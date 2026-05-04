import XCTest
import RealmSwift
import CloudKit
@testable import SyncKit

final class MockRealmSwiftAdapterDelegate: RealmSwiftAdapterDelegate {
    var onGotChanges: (([String: Any], Object) -> Void)?
    var onShouldIgnoreServerDeletion: ((Object, CKRecord.ID) -> Bool)?
    
    func realmSwiftAdapter(_ adapter: RealmSwiftAdapter, gotChanges changes: [String : Any], object: Object) {
        onGotChanges?(changes, object)
    }
    
    func realmSwiftAdapter(_ adapter: RealmSwiftAdapter, shouldIgnoreServerDeletionOf object: Object, with recordID: CKRecord.ID) -> Bool {
        return onShouldIgnoreServerDeletion?(object, recordID) ?? true
    }
}

final class RealmSwiftConflictTests: XCTestCase {
    var adapter: RealmSwiftAdapter!
    var targetRealm: Realm!
    var persistenceRealm: Realm!
    var mockDelegate: MockRealmSwiftAdapterDelegate!
    let zoneID = CKRecordZone.ID(zoneName: "testZone", ownerName: CKCurrentUserDefaultName)
    
    var strongCompany: Company?
    
    override func setUp() {
        super.setUp()
        
        let testName = self.name.replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
        var targetConfig = Realm.Configuration(inMemoryIdentifier: "target-\(testName)")
        targetConfig.objectTypes = [Company.self, Employee.self]
        targetRealm = try! Realm(configuration: targetConfig)
        
        var persistenceConfig = Realm.Configuration(inMemoryIdentifier: "persistence-\(testName)")
        persistenceConfig.objectTypes = [SyncedEntity.self, ServerToken.self, Record.self, PendingRelationship.self]
        persistenceRealm = try! Realm(configuration: persistenceConfig)
        
        adapter = RealmSwiftAdapter(persistenceRealmConfiguration: persistenceConfig,
                                    targetRealmConfiguration: targetConfig,
                                    recordZoneID: zoneID)
        mockDelegate = MockRealmSwiftAdapterDelegate()
        adapter.delegate = mockDelegate
    }
    
    override func tearDown() {
        adapter = nil
        targetRealm = nil
        persistenceRealm = nil
        strongCompany = nil
        mockDelegate = nil
        super.tearDown()
    }
    
    func testConflict_versionTracking_serverWins() {
        // 1. Create local object and sync it
        let companyName = "Test Company"
        try! targetRealm.write {
            let company = Company()
            company.name = companyName
            company.points = 10
            targetRealm.add(company)
        }
        
        waitForNotifications()
        
        // Simulate it was synced with version 1
        let record = adapter.recordsToUpload(limit: 1).first!
        record[CloudKitSynchronizer.entityVersionKey] = 1 as CKRecordValue
        adapter.didUpload(savedRecords: [record])
        
        // 2. Modify locally (version becomes 2)
        try! targetRealm.write {
            let company = targetRealm.object(ofType: Company.self, forPrimaryKey: companyName)!
            company.points = 20
        }
        waitForNotifications()
        
        // 3. Simulate server has version 3 (higher than local)
        let serverRecord = CKRecord(recordType: "Company", recordID: record.recordID)
        serverRecord["points"] = 50 as CKRecordValue
        serverRecord[CloudKitSynchronizer.entityVersionKey] = 3 as CKRecordValue
        
        adapter.saveChanges(in: [serverRecord])
        
        // 4. Verify server won
        let finalCompany = targetRealm.object(ofType: Company.self, forPrimaryKey: companyName)!
        XCTAssertEqual(finalCompany.points, 50)
    }

    func testConflict_versionTracking_clientWins() {
        // 1. Create local object and sync it
        let companyName = "Client Wins Company"
        try! targetRealm.write {
            let company = Company()
            company.name = companyName
            company.points = 10
            targetRealm.add(company)
        }
        waitForNotifications()
        
        let record = adapter.recordsToUpload(limit: 1).first!
        record[CloudKitSynchronizer.entityVersionKey] = 5 as CKRecordValue
        adapter.didUpload(savedRecords: [record])
        
        // 2. Modify locally (version remains 5 but updated date increases)
        try! targetRealm.write {
            let company = targetRealm.object(ofType: Company.self, forPrimaryKey: companyName)!
            company.points = 100
        }
        waitForNotifications()
        
        // 3. Simulate server has version 2 (lower than local)
        let serverRecord = CKRecord(recordType: "Company", recordID: record.recordID)
        serverRecord["points"] = 50 as CKRecordValue
        serverRecord[CloudKitSynchronizer.entityVersionKey] = 2 as CKRecordValue
        
        adapter.mergePolicy = .client
        adapter.saveChanges(in: [serverRecord])
        
        // 4. Verify client won
        let finalCompany = targetRealm.object(ofType: Company.self, forPrimaryKey: companyName)!
        XCTAssertEqual(finalCompany.points, 100)
    }
    
