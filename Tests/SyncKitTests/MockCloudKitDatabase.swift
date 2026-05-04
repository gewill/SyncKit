import Foundation
import CloudKit
import SyncKit

class MockCloudKitDatabase: NSObject, CloudKitDatabaseAdapter {
    var addedOperations = [CKDatabaseOperation]()
    var savedZones = [CKRecordZone]()
    var deletedZoneIDs = [CKRecordZone.ID]()
    var fetchedZoneIDs = [CKRecordZone.ID]()
    var fetchedRecordIDs = [CKRecord.ID]()
    
    var databaseScope: CKDatabase.Scope = .private
    
    func add(_ operation: CKDatabaseOperation) {
        addedOperations.append(operation)
        
        if let fetchDatabaseChanges = operation as? CKFetchDatabaseChangesOperation {
            fetchDatabaseChanges.fetchDatabaseChangesCompletionBlock?(nil, false, nil)
        } else if let fetchZoneChanges = operation as? CKFetchRecordZoneChangesOperation {
            fetchZoneChanges.fetchRecordZoneChangesCompletionBlock?(nil)
        } else if let modifyRecords = operation as? CKModifyRecordsOperation {
            modifyRecords.modifyRecordsCompletionBlock?(nil, nil, nil)
        }
    }
    
    func save(zone: CKRecordZone, completionHandler: @escaping (CKRecordZone?, Error?) -> Void) {
        savedZones.append(zone)
        completionHandler(zone, nil)
    }
    
    func fetch(withRecordZoneID zoneID: CKRecordZone.ID, completionHandler: @escaping (CKRecordZone?, Error?) -> Void) {
        fetchedZoneIDs.append(zoneID)
        completionHandler(nil, nil)
    }
    
    func fetch(withRecordID recordID: CKRecord.ID, completionHandler: @escaping (CKRecord?, Error?) -> Void) {
        fetchedRecordIDs.append(recordID)
        completionHandler(nil, nil)
    }
    
    func delete(withRecordZoneID zoneID: CKRecordZone.ID, completionHandler: @escaping (CKRecordZone.ID?, Error?) -> Void) {
        deletedZoneIDs.append(zoneID)
        completionHandler(zoneID, nil)
    }
    
    func fetchAllSubscriptions(completionHandler: @escaping ([CKSubscription]?, Error?) -> Void) {
        completionHandler([], nil)
    }
    
    func save(subscription: CKSubscription, completionHandler: @escaping (CKSubscription?, Error?) -> Void) {
        completionHandler(subscription, nil)
    }
    
    func delete(withSubscriptionID subscriptionID: CKSubscription.ID, completionHandler: @escaping (String?, Error?) -> Void) {
        completionHandler(subscriptionID, nil)
    }
}
