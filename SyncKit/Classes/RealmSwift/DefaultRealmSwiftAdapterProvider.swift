//
//  DefaultRealmSwiftAdapterProvider.swift
//  Pods
//
//  Created by Manuel Entrena on 18/11/2018.
//

import Foundation
import CloudKit
import RealmSwift

/// Raised when SyncKit cannot merge the tracking stores that earlier versions left at different paths.
/// Sync stays disabled until the stores can be merged, or until `CloudKitSynchronizer.eraseLocalMetadata()`
/// abandons them so that the next adapter starts from a fresh store. The stores themselves are kept.
public enum TrackingStoreRecoveryError: Error {
    /// The store holds shared records or unresolved relationships, which recovery does not reconcile.
    case unsupportedContent(URL)
    /// The store could not be copied or opened.
    case unreadableStore(URL, underlyingError: Error)
}

public class DefaultRealmSwiftAdapterProvider: NSObject, AdapterProvider {
    
    let zoneID: CKRecordZone.ID
    let persistenceConfiguration: Realm.Configuration
    let targetConfiguration: Realm.Configuration
    private let historicalStores: [URL]
    let usesRecoveredStore: Bool
    let appGroup: String?
    public private(set) var adapter: RealmSwiftAdapter!
    
    public convenience init(targetConfiguration: Realm.Configuration, zoneID: CKRecordZone.ID, appGroup: String? = nil) {
        self.init(targetConfiguration: targetConfiguration, zoneID: zoneID, appGroup: appGroup,
                  paths: Self.storePaths(appGroup: appGroup))
    }

    init(targetConfiguration: Realm.Configuration, zoneID: CKRecordZone.ID, appGroup: String?,
         paths: (active: URL, sources: [URL])) {
        self.targetConfiguration = targetConfiguration
        self.zoneID = zoneID
        self.appGroup = appGroup
        historicalStores = paths.sources
        usesRecoveredStore = paths.active.deletingLastPathComponent().lastPathComponent == "Recovered"
        var configuration = RealmSwiftAdapter.defaultPersistenceConfiguration()
        configuration.fileURL = paths.active
        persistenceConfiguration = configuration
        super.init()
        adapter = createAdapter()
    }
    
    public func cloudKitSynchronizer(_ synchronizer: CloudKitSynchronizer, modelAdapterForRecordZoneID recordZoneID: CKRecordZone.ID) -> ModelAdapter? {
        
        guard recordZoneID == zoneID else { return nil }
        
        if adapter.hasDeletedChangeTracking {
            // eraseLocalMetadata() discarded this adapter's store; keep syncing with a fresh one.
            adapter = createAdapter()
        }
        return adapter
    }
    
    public func cloudKitSynchronizer(_ synchronizer: CloudKitSynchronizer, zoneWasDeletedWithZoneID recordZoneID: CKRecordZone.ID) {
        
        let adapterHasSyncedBefore = adapter.serverChangeToken != nil
        if recordZoneID == zoneID && adapterHasSyncedBefore {
            
            adapter.deleteChangeTracking()
            synchronizer.removeModelAdapter(adapter)
            
            adapter = createAdapter()
            synchronizer.addModelAdapter(adapter)
        }
    }
    
    fileprivate func createAdapter() -> RealmSwiftAdapter {
        
        let path = persistenceConfiguration.fileURL!
        let sources = historicalStores
        let target = targetConfiguration
        let recovered = usesRecoveredStore
        return RealmSwiftAdapter(persistenceRealmConfiguration: persistenceConfiguration, targetRealmConfiguration: targetConfiguration, recordZoneID: zoneID, prepareStore: {
            if sources.count > 1 {
                try Self.recover(sources, to: path, target: target)
            }
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        }, discardStore: {
            // Resetting sync metadata gives up on histories that were never merged. Publishing the
            // Recovered directory (the commit marker) makes the next adapter start from a fresh store.
            guard recovered else { return }
            try? FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        })
    }
    
    // MARK: - File directory
    