    func testConflict_resurrection_serverModifyVsLocalDelete() {
        // 1. Create local object and sync it
        let companyName = "Resurrected Company"
        try! targetRealm.write {
            let company = Company()
            company.name = companyName
            company.points = 10
            targetRealm.add(company)
        }
        waitForNotifications()
        let record = adapter.recordsToUpload(limit: 1).first!
        record[CloudKitSynchronizer.entityVersionKey] = 1 as CKRecordValue
        adapter.didUpload(savedRecords: [record])
        
        // 2. Delete locally
        try! targetRealm.write {
            let company = targetRealm.object(ofType: Company.self, forPrimaryKey: companyName)!
            targetRealm.delete(company)
        }
        waitForNotifications()
        
        // 3. Simulate server has higher version
        let serverRecord = CKRecord(recordType: "Company", recordID: record.recordID)
        serverRecord["points"] = 50 as CKRecordValue
        serverRecord[CloudKitSynchronizer.entityVersionKey] = 2 as CKRecordValue
        
        adapter.saveChanges(in: [serverRecord])
        
        // 4. Verify object is resurrected
        let finalCompany = targetRealm.object(ofType: Company.self, forPrimaryKey: companyName)
        XCTAssertNotNil(finalCompany)
        XCTAssertEqual(finalCompany?.points, 50)
    }
    
    func testConflict_ignoreServerDeletion_localModifyVsServerDelete() {
        // 1. Create local object and sync it
        let companyName = "Survivor Company"
        try! targetRealm.write {
            let company = Company()
            company.name = companyName
            company.points = 10
            targetRealm.add(company)
        }
        waitForNotifications()
        let record = adapter.recordsToUpload(limit: 1).first!
        adapter.didUpload(savedRecords: [record])
        
        // 2. Modify locally
        try! targetRealm.write {
            let company = targetRealm.object(ofType: Company.self, forPrimaryKey: companyName)!
            company.points = 20
        }
        waitForNotifications()
        
        // 3. Simulate server deletion
        // Delegate by default returns true (ignore deletion)
        adapter.deleteRecords(with: [record.recordID])
        
        // 4. Verify object still exists locally
        let finalCompany = targetRealm.object(ofType: Company.self, forPrimaryKey: companyName)
        XCTAssertNotNil(finalCompany)
        XCTAssertEqual(finalCompany?.points, 20)
    }

    func testConflict_applyServerDeletion_localModifyVsServerDelete() {
        // 1. Create local object and sync it
        let companyName = "Doomed Company"
        try! targetRealm.write {
            let company = Company()
            company.name = companyName
            company.points = 10
            targetRealm.add(company)
        }
        waitForNotifications()
        let record = adapter.recordsToUpload(limit: 1).first!
        adapter.didUpload(savedRecords: [record])
        
        // 2. Modify locally
        try! targetRealm.write {
            let company = targetRealm.object(ofType: Company.self, forPrimaryKey: companyName)!
            company.points = 20
        }
        waitForNotifications()
        
        // 3. Simulate server deletion, delegate says NOT to ignore
        mockDelegate.onShouldIgnoreServerDeletion = { _, _ in false }
        adapter.deleteRecords(with: [record.recordID])
        
        // 4. Verify object is deleted locally
        let finalCompany = targetRealm.object(ofType: Company.self, forPrimaryKey: companyName)
        XCTAssertNil(finalCompany)
    }
    
    func testConflict_deltaCounter() {
        let company = Company()
        strongCompany = company
        adapter.counterProvider = company
        
        // 1. Create local object and sync it
        let companyName = "Counter Company"
        try! targetRealm.write {
            company.name = companyName
            company.points = 10
            targetRealm.add(company)
        }
        waitForNotifications()
        
        let record = adapter.recordsToUpload(limit: 1).first!
        adapter.didUpload(savedRecords: [record])
        
        // 2. Modify locally: add 5 points (Total 15)
        try! targetRealm.write {
            let localCompany = targetRealm.object(ofType: Company.self, forPrimaryKey: companyName)!
            localCompany.points = 15
        }
        waitForNotifications()
        
        // 3. Simulate server changed from 10 to 30
        let serverRecord = CKRecord(recordType: "Company", recordID: record.recordID)
        serverRecord["points"] = 30 as CKRecordValue
        serverRecord[CloudKitSynchronizer.entityVersionKey] = 2 as CKRecordValue
        
        adapter.saveChanges(in: [serverRecord])
        
        // 4. Verify result is Server (30) + Local Delta (5) = 35
        let finalCompany = targetRealm.object(ofType: Company.self, forPrimaryKey: companyName)!
        XCTAssertEqual(finalCompany.points, 35)
    }
    
