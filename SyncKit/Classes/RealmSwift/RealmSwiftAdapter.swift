//
//  RealmSwiftAdapter.swift
//  Pods
//
//  Created by Manuel Entrena on 29/08/2017.
//
//

import CloudKit
import RealmSwift
import Realm
import Foundation

func executeOnMainQueue(_ closure: () -> ()) {
    if Thread.isMainThread {
        closure()
    } else {
        DispatchQueue.main.sync {
            closure()
        }
    }
}

extension Realm {
    public func safeWrite(_ block: (() throws -> Void)) throws {
        if isInWriteTransaction {
            try block()
        } else {
            try write(block)
        }
    }
}

public protocol RealmSwiftAdapterDelegate: AnyObject {
    
    /**
     *  Asks the delegate to resolve conflicts for a managed object when using a custom mergePolicy.
     *  The delegate is expected to examine the change dictionary and optionally apply any of those changes to the managed object.
     *
     *  @param adapter    The `RealmSwiftAdapter` that is providing the changes.
     *  @param changeDictionary Dictionary containing keys and values with changes for the managed object. Values can be [NSNull null] to represent a nil value.
     *  @param object           The `RLMObject` that has changed on iCloud.
     */
    func realmSwiftAdapter(_ adapter:RealmSwiftAdapter, gotChanges changes: [String: Any], object: Object)

    /**
     *  Called when a conflict between a local modification and a server deletion is detected.
     *
     *  @param adapter The `RealmSwiftAdapter` detecting the conflict.
     *  @param object The local `Object` that has been modified.
     *  @param recordID The `CKRecord.ID` of the record that was deleted on the server.
     *
     *  @return A boolean indicating whether the local modification should be preserved (true) or the deletion should be applied (false).
     */
    func realmSwiftAdapter(_ adapter: RealmSwiftAdapter, shouldIgnoreServerDeletionOf object: Object, with recordID: CKRecord.ID) -> Bool
}

public protocol RealmSwiftAdapterRecordProcessing: AnyObject {
    
    /**
     *  Called by the adapter before copying a property from the Realm object to the CloudKit record to upload to CloudKit.
     *  The method can then apply custom logic to encode the property in the record.
     *
     *  @param propertyname     The name of the property that is being processed
     *  @param object   The `RLMObject` that is going to have its record uploaded.
     *  @param record   The `CKRecord` that is being configured before being sent to CloudKit.
     *
     *  @return Boolean indicating whether the adapter should process property normally. Return false if property was already handled in this method.
     */
    func shouldProcessPropertyBeforeUpload(propertyName: String, object: Object, record: CKRecord) -> Bool
    
    /**
     *  Called by the adapter before copying a property from the CloudKit record that was just downloaded to the Realm object.
     *  The method can apply custom logic to save the property from the record to the object. An object implementing this method *should not* change the record itself.
     *
     *  @param propertyname     The name of the property that is being processed
     *  @param object   The `RLMObject` that corresponds to the downloaded record.
     *  @param record   The `CKRecord` that was downloaded from CloudKit.
     *
     *  @return Boolean indicating whether the adapter should process property normally. Return false if property was already handled in this method.
     */
    func shouldProcessPropertyInDownload(propertyName: String, object: Object, record: CKRecord) -> Bool
}

/**
 *  An object conforming to this protocol can provide information about which properties should be treated as counters.
 *  Counters are merged using delta addition instead of Last-Write-Wins during conflicts.
 */
@objc public protocol RealmSwiftAdapterCounterProvider: AnyObject {
    func isCounter(property: String, in entityType: String) -> Bool
}

struct ChildRelationship {
    
    let parentEntityName: String
    let childEntityName: String
    let childParentKey: String
}

struct RealmProvider {
    
    let persistenceRealm: Realm
    let targetRealm: Realm
    
    init?(persistenceConfiguration: Realm.Configuration, targetConfiguration: Realm.Configuration) {
        
        guard let persistenceRealm = try? Realm(configuration: persistenceConfiguration),
            let targetRealm = try? Realm(configuration: targetConfiguration) else {
                return nil
        }
        
        self.persistenceRealm = persistenceRealm
        self.targetRealm = targetRealm
    }
}

struct ObjectUpdate {
    
    enum UpdateType {
        case insertion
        case update
        case deletion
    }
    
    let object: Object
    let identifier: String
    let entityType: String
    let updateType: UpdateType
    let changes: [PropertyChange]?
}


public class RealmSwiftAdapter: NSObject, ModelAdapter {
    
    static let shareRelationshipKey = "com.syncKit.shareRelationship"
    
    public let persistenceRealmConfiguration: Realm.Configuration
    public let targetRealmConfiguration: Realm.Configuration
    public let zoneID: CKRecordZone.ID
    public var mergePolicy: MergePolicy = .server
    public weak var delegate: RealmSwiftAdapterDelegate?
    public weak var recordProcessingDelegate: RealmSwiftAdapterRecordProcessing?
    public weak var counterProvider: RealmSwiftAdapterCounterProvider?
    public var forceDataTypeInsteadOfAsset: Bool = false
    
    private lazy var tempFileManager: TempFileManager = {
        TempFileManager(identifier: "\(recordZoneID.ownerName).\(recordZoneID.zoneName)")
    }()
    
    var realmProvider: RealmProvider!
    
    var collectionNotificationTokens = [NotificationToken]()
    var objectNotificationTokens = [String: NotificationToken]()
    var pendingTrackingUpdates = [ObjectUpdate]()
    var childRelationships = [String: Array<ChildRelationship>]()
    var modelTypes = [String: Object.Type]()
    var entityEncryptedFields = [String: Set<String>]()
    public private(set) var hasChanges = false
    
    /* Should be initialized on main queue */
    public init(persistenceRealmConfiguration: Realm.Configuration, targetRealmConfiguration: Realm.Configuration, recordZoneID: CKRecordZone.ID) {
        
        self.persistenceRealmConfiguration = persistenceRealmConfiguration
        self.targetRealmConfiguration = targetRealmConfiguration
        self.zoneID = recordZoneID
        
        super.init()
        
        executeOnMainQueue {
            setupTypeNamesLookup()
            setupEncryptedFields()
            setup()
            setupChildrenRelationshipsLookup()
        }
    }
    
    deinit {
        invalidateRealmAndTokens()
    }
    
    func invalidateRealmAndTokens() {
        executeOnMainQueue {
            for token in objectNotificationTokens.values {
                token.invalidate()
            }
            objectNotificationTokens.removeAll()
            for token in collectionNotificationTokens {
                token.invalidate()
            }
            collectionNotificationTokens.removeAll()
            
            realmProvider?.persistenceRealm.invalidate()
            realmProvider = nil
        }
    }
    
    static public func defaultPersistenceConfiguration() -> Realm.Configuration {
        
        var configuration = Realm.Configuration()
        configuration.schemaVersion = 1
        configuration.migrationBlock = { migration, oldSchemaVersion in
            
        }
        configuration.objectTypes = [SyncedEntity.self, Record.self, PendingRelationship.self, ServerToken.self]
        return configuration
    }
    
    func setupTypeNamesLookup() {
        
        targetRealmConfiguration.objectTypes?.forEach { objectType in

            modelTypes[objectType.className()] = objectType as? Object.Type
        }
    }
    
