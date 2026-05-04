import Foundation
import CloudKit
import SyncKit

class MockModelAdapter: NSObject, ModelAdapter {
    var hasChanges: Bool = false
    var recordZoneID: CKRecordZone.ID
    var serverChangeToken: CKServerChangeToken?
    var mergePolicy: MergePolicy = .server
    
    var prepareToImportCalled = false
    var saveChangesCalled = false
    var deleteRecordsCalled = false
    var persistImportedChangesCalled = false
    var recordsToUploadCalled = false
    var didUploadCalled = false
    var recordIDsMarkedForDeletionCalled = false
    var didDeleteCalled = false
    var didFinishImportCalled = false
    
    init(recordZoneID: CKRecordZone.ID) {
        self.recordZoneID = recordZoneID
    }
    
    func prepareToImport() { prepareToImportCalled = true }
    func saveChanges(in records: [CKRecord]) { saveChangesCalled = true }
    func deleteRecords(with recordIDs: [CKRecord.ID]) { deleteRecordsCalled = true }
    func persistImportedChanges(completion: @escaping (Error?) -> ()) {
        persistImportedChangesCalled = true
        completion(nil)
    }
    func recordsToUpload(limit: Int) -> [CKRecord] {
        recordsToUploadCalled = true
        return []
    }
    func didUpload(savedRecords: [CKRecord]) { didUploadCalled = true }
    func recordIDsMarkedForDeletion(limit: Int) -> [CKRecord.ID] {
        recordIDsMarkedForDeletionCalled = true
        return []
    }
    func didDelete(recordIDs: [CKRecord.ID]) { didDeleteCalled = true }
    func hasRecordID(_ recordID: CKRecord.ID) -> Bool { return false }
    func didFinishImport(with error: Error?) { didFinishImportCalled = true }
    func saveToken(_ token: CKServerChangeToken?) { serverChangeToken = token }
    func deleteChangeTracking() {}
    func record(for object: AnyObject) -> CKRecord? { return nil }
    func share(for object: AnyObject) -> CKShare? { return nil }
    func save(share: CKShare, for object: AnyObject) {}
    func deleteShare(for object: AnyObject) {}
    func shareForRecordZone() -> CKShare? { return nil }
    func saveShareForRecordZone(share: CKShare) {}
    func deleteShareForRecordZone() {}
    func recordsToUpdateParentRelationshipsForRoot(_ object: AnyObject) -> [CKRecord] { return [] }
}

class MockAdapterProvider: NSObject, AdapterProvider {
    var mockAdapter: MockModelAdapter?
    
    func cloudKitSynchronizer(_ synchronizer: CloudKitSynchronizer, modelAdapterForRecordZoneID zoneID: CKRecordZone.ID) -> ModelAdapter? {
        return mockAdapter
    }
    
    func cloudKitSynchronizer(_ synchronizer: CloudKitSynchronizer, zoneWasDeletedWithZoneID zoneID: CKRecordZone.ID) {}
}