    func testConflict_customMergePolicy() {
        // 1. Create local object and sync it
        let companyName = "Custom Merge Company"
        try! targetRealm.write {
            let company = Company()
            company.name = companyName
            company.points = 10
            targetRealm.add(company)
        }
        waitForNotifications()
        let record = adapter.recordsToUpload(limit: 1).first!
        adapter.didUpload(savedRecords: [record])
        
        // 2. Modify locally
        try! targetRealm.write {
            let company = targetRealm.object(ofType: Company.self, forPrimaryKey: companyName)!
            company.points = 20
        }
        waitForNotifications()
        
        // 3. Simulate server change
        let serverRecord = CKRecord(recordType: "Company", recordID: record.recordID)
        serverRecord["points"] = 50 as CKRecordValue
        serverRecord[CloudKitSynchronizer.entityVersionKey] = 2 as CKRecordValue
        
        // Use custom merge policy
        adapter.mergePolicy = .custom
        var gotChangesCalled = false
        mockDelegate.onGotChanges = { changes, object in
            gotChangesCalled = true
            XCTAssertEqual(changes["points"] as? Int, 50)
            // Manual merge: add half of server value to local
            if let serverPoints = changes["points"] as? Int {
                let company = object as! Company
                company.points += serverPoints / 2
            }
        }
        
        adapter.saveChanges(in: [serverRecord])
        
        // 4. Verify custom merge happened: 20 + (50/2) = 45
        XCTAssertTrue(gotChangesCalled)
        let finalCompany = targetRealm.object(ofType: Company.self, forPrimaryKey: companyName)!
        XCTAssertEqual(finalCompany.points, 45)
    }
    
    func testConflict_semanticListMerging() {
        // 1. Create company with one employee and sync
        let companyName = "List Company"
        try! targetRealm.write {
            let company = Company()
            company.name = companyName
            let e1 = Employee()
            e1.name = "E1"
            company.employees.append(e1)
            targetRealm.add(company)
        }
        waitForNotifications()
        let record = adapter.recordsToUpload(limit: 1).first!
        adapter.didUpload(savedRecords: [record])
        
        // 2. Local change: add E2
        try! targetRealm.write {
            let company = targetRealm.object(ofType: Company.self, forPrimaryKey: companyName)!
            let e2 = Employee()
            e2.name = "E2"
            company.employees.append(e2)
        }
        waitForNotifications()
        
        // 3. Server change: add E3 (but it doesn't know about E2)
        let serverRecord = CKRecord(recordType: "Company", recordID: record.recordID)
        let e1Ref = CKRecord.Reference(recordID: CKRecord.ID(recordName: "Employee.E1", zoneID: zoneID), action: .none)
        let e3Ref = CKRecord.Reference(recordID: CKRecord.ID(recordName: "Employee.E3", zoneID: zoneID), action: .none)
        serverRecord["employees"] = [e1Ref, e3Ref] as CKRecordValue
        serverRecord[CloudKitSynchronizer.entityVersionKey] = 2 as CKRecordValue
        
        // We also need to have E3 in the target Realm for the relationship to be applied
        try! targetRealm.write {
            let e3 = Employee()
            e3.name = "E3"
            targetRealm.add(e3)
        }
        
        adapter.saveChanges(in: [serverRecord])
        adapter.persistImportedChanges { _ in }
        
        // 4. Verify result contains E1, E2, and E3
        let finalCompany = targetRealm.object(ofType: Company.self, forPrimaryKey: companyName)!
        let employeeNames = Set(finalCompany.employees.map { $0.name })
        XCTAssertTrue(employeeNames.contains("E1"))
        XCTAssertTrue(employeeNames.contains("E2"))
        XCTAssertTrue(employeeNames.contains("E3"))
        XCTAssertEqual(employeeNames.count, 3)
    }
    
    private func waitForNotifications() {
        let expectation = self.expectation(description: "Wait for notifications")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1, handler: nil)
    }
}