    /**
     *  If using app groups, SyncKit offers the option to store its tracking database in the shared container so that it's
     *  accessible by SyncKit from any of the apps in the group. This method returns the path used in this case.
     *
     *  @param  appGroup   Identifier of an App Group this app belongs to.
     *
     *  @return File path, in the shared container, where SyncKit will store its tracking database.
     */
    
    public static func realmPath(appGroup: String?) -> String {
        storePaths(appGroup: appGroup).active.path
    }

    private static func storePaths(appGroup: String?) -> (active: URL, sources: [URL]) {
        let fm = FileManager.default
        let root = appGroup.map { fm.containerURL(forSecurityApplicationGroupIdentifier: $0)!.path }
            ?? applicationDocumentsDirectory()!
        let directory = URL(fileURLWithPath: root).appendingPathComponent("Realm", isDirectory: true)
        let canonical = directory.appendingPathComponent(realmFileName())
        let published = directory.appendingPathComponent("Recovered").appendingPathComponent(realmFileName())
        // The directory is the commit marker, even after SyncKit explicitly resets its store.
        if fm.fileExists(atPath: published.deletingLastPathComponent().path) { return (published, []) }
        var paths = [canonical, URL(fileURLWithPath: root + "Realm" + realmFileName())]
        if appGroup == nil, let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).last {
            let old = support.appendingPathComponent("com.mentrena.QSCloudKitSynchronizerRealm" + realmFileName())
            if !paths.contains(old) { paths.append(old) }
        }
        let existing = paths.filter { fm.fileExists(atPath: $0.path) }
        return (existing.count > 1 ? published : existing.first ?? canonical, existing)
    }

    static func recover(_ paths: [URL], to destination: URL, target: Realm.Configuration) throws {
        let fm = FileManager.default
        let published = destination.deletingLastPathComponent()
        if fm.fileExists(atPath: published.path) { return }
        let directory = published.deletingLastPathComponent()
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        removeAbandonedWorkDirectories(in: directory)
        let work = directory.appendingPathComponent(workDirectoryPrefix + UUID().uuidString, isDirectory: true)
        let staging = work.appendingPathComponent("Store", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        // Read writable copies: older file formats need an upgrade that read-only Realms cannot perform,
        // and the sources themselves must stay byte-for-byte intact.
        let snapshots = try paths.enumerated().map { index, path -> (path: URL, snapshot: URL) in
            let snapshot = work.appendingPathComponent("Source-\(index).realm")
            do {
                try fm.copyItem(at: path, to: snapshot)
            } catch {
                throw TrackingStoreRecoveryError.unreadableStore(path, underlyingError: error)
            }
            return (path, snapshot)
        }
        let reader = DispatchQueue(label: "SyncKit.trackingStoreRecovery")
        try reader.sync {
            try autoreleasepool {
                try writeRecoveredStore(from: snapshots, to: staging.appendingPathComponent(destination.lastPathComponent),
                                        target: target, reader: reader)
            }
        }
        do {
            try fm.moveItem(at: staging, to: published)
        } catch {
            // A concurrent opener may have committed the same recovery first.
            if !fm.fileExists(atPath: destination.path) { throw error }
        }
    }

    private static let workDirectoryPrefix = ".recovery-"

    /// Work directories from an interrupted attempt are never published. The age check leaves alone an
    /// attempt that another process may still be running.
    private static func removeAbandonedWorkDirectories(in directory: URL) {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where name.hasPrefix(workDirectoryPrefix) {
            let url = directory.appendingPathComponent(name)
            let modified = (try? fm.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
            if modified.map({ $0.timeIntervalSinceNow < -600 }) ?? true {
                try? fm.removeItem(at: url)
            }
        }
    }

    private static func writeRecoveredStore(from sources: [(path: URL, snapshot: URL)], to file: URL,
                                            target: Realm.Configuration, reader: DispatchQueue) throws {
        let config = RealmSwiftAdapter.defaultPersistenceConfiguration()
        var groups = [String: [SyncedEntity]]()
        var openSources = [Realm]()
        for (path, snapshot) in sources {
            var configuration = config
            configuration.fileURL = snapshot
            let source: Realm
            do {
                source = try Realm(configuration: configuration, queue: reader)
            } catch {
                throw TrackingStoreRecoveryError.unreadableStore(path, underlyingError: error)
            }
            openSources.append(source)
            // Shared graphs need relationship-aware reconciliation; leave them intact.
            guard source.objects(PendingRelationship.self).isEmpty else { throw TrackingStoreRecoveryError.unsupportedContent(path) }
            for row in source.objects(SyncedEntity.self) {
                guard row.share == nil, row.entityType != "CKShare",
                      let state = SyncedEntityState(rawValue: row.state), state != .inserted else {
                    throw TrackingStoreRecoveryError.unsupportedContent(path)
                }
                groups[row.identifier, default: []].append(row)
            }
        }

        let local = try Realm(configuration: target)
        var localTypes = [String: String]()
        for schema in local.schema.objectSchema {
            // Like RealmSwiftAdapter.setup(), only types with a primary key are synchronized.
            guard !schema.isEmbedded, let key = schema.primaryKeyProperty?.name else { continue }
            for object in local.dynamicObjects(schema.className) {
                guard let value = object[key] else { throw CocoaError(.fileReadCorruptFile) }
                localTypes[schema.className + "." + String(describing: value)] = schema.className
            }
        }
        var output = config
        output.fileURL = file
        let merged = try Realm(configuration: output)
        try merged.write {
            for (id, rows) in groups {
                let hasLocal = localTypes[id] != nil
                let states = rows.map { $0.entityState }
                // Keys edited locally and not uploaded yet. A `.new` row also records edits made after its insert.
                let editKeys = Set(rows.filter { $0.entityState == .changed || $0.entityState == .new }
                    .flatMap { $0.changedKeys?.components(separatedBy: ",") ?? [] })
                    .filter { !$0.isEmpty && !$0.hasPrefix("$") }
                let pendingWrite = states.contains(.new) || states.contains(.changed)
                let state: SyncedEntityState
                if hasLocal {
                    if states.contains(.changed) || !editKeys.isEmpty { state = .changed }
                    else if states.contains(.new) { state = .new }
                    // Synced, or deleted in another history: keep the bill and reconcile it with the cloud copy.
                    else { state = .synced }
                } else {
                    // An edit/delete disagreement with no local copy is restored by a full fetch.
                    guard states.contains(.deleted) && !pendingWrite else { continue }
                    state = .deleted
                }
                let entry = SyncedEntity(entityType: rows[0].entityType, identifier: id, state: state.rawValue)
                let keys = (state == .changed ? editKeys : []).union([SyncedEntity.recoveryKey])
                entry.changedKeys = keys.sorted().joined(separator: ",")
                // Use a delete's own baseline for conditional replay, never another store's revision.
                let baselines = rows.filter { $0.entityState == .deleted }.compactMap { $0.record?.encodedRecord }
                if state == .deleted, let bytes = newestRecordData(baselines) {
                    let record = Record()
                    record.encodedRecord = bytes
                    entry.record = record
                }
                merged.add(entry)
            }
            for (id, type) in localTypes where groups[id] == nil {
                let entry = SyncedEntity(entityType: type, identifier: id, state: SyncedEntityState.new.rawValue)
                entry.changedKeys = SyncedEntity.recoveryKey
                merged.add(entry)
            }
        }
    }

    /// When several histories hold a pending delete, only the newest baseline can still match the
    /// server: CloudKit revisions only move forward.
    private static func newestRecordData(_ candidates: [Data]) -> Data? {
        func modificationDate(_ data: Data) -> Date {
            guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return .distantPast }
            coder.requiresSecureCoding = false
            defer { coder.finishDecoding() }
            return CKRecord(coder: coder)?.modificationDate ?? .distantPast
        }
        return candidates.max { modificationDate($0) < modificationDate($1) }
    }

    fileprivate static func applicationDocumentsDirectory() -> String? {
        #if os(iOS) || os(watchOS) || os(tvOS)
        return NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true).last
        #else
        let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        return urls.last?.appendingPathComponent("com.mentrena.QSCloudKitSynchronizer").path
        #endif
    }
    
    fileprivate static func realmFileName() -> String {
        return "QSSyncStore.realm"
    }
    
}