    func setupEncryptedFields() {
        if #available(iOS 15, OSX 12, watchOS 8.0, *) {
            targetRealmConfiguration.objectTypes?.forEach { objectType in
                if let encryptedEntity = objectType as? EncryptedObject.Type {
                    entityEncryptedFields[objectType.className()] = Set(encryptedEntity.encryptedFields())
                }
            }
        }
    }
    
    func setup() {
        
        realmProvider = RealmProvider(persistenceConfiguration: persistenceRealmConfiguration, targetConfiguration: targetRealmConfiguration)

        guard let provider = realmProvider else {
            debugPrint("RealmSwiftAdapter: Failed to initialize RealmProvider — check Realm configuration and migration")
            return
        }

        let needsInitialSetup = provider.persistenceRealm.objects(SyncedEntity.self).count <= 0

        for schema in provider.targetRealm.schema.objectSchema {

            let objectClass = realmObjectClass(name: schema.className)
            guard let primaryKey = objectClass.primaryKey() else {
                debugPrint("RealmSwiftAdapter: Skipping \(schema.className) — no primary key defined")
                continue
            }
            let results = provider.targetRealm.objects(objectClass)
            
            // Register for collection notifications
            let token = results.observe({ [weak self] (collectionChange) in
                guard let self = self else { return }
                switch collectionChange {
                case .update(_, _, let insertions, _):
                    
                    for index in insertions {
                        
                        let object = results[index]
                        let identifier = self.getStringIdentifier(for: object, usingPrimaryKey: primaryKey)
                        /* This can be called during a transaction, and it's illegal to add a notification block during a transaction,
                         * so we keep all the insertions in a list to be processed as soon as the realm finishes the current transaction
                         */
                        if object.realm!.isInWriteTransaction {
                            
                            self.pendingTrackingUpdates.append(ObjectUpdate(object: object, identifier: identifier, entityType: schema.className, updateType: .insertion, changes: nil))
                        } else {
                            
                            self.updateTracking(insertedObject: object, identifier: identifier, entityName: schema.className, provider: self.realmProvider)
                        }
                    }
                default: break
                }
            })
            collectionNotificationTokens.append(token)
            
            // Register for object updates
            for object in results {
                
                let identifier = self.getStringIdentifier(for: object, usingPrimaryKey: primaryKey)
                let token = object.observe({ [weak self] (change) in
                    
                    switch change {
                    case .change(_, let properties):
                        
                        if object.realm!.isInWriteTransaction {
                            
                            self?.pendingTrackingUpdates.append(ObjectUpdate(object: object, identifier: identifier, entityType: schema.className, updateType: .update, changes: properties))
                        } else {
                            
                            self?.updateTracking(objectIdentifier: identifier, entityName: schema.className, inserted: false, deleted: false, changes: properties, realmProvider: self!.realmProvider)
                        }
                    case .deleted:
                        
                        if object.realm!.isInWriteTransaction {
                            
                            self?.pendingTrackingUpdates.append(ObjectUpdate(object: object, identifier: identifier, entityType: schema.className, updateType: .deletion, changes: nil))
                        } else {
                            
                            self?.updateTracking(objectIdentifier: identifier, entityName: schema.className, inserted: false, deleted: true, changes: nil, realmProvider: self!.realmProvider)
                        }
                        break
                    default: break
                    }
                })
                
                if needsInitialSetup {
                    
                    createSyncedEntity(entityType: schema.className, identifier: identifier, realm: provider.persistenceRealm)
                }
                
                objectNotificationTokens[identifier] = token
            }
        }
        
        let token = provider.targetRealm.observe { [weak self] (_, _) in
            
            self?.enqueueObjectUpdates()
        }
        collectionNotificationTokens.append(token)
        
        updateHasChanges(realm: provider.persistenceRealm)
        
        if hasChanges {
            
            NotificationCenter.default.post(name: .ModelAdapterHasChangesNotification, object: self)
        }
    }
    
    func realmObjectClass(name: String) -> Object.Type {
        
        return modelTypes[name]!
    }
    
    func updateHasChanges(realm: Realm) {
        
        let predicate = NSPredicate(format: "state != %ld", SyncedEntityState.synced.rawValue)
        let results = realm.objects(SyncedEntity.self).filter(predicate)
        
        hasChanges = results.count > 0;
    }
    
    func setupChildrenRelationshipsLookup() {

        guard let provider = realmProvider else { return }

        childRelationships.removeAll()

        for objectSchema in provider.targetRealm.schema.objectSchema {
            
            let objectClass = realmObjectClass(name: objectSchema.className)
            if let parentClass = objectClass.self as? ParentKey.Type {
                let parentKey = parentClass.parentKey()
                let parentProperty = objectSchema.properties.first { $0.name == parentKey }
                
                let parentClassName = parentProperty!.objectClassName!
                let relationship = ChildRelationship(parentEntityName: parentClassName, childEntityName: objectSchema.className, childParentKey: parentKey)
                if childRelationships[parentClassName] == nil {
                    childRelationships[parentClassName] = Array<ChildRelationship>()
                }
                childRelationships[parentClassName]!.append(relationship)
            }
        }
    }
    
    func enqueueObjectUpdates() {
        
        if pendingTrackingUpdates.count > 0 {
            
            if realmProvider.targetRealm.isInWriteTransaction {
                
                DispatchQueue.main.async { [weak self] in
                    self?.enqueueObjectUpdates()
                }
            } else {
                
                updateObjectTracking()
            }
        }
    }
    
    func updateObjectTracking() {
        
        for update in pendingTrackingUpdates {
            
            if update.updateType == .insertion {
                
                updateTracking(insertedObject: update.object, identifier: update.identifier, entityName: update.entityType, provider: realmProvider)
            } else {
                
                updateTracking(objectIdentifier: update.identifier, entityName: update.entityType, inserted: false, deleted: (update.updateType == .deletion), changes: update.changes, realmProvider: realmProvider)
            }
        }
        
        pendingTrackingUpdates.removeAll()
    }
    
    func updateTracking(insertedObject: Object, identifier: String, entityName: String, provider: RealmProvider) {
        
        let token = insertedObject.observe { [weak self] (change) in
            
            switch change {
            case .change(_, let properties):
                
                self?.updateTracking(objectIdentifier: identifier, entityName: entityName, inserted: false, deleted: false, changes: properties, realmProvider: provider)
            case .deleted:
                
                self?.updateTracking(objectIdentifier: identifier, entityName: entityName, inserted: false, deleted: true, changes: nil, realmProvider: self!.realmProvider)
            default: break
            }
        }
        
        objectNotificationTokens[identifier] = token
        
        updateTracking(objectIdentifier: identifier, entityName: entityName, inserted: true, deleted: false, changes: nil, realmProvider: provider)
    }
    
    func updateTracking(objectIdentifier: String, entityName: String, inserted: Bool, deleted: Bool, changes: [PropertyChange]?, realmProvider: RealmProvider) {
        
        var isNewChange = false
        let identifier = "\(entityName).\(objectIdentifier)"
        let syncedEntity = getSyncedEntity(objectIdentifier: identifier, realm: realmProvider.persistenceRealm)
        
        if deleted {
            
            isNewChange = true
            
            if let syncedEntity = syncedEntity {
                try? realmProvider.persistenceRealm.safeWrite {
                    syncedEntity.state = SyncedEntityState.deleted.rawValue
                    syncedEntity.updated = Date()
                }
            }
            
            if let token = objectNotificationTokens[objectIdentifier] {
                
                objectNotificationTokens.removeValue(forKey: objectIdentifier)
                token.invalidate()
            }
            
        } else if syncedEntity == nil {
            
            self.createSyncedEntity(entityType: entityName, identifier: objectIdentifier, realm: self.realmProvider.persistenceRealm)
            
            if inserted {
                isNewChange = true
            }
            
        } else if !inserted {
            
            guard let syncedEntity = syncedEntity else {
                return
            }
            
            isNewChange = true
            
            var changedKeys: NSMutableSet
            if let changedKeysString = syncedEntity.changedKeys {
                changedKeys = NSMutableSet(array: changedKeysString.components(separatedBy: ","))
            } else {
                changedKeys = NSMutableSet()
            }
            
            if let changes = changes {
                for propertyChange in changes {
                    
                    changedKeys.add(propertyChange.name)
                }
            }
            
            try? realmProvider.persistenceRealm.safeWrite {
                syncedEntity.changedKeys = (changedKeys.allObjects as! [String]).joined(separator: ",")
                syncedEntity.updated = Date()
                syncedEntity.version += 1
                if syncedEntity.state == SyncedEntityState.synced.rawValue && !syncedEntity.changedKeys!.isEmpty {
                    syncedEntity.state = SyncedEntityState.changed.rawValue
                    // If state was New then leave it as that
                }
            }
        }
        
        if !hasChanges && isNewChange {
            hasChanges = true
            NotificationCenter.default.post(name: .ModelAdapterHasChangesNotification, object: self)
        }
    }
    
    func commitTargetWriteTransactionWithoutNotifying() {
        
        try? realmProvider.targetRealm.commitWrite(withoutNotifying: Array(objectNotificationTokens.values))
    }
    
    @discardableResult
    func createSyncedEntity(entityType: String, identifier: String, realm: Realm) -> SyncedEntity {
        
        let syncedEntity = SyncedEntity(entityType: entityType, identifier: "\(entityType).\(identifier)", state: SyncedEntityState.new.rawValue)
        syncedEntity.updated = Date()
        
        try? realm.safeWrite {
            realm.add(syncedEntity)
        }
        
        return syncedEntity
    }
    
    func createSyncedEntity(record: CKRecord, realmProvider: RealmProvider) -> SyncedEntity {
        
        let syncedEntity = SyncedEntity(entityType: record.recordType, identifier: record.recordID.recordName, state: SyncedEntityState.synced.rawValue)
        
        realmProvider.persistenceRealm.add(syncedEntity)
        
        let objectClass = realmObjectClass(name: record.recordType)
        let primaryKey = objectClass.primaryKey()!
        let objectIdentifier = getObjectIdentifier(for: syncedEntity)
        let object = objectClass.init()
        object.setValue(objectIdentifier, forKey: primaryKey)
        realmProvider.targetRealm.add(object)
        
        return syncedEntity;

    }
    
    func getObjectIdentifier(for syncedEntity: SyncedEntity) -> Any {

        let range = syncedEntity.identifier.range(of: syncedEntity.entityType)!
        let index = syncedEntity.identifier.index(range.upperBound, offsetBy: 1)
        let objectIdentifier = String(syncedEntity.identifier[index...])
        let objectClass = realmObjectClass(name: syncedEntity.entityType)
        
        guard let objectSchema = objectClass.sharedSchema(),
              let keyType = objectSchema.primaryKeyProperty?.type else {
            return objectIdentifier
        }
        
        switch keyType {
        case .int:
            return Int(objectIdentifier)!
        case .objectId:
            return try! ObjectId(string: objectIdentifier)
        case .string:
            return objectIdentifier
        default:
            return objectIdentifier
        }
    }
    
    func getObjectIdentifier(stringObjectId: String, entityType: String) -> Any? {
        let objectClass = realmObjectClass(name: entityType)
        guard let schema = objectClass.sharedSchema(),
              let keyType = schema.primaryKeyProperty?.type else {
            return nil
        }
        
        switch keyType {
        case .int:
            return Int(stringObjectId)!
        case .objectId:
            return try! ObjectId(string: stringObjectId)
        case .string:
            return stringObjectId
        default:
            return stringObjectId
        }
    }
    
    func syncedEntity(for object: Object, realm: Realm) -> SyncedEntity? {
        
        let objectClass = realmObjectClass(name: object.objectSchema.className)
        let primaryKey = objectClass.primaryKey()!
        let identifier = object.objectSchema.className + "." + getStringIdentifier(for: object, usingPrimaryKey: primaryKey)
        return getSyncedEntity(objectIdentifier: identifier, realm: realm)
    }
    
    @available(iOS 15, OSX 12, watchOS 8.0, *)
    func syncedEntityForRecordZoneShare(realm: Realm) -> SyncedEntity? {
        return getSyncedEntity(objectIdentifier: CKRecordNameZoneWideShare, realm: realm)
    }
    
    func getStringIdentifier(for object: Object, usingPrimaryKey key: String) -> String {

        let objectId = object.value(forKey: key)
        if let value = objectId as? CustomStringConvertible {
            return String(describing: value)
        } else {
            return objectId as! String
        }
    }
    
    func getSyncedEntity(objectIdentifier: String, realm: Realm) -> SyncedEntity? {
        
        return realm.object(ofType: SyncedEntity.self, forPrimaryKey: objectIdentifier)
    }
    
    func shouldIgnore(key: String) -> Bool {
        
        return CloudKitSynchronizer.metadataKeys.contains(key)
    }
    
    func applyChanges(in record: CKRecord, to object: Object, syncedEntity: SyncedEntity, realmProvider: RealmProvider) {
        
        if syncedEntity.state == SyncedEntityState.changed.rawValue || syncedEntity.state == SyncedEntityState.new.rawValue {
        
            if mergePolicy == .server {
                
                for property in object.objectSchema.properties {
                    if shouldIgnore(key: property.name) {
                        continue
                    }
                    if property.type == PropertyType.linkingObjects {
                        continue
                    }
                    
                    applyChange(property: property.name, record: record, object: object, syncedEntity: syncedEntity, realmProvider: realmProvider)
                }
                
                let serverVersion = record[CloudKitSynchronizer.entityVersionKey] as? Int ?? 0
                syncedEntity.version = max(syncedEntity.version, serverVersion)
                
            } else if mergePolicy == .client {
                
                let changedKeysString = syncedEntity.changedKeys ?? ""
                var changedKeys: [String] = changedKeysString.components(separatedBy: ",")
                let serverDate = record.modificationDate
                let localDate = syncedEntity.updated
                let serverVersion = record[CloudKitSynchronizer.entityVersionKey] as? Int ?? 0
                let localVersion = syncedEntity.version
                
                let serverIsNewer = serverDate != nil && localDate != nil && serverDate! > localDate!
                let serverIsSeverelyOutdated = serverVersion > localVersion
                var keysToRemove = [String]()
                
                for property in object.objectSchema.properties {
                    
                    if property.type == PropertyType.linkingObjects {
                        continue
                    }
                    
                    if !shouldIgnore(key: property.name) {
                        let isModifiedLocally = changedKeys.contains(property.name)
                        let isNew = syncedEntity.state == SyncedEntityState.new.rawValue
                        
                        if !isModifiedLocally || serverIsSeverelyOutdated || serverIsNewer || (isNew && object.value(forKey: property.name) == nil) {
                            applyChange(property: property.name, record: record, object: object, syncedEntity: syncedEntity, realmProvider: realmProvider)
                            if isModifiedLocally && (serverIsSeverelyOutdated || serverIsNewer) {
                                keysToRemove.append(property.name)
                            }
                        }
                    }
                }
                
                if !keysToRemove.isEmpty {
                    changedKeys.removeAll { keysToRemove.contains($0) }
                    syncedEntity.changedKeys = changedKeys.joined(separator: ",")
                    if syncedEntity.changedKeys?.isEmpty == true {
                        syncedEntity.state = SyncedEntityState.synced.rawValue
                    }
                }
                
                syncedEntity.version = max(syncedEntity.version, serverVersion)
                
            } else if mergePolicy == .custom {
                
                var recordChanges = [String: Any]()
                
                for property in object.objectSchema.properties {
                    
                    if property.type == PropertyType.linkingObjects {
                        continue
                    }
                    
                    if !shouldIgnore(key: property.name) &&
                        !(record[property.name] is CKRecord.Reference) {

                        if let asset = record[property.name] as? CKAsset {
                            recordChanges[property.name] = asset.fileURL != nil ? NSData(contentsOf: asset.fileURL!) : NSNull()
                        } else {
                            recordChanges[property.name] = record[property.name] ?? NSNull()
                        }
                    }
                }
                
                delegate?.realmSwiftAdapter(self, gotChanges: recordChanges, object: object)
                
                let serverVersion = record[CloudKitSynchronizer.entityVersionKey] as? Int ?? 0
                syncedEntity.version = max(syncedEntity.version, serverVersion)
                
            }
        } else {
            
            for property in object.objectSchema.properties {
                
                if shouldIgnore(key: property.name) {
                    continue
                }
                if property.isArray || property.type == PropertyType.linkingObjects {
                    continue
                }
                
                applyChange(property: property.name, record: record, object: object, syncedEntity: syncedEntity, realmProvider: realmProvider)
            }
            
            let serverVersion = record[CloudKitSynchronizer.entityVersionKey] as? Int ?? 0
            syncedEntity.version = max(syncedEntity.version, serverVersion)
        }
    }
    
    func applyChange(property key: String, record: CKRecord, object: Object, syncedEntity: SyncedEntity, realmProvider: RealmProvider) {
        
        if key == object.objectSchema.primaryKeyProperty!.name {
            return
        }
        
        guard let property = object.objectSchema[key] else {
            return
        }
        
        if let recordProcessingDelegate = recordProcessingDelegate,
           !recordProcessingDelegate.shouldProcessPropertyInDownload(propertyName: key, object: object, record: record) {
            return
        }
        
        let currentValue = object.value(forKey: key)
        
        if let encrypted = entityEncryptedFields[syncedEntity.entityType],
           encrypted.contains(key) {
            if #available(iOS 15, OSX 12, watchOS 8.0, *) {
                let newValue = record.encryptedValues[key]
                if !isEquivalent(currentValue, newValue) {
                    object.setValue(newValue, forKey: key)
                }
            }
        } else if property.isArray,
                  let rlmArray = currentValue as? RLMArray<AnyObject> {
            let serverValue = record[key]
            let ancestorRecord = getRecord(for: syncedEntity)
            let ancestorValue = ancestorRecord?[key]
            
            applyListChanges(property: key, rlmArray: rlmArray, serverValue: serverValue, ancestorValue: ancestorValue, syncedEntity: syncedEntity)
            
        } else {
            let value = record[key]
            if let reference = value as? CKRecord.Reference {
                // Save relationship to be applied after all records have been downloaded and persisted
                // to ensure target of the relationship has already been created
                let recordName = reference.recordID.recordName
                let separatorRange = recordName.range(of: ".")!
                let objectIdentifier = String(recordName[separatorRange.upperBound...])
                savePendingRelationship(name: key, syncedEntity: syncedEntity, targetIdentifier: objectIdentifier, realm: realmProvider.persistenceRealm)
            } else if let asset = value as? CKAsset {
                if let fileURL = asset.fileURL,
                    let data =  NSData(contentsOf: fileURL) {
                    if !isEquivalent(currentValue, data) {
                        object.setValue(data, forKey: key)
                    }
                }
            } else if value != nil || object.objectSchema[key]?.isOptional == true {
                var finalValue = value
                if let counterProvider = counterProvider,
                   counterProvider.isCounter(property: key, in: syncedEntity.entityType),
                   let serverValue = value as? NSNumber,
                   let localValue = currentValue as? NSNumber {

                    let ancestorRecord = getRecord(from: syncedEntity.lastSyncedRecord)
                    let ancestorValue = (ancestorRecord?[key] as? NSNumber) ?? NSNumber(value: 0)
                    let delta = localValue.doubleValue - ancestorValue.doubleValue
                    finalValue = NSNumber(value: serverValue.doubleValue + delta)
                }

                if !isEquivalent(currentValue, finalValue) {
                    object.setValue(finalValue, forKey: key)
                }
            }
        }
    }
    
    func isEquivalent(_ value1: Any?, _ value2: Any?) -> Bool {
        if value1 == nil && value2 == nil { return true }
        guard let v1 = value1, let v2 = value2 else { return false }
        
        if let d1 = v1 as? Data, let d2 = v2 as? Data {
            return d1 == d2
        } else if let s1 = v1 as? String, let s2 = v2 as? String {
            return s1 == s2
        } else if let n1 = v1 as? NSNumber, let n2 = v2 as? NSNumber {
            return n1 == n2
        } else if let date1 = v1 as? Date, let date2 = v2 as? Date {
            return date1 == date2
        }
        
        return false
    }

    func applyListChanges(property key: String, rlmArray: RLMArray<AnyObject>, serverValue: Any?, ancestorValue: Any?, syncedEntity: SyncedEntity) {
        let serverItems = serverValue as? [Any] ?? []
        let ancestorItems = ancestorValue as? [Any] ?? []
        
        var currentLocalItems = [Any]()
        for i in 0..<rlmArray.count {
            currentLocalItems.append(rlmArray.object(at: i))
        }
        
        let serverIds = Set(serverItems.map { identifierForItem($0) })
        let ancestorIds = Set(ancestorItems.map { identifierForItem($0) })
        let localIds = Set(currentLocalItems.map { identifierForItem($0) })
        
        let localAdditions = localIds.subtracting(ancestorIds)
        let localDeletions = ancestorIds.subtracting(localIds)
        
        let finalIds = serverIds.union(localAdditions).subtracting(localDeletions)
        
        // Update list
        // Remove items no longer in finalIds
        var i = 0
        while i < Int(rlmArray.count) {
            let item = rlmArray.object(at: UInt(i))
            if !finalIds.contains(identifierForItem(item)) {
                rlmArray.removeObject(at: UInt(i))
            } else {
                i += 1
            }
        }
        
        // Add new items from finalIds
        let currentIds = Set((0..<Int(rlmArray.count)).map { identifierForItem(rlmArray.object(at: UInt($0))) })
        let idsToAdd = finalIds.subtracting(currentIds)
        
        for id in idsToAdd {
            // Find item in local or server
            if let item = currentLocalItems.first(where: { identifierForItem($0) == id }) {
                rlmArray.add(item as AnyObject)
            } else if let serverItem = serverItems.first(where: { identifierForItem($0) == id }) {
                let itemID = identifierForItem(serverItem)
                if let separatorRange = itemID.range(of: ".") {
                    let entityName = String(itemID[..<separatorRange.lowerBound])
                    let objectIdentifier = String(itemID[separatorRange.upperBound...])
                    
                    if modelTypes[entityName] != nil {
                        savePendingRelationship(name: key, syncedEntity: syncedEntity, targetIdentifier: objectIdentifier, realm: realmProvider.persistenceRealm)
                    } else {
                        rlmArray.add(serverItem as AnyObject)
                    }
                } else {
                    rlmArray.add(serverItem as AnyObject)
                }
            }
        }
    }

    func identifierForItem(_ item: Any) -> String {
        if let target = item as? Object {
            let className = target.objectSchema.className
            let primaryKey = target.objectSchema.primaryKeyProperty!.name
            let targetIdentifier = self.getStringIdentifier(for: target, usingPrimaryKey: primaryKey)
            return "\(className).\(targetIdentifier)"
        }
        
        let desc = "\(item)"
        if desc.contains("recordName="),
           let recordNameRange = desc.range(of: "recordName=") {
            let remaining = desc[recordNameRange.upperBound...]
            if let commaRange = remaining.range(of: ",") {
                return String(remaining[..<commaRange.lowerBound])
            } else if let bracketRange = remaining.range(of: ">") {
                return String(remaining[..<bracketRange.lowerBound])
            }
        }
        
        if let reference = item as? CKRecord.Reference {
            return reference.recordID.recordName
        } else if let recordID = (item as AnyObject).value(forKey: "recordID") as? CKRecord.ID {
            return recordID.recordName
        }
        
        return desc
    }
    
    func savePendingRelationship(name: String, syncedEntity: SyncedEntity, targetIdentifier: String, realm: Realm) {
        
        let pendingRelationship = PendingRelationship()
        pendingRelationship.relationshipName = name
        pendingRelationship.forSyncedEntity = syncedEntity
        pendingRelationship.targetIdentifier = targetIdentifier
        realm.add(pendingRelationship)
    }
    
    func saveShareRelationship(for entity: SyncedEntity, record: CKRecord) {
        
        if let share = record.share {
            let relationship = PendingRelationship()
            relationship.relationshipName = RealmSwiftAdapter.shareRelationshipKey
            relationship.targetIdentifier = share.recordID.recordName
            relationship.forSyncedEntity = entity
            entity.realm?.add(relationship)
        }
    }
    
    func applyPendingRelationships(realmProvider: RealmProvider) {
        
        let pendingRelationships = realmProvider.persistenceRealm.objects(PendingRelationship.self)
        
        if pendingRelationships.count == 0 {
            return
        }
        
        realmProvider.persistenceRealm.beginWrite()
        realmProvider.targetRealm.beginWrite()
        for relationship in pendingRelationships {
            
            let entity = relationship.forSyncedEntity
            
            guard let syncedEntity = entity,
                syncedEntity.entityState != .deleted else { continue }
            
            let originObjectClass = realmObjectClass(name: syncedEntity.entityType)
            let objectIdentifier = getObjectIdentifier(for: syncedEntity)
            guard let originObject = realmProvider.targetRealm.object(ofType: originObjectClass, forPrimaryKey: objectIdentifier) else { continue }
            
            if relationship.relationshipName == RealmSwiftAdapter.shareRelationshipKey {
                syncedEntity.share = getSyncedEntity(objectIdentifier: relationship.targetIdentifier, realm: realmProvider.persistenceRealm)
                realmProvider.persistenceRealm.delete(relationship)
                continue;
            }
            
            var targetClassName: String?
            for property in originObject.objectSchema.properties {
                if property.name == relationship.relationshipName {
                    targetClassName = property.objectClassName
                    break
                }
            }
            
            guard let className = targetClassName else {
                continue
            }
            
            let targetObjectClass = realmObjectClass(name: className)
            let targetObjectIdentifier = getObjectIdentifier(stringObjectId: relationship.targetIdentifier, entityType: className)
            let targetObject = realmProvider.targetRealm.object(ofType: targetObjectClass, forPrimaryKey: targetObjectIdentifier)
            
            guard let target = targetObject else {
                continue
            }
            
            let propertyValue = originObject.value(forKey: relationship.relationshipName)
            if let rlmArray = propertyValue as? RLMArray<AnyObject> {
                rlmArray.add(target as AnyObject)
            } else {
                originObject.setValue(target, forKey: relationship.relationshipName)
            }
            
            realmProvider.persistenceRealm.delete(relationship)
        }
        
        try? realmProvider.persistenceRealm.commitWrite()
        commitTargetWriteTransactionWithoutNotifying()
        debugPrint("Finished applying pending relationships")
    }
    
    func save(record: CKRecord, for syncedEntity: SyncedEntity) {
        
        if syncedEntity.record == nil {
            syncedEntity.record = Record()
        }
        
        syncedEntity.record!.encodedRecord = encodedRecord(record, onlySystemFields: true)
    }
    
    func encodedRecord(_ record: CKRecord, onlySystemFields: Bool) -> Data {
        return Coder.shared.encode(record, onlySystemFields: onlySystemFields)
    }
    
    func getRecord(for syncedEntity: SyncedEntity) -> CKRecord? {
        return getRecord(from: syncedEntity.record)
    }

    func getRecord(from recordEntity: Record?) -> CKRecord? {
        guard let recordData = recordEntity?.encodedRecord else { return nil }
        return Coder.shared.decode(from: recordData)
    }
    
    func save(share: CKShare, forSyncedEntity entity: SyncedEntity, realmProvider: RealmProvider) {
        
        var recordEntity: Record?
        if let entityForShare = entity.share {
            recordEntity = entityForShare.record
        } else {
            let entityForShare = createSyncedEntity(for: share, realmProvider: realmProvider)
            recordEntity = Record()
            realmProvider.persistenceRealm.add(recordEntity!)
            entityForShare.record = recordEntity
            entity.share = entityForShare
        }
        
        recordEntity?.encodedRecord = encodedRecord(share, onlySystemFields: false)
    }
    
    @available(iOS 15, OSX 12, watchOS 8.0, *)
    func saveShareForRecordZone(share: CKShare, realmProvider: RealmProvider) {
        var entity = syncedEntityForRecordZoneShare(realm: realmProvider.persistenceRealm)
        var recordEntity: Record!
        if entity == nil {
            entity = createSyncedEntity(for: share, realmProvider: realmProvider)
            recordEntity = Record()
            realmProvider.persistenceRealm.add(recordEntity)
            entity?.record = recordEntity
        } else {
            recordEntity = entity?.record
        }
        
        recordEntity.encodedRecord = encodedRecord(share, onlySystemFields: false)
    }
    
    func getShare(for entity: SyncedEntity) -> CKShare? {
        guard let share = entity.share else {
            return nil
        }
        return getStoredShare(inShareEntity: share)
    }
    
    func getStoredShare(inShareEntity entity: SyncedEntity) -> CKShare? {
        if let recordData = entity.record?.encodedRecord {
            guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: recordData) else { return nil }
            unarchiver.requiresSecureCoding = false
            let share = CKShare(coder: unarchiver)
            unarchiver.finishDecoding()
            return share
        } else {
            return nil
        }
    }
    
    func createSyncedEntity(for share: CKShare, realmProvider: RealmProvider) -> SyncedEntity {
        
        let entityForShare = SyncedEntity()
        entityForShare.entityType = "CKShare"
        entityForShare.identifier = share.recordID.recordName
        entityForShare.updated = Date()
        entityForShare.state = SyncedEntityState.synced.rawValue
        realmProvider.persistenceRealm.add(entityForShare)
        
        return entityForShare
    }
    
    func nextStateToSync(after state: SyncedEntityState) -> SyncedEntityState {
        return SyncedEntityState(rawValue: state.rawValue + 1)!
    }
    
    func recordsToUpload(withState state: SyncedEntityState, limit: Int, realmProvider: RealmProvider) -> [CKRecord] {
        
        let predicate = NSPredicate(format: "state == %ld", state.rawValue)
        let results = realmProvider.persistenceRealm.objects(SyncedEntity.self).filter(predicate)
        var resultArray = [CKRecord]()
        var includedEntityIDs = Set<String>()
        for syncedEntity in results {
            
            if resultArray.count > limit {
                break
            }
            
            var entity: SyncedEntity! = syncedEntity
            while entity != nil && entity.state == state.rawValue && !includedEntityIDs.contains(entity.identifier) {
                var parentEntity: SyncedEntity? = nil
                guard let record = recordToUpload(syncedEntity: entity, realmProvider: realmProvider, parentSyncedEntity: &parentEntity) else {
                    entity = nil
                    continue
                }
                resultArray.append(record)
                includedEntityIDs.insert(entity.identifier)
                entity = parentEntity
            }
        }
        
        return resultArray
    }
    
    func recordToUpload(syncedEntity: SyncedEntity, realmProvider: RealmProvider, parentSyncedEntity: inout SyncedEntity?) -> CKRecord? {

        let record = getRecord(for: syncedEntity) ?? CKRecord(recordType: syncedEntity.entityType, recordID: CKRecord.ID(recordName: syncedEntity.identifier, zoneID: zoneID))

        let objectClass = realmObjectClass(name: syncedEntity.entityType)
        let primaryKey = objectClass.primaryKey()!
        let objectIdentifier = getObjectIdentifier(for: syncedEntity)
        let object = realmProvider.targetRealm.object(ofType: objectClass, forPrimaryKey: objectIdentifier)
        let entityState = syncedEntity.state

        guard let object = object else {
            // Object does not exist, but tracking syncedEntity thinks it does.
            // We mark it as deleted so the iCloud record will get deleted too
            try? realmProvider.persistenceRealm.write {
                syncedEntity.entityState = .deleted
            }
            return nil
        }

        let changedKeys = (syncedEntity.changedKeys ?? "").components(separatedBy: ",")

        record[CloudKitSynchronizer.entityVersionKey] = syncedEntity.version as CKRecordValue

        var parentKey: String?
        if let childObject = object as? ParentKey {
            parentKey = type(of: childObject).parentKey()
        }

        let encryptedFields = entityEncryptedFields[syncedEntity.entityType]

        var parent: Object? = nil

        for property in object.objectSchema.properties {

            if (entityState == SyncedEntityState.new.rawValue || changedKeys.contains(property.name)) {

                if let recordProcessingDelegate = recordProcessingDelegate,
                   !recordProcessingDelegate.shouldProcessPropertyBeforeUpload(propertyName: property.name, object: object, record: record) {
                    continue
                }

                if property.type == PropertyType.object && !property.isArray {
                    if let target = object.value(forKey: property.name) as? Object {

                        let targetIdentifier = self.getStringIdentifier(for: target, usingPrimaryKey: primaryKey)
                        let referenceIdentifier = "\(property.objectClassName!).\(targetIdentifier)"
                        let recordID = CKRecord.ID(recordName: referenceIdentifier, zoneID: zoneID)
                        // if we set the parent we must make the action .deleteSelf, otherwise we get errors if we ever try to delete the parent record
                        let action: CKRecord.ReferenceAction = parentKey == property.name ? .deleteSelf : .none
                        let recordReference = CKRecord.Reference(recordID: recordID, action: action)
                        record[property.name] = recordReference;
                        if parentKey == property.name {
                            parent = target
                        }
                    }
                } else if property.type != PropertyType.linkingObjects &&
                            !(property.name == objectClass.primaryKey()!) {

                    if let encrypted = encryptedFields,
                       encrypted.contains(property.name) {
                        if #available(iOS 15, OSX 12, watchOS 8.0, *) {
                            record.encryptedValues[property.name] = object.value(forKey: property.name) as? CKRecordValue
                        }
                    } else {
                        let value = object.value(forKey: property.name)

                        if property.isArray,
                           let rlmArray = value as? RLMArray<AnyObject> {
                            var array = [Any]()
                            for i in 0..<rlmArray.count {
                                let item = rlmArray.object(at: i)
                                if let target = item as? Object {
                                    let targetIdentifier = self.getStringIdentifier(for: target, usingPrimaryKey: target.objectSchema.primaryKeyProperty!.name)
                                    let referenceIdentifier = "\(target.objectSchema.className).\(targetIdentifier)"
                                    let recordID = CKRecord.ID(recordName: referenceIdentifier, zoneID: zoneID)
                                    array.append(CKRecord.Reference(recordID: recordID, action: .none))
                                } else {
                                    array.append(item)
                                }
                            }
                            record[property.name] = array as NSArray
                        } else if property.type == PropertyType.data,
                            let data = value as? Data,
                            forceDataTypeInsteadOfAsset == false  {

                            let fileURL = self.tempFileManager.store(data: data)
                            let asset = CKAsset(fileURL: fileURL)
                            record[property.name] = asset
                        } else if value == nil {
                            record[property.name] = nil
                        } else if let recordValue = value as? CKRecordValue {
                            record[property.name] = recordValue
                        }
                    }
                }
            }
        }
        
        if let parentKey = parentKey,
            entityState == SyncedEntityState.new.rawValue || changedKeys.contains(parentKey),
            let reference = record[parentKey] as? CKRecord.Reference {
            
            record.parent = CKRecord.Reference(recordID: reference.recordID, action: .none)
            if let parent = parent {
                parentSyncedEntity = self.syncedEntity(for: parent, realm: realmProvider.persistenceRealm)
            }
        }
        
        return record;
    }
    
    // MARK: - Children records
    
    func childrenRecords(for syncedEntity: SyncedEntity) -> [CKRecord] {

        var records = [CKRecord]()
        var parent: SyncedEntity?
        guard let record = recordToUpload(syncedEntity: syncedEntity, realmProvider: realmProvider, parentSyncedEntity: &parent) else {
            return []
        }
        records.append(record)
        
        if let relationships = childRelationships[syncedEntity.entityType] {
            for relationship in relationships {
                
                let objectID = getObjectIdentifier(for: syncedEntity)
                let objectClass = realmObjectClass(name: syncedEntity.entityType) as Object.Type
                if let object = realmProvider.targetRealm.object(ofType: objectClass.self, forPrimaryKey: objectID) {
                    
                    // Get children
                    let childObjectClass = realmObjectClass(name: relationship.childEntityName)
                    let predicate = NSPredicate(format: "%K == %@", relationship.childParentKey, object)
                    let children = realmProvider.targetRealm.objects(childObjectClass.self).filter(predicate)
                    
                    for child in children {
                        if let childEntity = self.syncedEntity(for: child, realm: realmProvider.persistenceRealm) {
                            records.append(contentsOf: childrenRecords(for: childEntity))
                        }
                    }
                }
            }
        }
        
        return records
    }
    
