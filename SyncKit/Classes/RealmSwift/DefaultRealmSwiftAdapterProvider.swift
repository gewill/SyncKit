//
//  DefaultRealmSwiftAdapterProvider.swift
//  Pods
//
//  Created by Manuel Entrena on 18/11/2018.
//

import Foundation
import CloudKit
import RealmSwift

public class DefaultRealmSwiftAdapterProvider: NSObject, AdapterProvider {
    
    let zoneID: CKRecordZone.ID
    let persistenceConfiguration: Realm.Configuration
    let targetConfiguration: Realm.Configuration
    private let historicalStores: [URL]
    let usesRecoveredStore: Bool
    let appGroup: String?
    public private(set) var adapter: RealmSwiftAdapter!
    
    public init(targetConfiguration: Realm.Configuration, zoneID: CKRecordZone.ID, appGroup: String? = nil) {
        self.targetConfiguration = targetConfiguration
        self.zoneID = zoneID
        self.appGroup = appGroup
        let paths = Self.storePaths(appGroup: appGroup)
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
        
        return RealmSwiftAdapter(persistenceRealmConfiguration: persistenceConfiguration, targetRealmConfiguration: targetConfiguration, recordZoneID: zoneID) {
            let path = self.persistenceConfiguration.fileURL!
            if self.historicalStores.count > 1 {
                try Self.recover(self.historicalStores, to: path, target: self.targetConfiguration)
            }
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
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
        let staging = directory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        let reader = DispatchQueue(label: "SyncKit.trackingStoreRecovery")
        try reader.sync {
            try autoreleasepool {
                try writeRecoveredStore(from: paths, to: staging.appendingPathComponent(destination.lastPathComponent),
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

    private static func writeRecoveredStore(from paths: [URL], to file: URL,
                                            target: Realm.Configuration, reader: DispatchQueue) throws {
        let config = RealmSwiftAdapter.defaultPersistenceConfiguration()
        var groups = [String: [SyncedEntity]]()
        let sources = try paths.map { path -> Realm in
            var source = config
            source.fileURL = path
            source.readOnly = true
            return try Realm(configuration: source, queue: reader)
        }
        for source in sources {
            // Shared graphs need relationship-aware reconciliation; leave them intact.
            guard source.objects(PendingRelationship.self).isEmpty else { throw CocoaError(.featureUnsupported) }
            for row in source.objects(SyncedEntity.self) {
                guard row.share == nil, row.entityType != "CKShare",
                      let state = SyncedEntityState(rawValue: row.state), state != .inserted else { throw CocoaError(.featureUnsupported) }
                groups[row.identifier, default: []].append(row)
            }
        }

        let local = try Realm(configuration: target)
        var localTypes = [String: String]()
        for schema in local.schema.objectSchema {
            guard let key = schema.primaryKeyProperty?.name else { throw CocoaError(.featureUnsupported) }
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
                let pendingWrite = states.contains(.new) || states.contains(.changed)
                let deleted = states.contains(.deleted)
                let state: SyncedEntityState
                if hasLocal {
                    if states.contains(.new) { state = .new }
                    else if states.contains(.changed) { state = .changed }
                    else if deleted { state = .new }
                    else { state = .synced }
                } else {
                    // An edit/delete disagreement with no local copy is restored by a full fetch.
                    guard deleted && !pendingWrite else { continue }
                    state = .deleted
                }
                let entry = SyncedEntity(entityType: rows[0].entityType, identifier: id, state: state.rawValue)
                if state != .synced {
                    var keys = Set(rows.filter { state != .deleted && $0.entityState == .changed }
                            .flatMap { $0.changedKeys?.components(separatedBy: ",") ?? [] })
                    keys.insert(SyncedEntity.recoveryKey)
                    entry.changedKeys = keys.sorted().joined(separator: ",")
                }
                // Use the delete's own baseline for conditional replay, never another store's revision.
                let baselines = rows.filter { state == .deleted && $0.entityState == .deleted }
                if let bytes = baselines.compactMap({ $0.record?.encodedRecord }).first {
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