//    - (RLMResults *)childrenOf:(RLMObject *)parent withRelationship:(ChildRelationship *)relationship
//    {
//    Class objectClass = NSClassFromString(relationship.childEntityName);
//    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"%K == %@", relationship.childParentKey, parent];
//    return [objectClass objectsInRealm:parent.realm withPredicate:predicate];
//    }
    
    // MARK: - ModelAdapter
    
    public func prepareToImport() {
        
    }
    
    public func saveChanges(in records: [CKRecord]) {
        
        guard records.count != 0,
            realmProvider != nil else {
            return
        }
        
        executeOnMainQueue {
            self.realmProvider.persistenceRealm.beginWrite()
            self.realmProvider.targetRealm .beginWrite()
            
            for record in records {
                
                var syncedEntity: SyncedEntity! = getSyncedEntity(objectIdentifier: record.recordID.recordName, realm: self.realmProvider.persistenceRealm)
                if syncedEntity == nil {
                    if #available(iOS 10.0, *) {
                        if let share = record as? CKShare {
                            syncedEntity = createSyncedEntity(for: share, realmProvider: self.realmProvider)
                        } else {
                            syncedEntity = createSyncedEntity(record: record, realmProvider: self.realmProvider)
                        }
                    } else {
                        syncedEntity = createSyncedEntity(record: record, realmProvider: self.realmProvider)
                    }
                } else if syncedEntity.entityState == .deleted && syncedEntity.entityType != "CKShare" {
                    let serverDate = record.modificationDate
                    let localDate = syncedEntity.updated
                    let serverVersion = record[CloudKitSynchronizer.entityVersionKey] as? Int ?? 0
                    let localVersion = syncedEntity.version
                    
                    if (serverDate != nil && localDate != nil && serverDate! > localDate!) || serverVersion > localVersion {
                        // Resurrect
                        let objectClass = realmObjectClass(name: record.recordType)
                        let primaryKey = objectClass.primaryKey()!
                        let objectIdentifier = getObjectIdentifier(for: syncedEntity)
                        if self.realmProvider.targetRealm.object(ofType: objectClass, forPrimaryKey: objectIdentifier) == nil {
                            let object = objectClass.init()
                            object.setValue(objectIdentifier, forKey: primaryKey)
                            self.realmProvider.targetRealm.add(object)
                        }
                        syncedEntity.entityState = .synced
                    }
                }
                
                if syncedEntity.entityState != .deleted && syncedEntity.entityType != "CKShare" {
                    
                    let objectClass = realmObjectClass(name: record.recordType)
                    let objectIdentifier = getObjectIdentifier(for: syncedEntity)
                    guard let object = self.realmProvider.targetRealm.object(ofType: objectClass, forPrimaryKey: objectIdentifier) else {
                        continue
                    }
                    
                    applyChanges(in: record, to: object, syncedEntity: syncedEntity, realmProvider: self.realmProvider)
                    saveShareRelationship(for: syncedEntity, record: record)
                }
                
                save(record: record, for: syncedEntity)
                
                if syncedEntity.lastSyncedRecord == nil {
                    syncedEntity.lastSyncedRecord = Record()
                }
                syncedEntity.lastSyncedRecord?.encodedRecord = self.encodedRecord(record, onlySystemFields: false)
            }
            // Order is important here. Notifications might be delivered after targetRealm is saved and
            // it's convenient if the persistenceRealm is not in a write transaction
            try? self.realmProvider.persistenceRealm.commitWrite()
            commitTargetWriteTransactionWithoutNotifying()
        }
    }
    
    public func deleteRecords(with recordIDs: [CKRecord.ID]) {
        debugPrint("Deleting records with record ids \(recordIDs)")
        guard recordIDs.count != 0,
            realmProvider != nil else {
            return
        }
        
        executeOnMainQueue {

            self.realmProvider.persistenceRealm.beginWrite()
            self.realmProvider.targetRealm.beginWrite()
            
            for recordID in recordIDs {
                
                if let syncedEntity = getSyncedEntity(objectIdentifier: recordID.recordName, realm: self.realmProvider.persistenceRealm) {
                    
                    if syncedEntity.entityState == .changed || syncedEntity.entityState == .new {
                        
                        let objectClass = realmObjectClass(name: syncedEntity.entityType)
                        let objectIdentifier = getObjectIdentifier(for: syncedEntity)
                        if let object = self.realmProvider.targetRealm.object(ofType: objectClass, forPrimaryKey: objectIdentifier),
                           let delegate = self.delegate,
                           delegate.realmSwiftAdapter(self, shouldIgnoreServerDeletionOf: object, with: recordID) == false {
                            // Delegate said NOT to ignore, so we fall through to delete
                        } else {
                            // Local modification found and either no delegate or delegate said to ignore server deletion.
                            // Skip deletion to avoid data loss.
                            // The next sync will re-upload this record to CloudKit.
                            continue
                        }
                    }
                    
                    if syncedEntity.entityType != "CKShare" {
                        
                        let objectClass = realmObjectClass(name: syncedEntity.entityType)
                        let objectIdentifier = getObjectIdentifier(for: syncedEntity)
                        let object = self.realmProvider.targetRealm.object(ofType: objectClass, forPrimaryKey: objectIdentifier)
                        
                        if let object = object {
                            
                            let primaryKey = objectClass.primaryKey()!
                            let stringIdentifier = getStringIdentifier(for: object, usingPrimaryKey: primaryKey)
                            if let token = objectNotificationTokens[stringIdentifier] {
                                DispatchQueue.main.async { [weak self] in
                                    self?.objectNotificationTokens.removeValue(forKey: stringIdentifier)
                                    token.invalidate()
                                }
                            }
                            self.realmProvider.targetRealm.delete(object)
                        }
                    }
                    
                    if let record = syncedEntity.record {
                        self.realmProvider.persistenceRealm.delete(record);
                    }
                    
                    self.realmProvider.persistenceRealm.delete(syncedEntity)
                }
            }
            
            try? self.realmProvider.persistenceRealm.commitWrite()
            self.commitTargetWriteTransactionWithoutNotifying()
        }
    }
    
    public func persistImportedChanges(completion: @escaping ((Error?) -> Void)) {
        guard realmProvider != nil else {
            completion(nil)
            return
        }
        
        executeOnMainQueue {
            
            self.applyPendingRelationships(realmProvider: self.realmProvider)
        }
        
        completion(nil)
    }
    
    public func recordsToUpload(limit: Int) -> [CKRecord] {
        
        guard realmProvider != nil else { return [] }
        
        var recordsArray = [CKRecord]()
        
        executeOnMainQueue {
            
            let recordLimit = limit == 0 ? Int.max : limit
            var uploadingState = SyncedEntityState.new
            
            var innerLimit = recordLimit
            while recordsArray.count < recordLimit && uploadingState.rawValue < SyncedEntityState.deleted.rawValue {
                recordsArray.append(contentsOf: self.recordsToUpload(withState: uploadingState, limit: innerLimit, realmProvider: self.realmProvider))
                uploadingState = self.nextStateToSync(after: uploadingState)
                innerLimit = recordLimit - recordsArray.count
            }
        }
        
        return recordsArray
    }
    
    public func didUpload(savedRecords: [CKRecord]) {
        guard realmProvider != nil else { return }
        
        executeOnMainQueue {
            
            self.realmProvider.persistenceRealm.beginWrite()
            for record in savedRecords {
                
                if let syncedEntity = self.realmProvider.persistenceRealm.object(ofType: SyncedEntity.self, forPrimaryKey: record.recordID.recordName) {
                    
                    syncedEntity.state = SyncedEntityState.synced.rawValue
                    syncedEntity.changedKeys = nil
                    let serverVersion = record[CloudKitSynchronizer.entityVersionKey] as? Int ?? 0
                    syncedEntity.version = max(syncedEntity.version, serverVersion)
                    self.save(record: record, for: syncedEntity)
                    
                    if syncedEntity.lastSyncedRecord == nil {
                        syncedEntity.lastSyncedRecord = Record()
                    }
                    syncedEntity.lastSyncedRecord?.encodedRecord = self.encodedRecord(record, onlySystemFields: false)
                }
                
            }
            try? self.realmProvider.persistenceRealm.commitWrite()
        }
    }
    
    public func recordIDsMarkedForDeletion(limit: Int) -> [CKRecord.ID] {
        guard realmProvider != nil else { return [] }
        
        var recordIDs = [CKRecord.ID]()
        executeOnMainQueue {
            
            let predicate = NSPredicate(format: "state == %ld", SyncedEntityState.deleted.rawValue)
            let deletedEntities = self.realmProvider.persistenceRealm.objects(SyncedEntity.self).filter(predicate)
            
            for syncedEntity in deletedEntities {
                
                if recordIDs.count >= limit {
                    break
                }
                recordIDs.append(CKRecord.ID(recordName: syncedEntity.identifier, zoneID: zoneID))
            }
        }
        
        return recordIDs
    }
    
    public func didDelete(recordIDs deletedRecordIDs: [CKRecord.ID]) {
        
        guard realmProvider != nil else { return }
        
        executeOnMainQueue {
            
            self.realmProvider.persistenceRealm.beginWrite()
            for recordID in deletedRecordIDs {
                
                if let syncedEntity = self.realmProvider.persistenceRealm.object(ofType: SyncedEntity.self, forPrimaryKey: recordID.recordName) {
                    if let record = syncedEntity.record {
                        self.realmProvider.persistenceRealm.delete(record)
                    }
                    self.realmProvider.persistenceRealm.delete(syncedEntity)
                }
            }
            try? self.realmProvider.persistenceRealm.commitWrite()
        }
    }
    
    public func hasRecordID(_ recordID: CKRecord.ID) -> Bool {
        
        guard realmProvider != nil else { return false }
        
        var hasRecord = false
        executeOnMainQueue {
            let syncedEntity = self.realmProvider.persistenceRealm.object(ofType: SyncedEntity.self, forPrimaryKey: recordID.recordName)
            hasRecord = syncedEntity != nil
        }
        return hasRecord
    }
    
    public func didFinishImport(with error: Error?) {
    
        guard realmProvider != nil else { return }
        
        tempFileManager.clearTempFiles()
        
        executeOnMainQueue {
            updateHasChanges(realm: self.realmProvider.persistenceRealm)
        }
    }
    
    public func record(for object: AnyObject) -> CKRecord? {
        
        guard realmProvider != nil,
            let realmObject = object as? Object else {
            return nil
        }
        
        var record: CKRecord?
        
        executeOnMainQueue {
            if let syncedEntity = syncedEntity(for: realmObject, realm: self.realmProvider.persistenceRealm) {
                var parent: SyncedEntity?
                record = recordToUpload(syncedEntity: syncedEntity, realmProvider: self.realmProvider, parentSyncedEntity: &parent)
            }
        }
        
        return record
    }
    
    public func share(for object: AnyObject) -> CKShare? {
        
        guard realmProvider != nil,
            let realmObject = object as? Object else {
            return nil
        }
        
        var share: CKShare?
        
        executeOnMainQueue {
            if let syncedEntity = syncedEntity(for: realmObject, realm: self.realmProvider.persistenceRealm) {
                share = getShare(for: syncedEntity)
            }
        }
        
        return share
    }
    
    public func save(share: CKShare, for object: AnyObject) {
    
        guard realmProvider != nil,
            let realmObject = object as? Object else {
            return
        }
        
        executeOnMainQueue {
            if let syncedEntity = syncedEntity(for: realmObject, realm: self.realmProvider.persistenceRealm) {
                
                self.realmProvider.persistenceRealm.beginWrite()
                self.save(share: share, forSyncedEntity: syncedEntity, realmProvider: self.realmProvider)
                try? self.realmProvider.persistenceRealm.commitWrite()
            }
        }
    }
    
    public func deleteShare(for object: AnyObject) {
        
        guard realmProvider != nil,
            let realmObject = object as? Object else {
            return
        }
        
        executeOnMainQueue {
            if let syncedEntity = syncedEntity(for: realmObject, realm: self.realmProvider.persistenceRealm),
                let shareEntity = syncedEntity.share {
                
                self.realmProvider.persistenceRealm.beginWrite()
                syncedEntity.share = nil
                if let record = shareEntity.record {
                    self.realmProvider.persistenceRealm.delete(record)
                }
                self.realmProvider.persistenceRealm.delete(shareEntity)
                try? self.realmProvider.persistenceRealm.commitWrite()
            }
        }
    }
    
    public func deleteChangeTracking() {
        
        invalidateRealmAndTokens()
        
        let config = self.persistenceRealmConfiguration
        let realmFileURLs: [URL] = [config.fileURL,
                             config.fileURL?.appendingPathExtension("lock"),
                             config.fileURL?.appendingPathExtension("note"),
                             config.fileURL?.appendingPathExtension("management")
            ].compactMap { $0 }
        
        for url in realmFileURLs {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                print("Error deleting file at \(url): \(error)")
            }
        }
    }
    
    public var recordZoneID: CKRecordZone.ID {
        return zoneID
    }
    
    public var serverChangeToken: CKServerChangeToken? {
    
        guard realmProvider != nil else { return nil }
        
        var token: CKServerChangeToken?
        executeOnMainQueue {
            let serverToken = self.realmProvider.persistenceRealm.objects(ServerToken.self).first
            if let tokenData = serverToken?.token {
                token = Coder.shared.object(from: tokenData) as? CKServerChangeToken
            }
        }
        return token
    }
    
    public func saveToken(_ token: CKServerChangeToken?) {
    
        guard realmProvider != nil else { return }
        
        executeOnMainQueue {
            var serverToken: ServerToken! = self.realmProvider.persistenceRealm.objects(ServerToken.self).first
            
            self.realmProvider.persistenceRealm.beginWrite()
            
            if serverToken == nil {
                serverToken = ServerToken()
                self.realmProvider.persistenceRealm.add(serverToken)
            }
            
            if let token = token {
                serverToken.token = Coder.shared.data(from: token)
            } else {
                serverToken.token = nil
            }
            
            try? self.realmProvider.persistenceRealm.commitWrite()
        }
    }
    
    public func recordsToUpdateParentRelationshipsForRoot(_ object: AnyObject) -> [CKRecord] {
        guard realmProvider != nil,
            let realmObject = object as? Object else {
            return []
        }
        
        var records: [CKRecord]?
        executeOnMainQueue {
            if let syncedEntity = syncedEntity(for: realmObject, realm: self.realmProvider.persistenceRealm) {
                records = self.childrenRecords(for: syncedEntity)
            }
        }
        
        return records ?? []
    }
    
    @available(iOS 15.0, OSX 12, watchOS 8.0, *)
    public func shareForRecordZone() -> CKShare? {
        guard realmProvider != nil else {
            return nil
        }
        
        var share: CKShare?
        
        executeOnMainQueue {
            if let syncedEntity = syncedEntityForRecordZoneShare(realm: self.realmProvider.persistenceRealm) {
                share = getStoredShare(inShareEntity: syncedEntity)
            }
        }
        
        return share
    }
    
    /// Store CKShare for the record zone.
    /// - Parameters:
    ///   - share: `CKShare` object to save.
    @available(iOS 15.0, OSX 12, watchOS 8.0, *)
    public func saveShareForRecordZone(share: CKShare) {
        guard realmProvider != nil else {
            return
        }
        
        executeOnMainQueue {
            self.realmProvider.persistenceRealm.beginWrite()
            self.saveShareForRecordZone(share: share, realmProvider: self.realmProvider)
            try? self.realmProvider.persistenceRealm.commitWrite()
        }
    }
    
    /// Delete existing `CKShare` for adapter's record zone.
    @available(iOS 15.0, OSX 12, watchOS 8.0, *)
    public func deleteShareForRecordZone() {
        guard realmProvider != nil else {
            return
        }
        
        executeOnMainQueue {
            if let syncedEntity = syncedEntityForRecordZoneShare(realm: self.realmProvider.persistenceRealm) {
                
                self.realmProvider.persistenceRealm.beginWrite()
                if let record = syncedEntity.record {
                    self.realmProvider.persistenceRealm.delete(record)
                }
                self.realmProvider.persistenceRealm.delete(syncedEntity)
                try? self.realmProvider.persistenceRealm.commitWrite()
            }
        }
    }

}
