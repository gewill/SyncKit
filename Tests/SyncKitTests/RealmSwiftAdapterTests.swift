import XCTest
import RealmSwift
import CloudKit
@testable import SyncKit

final class RealmSwiftAdapterTests: XCTestCase {
    var adapter: RealmSwiftAdapter!
    var targetRealm: Realm!
    var persistenceRealm: Realm!
    let zoneID = CKRecordZone.ID(zoneName: "testZone", ownerName: CKCurrentUserDefaultName)
    
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
    }
    
    override func tearDown() {
        adapter = nil
        targetRealm = nil
        persistenceRealm = nil
        super.tearDown()
    }
    
    func testInitialization() {
        XCTAssertNotNil(adapter)
        XCTAssertEqual(adapter.recordZoneID, zoneID)
    }
    
    func testRecordsToUpload_withList_containsReferences() {
        try! targetRealm.write {
            let company = Company()
            company.name = "Reference Company"
            let e1 = Employee()
            e1.name = "E1"
            company.employees.append(e1)
            targetRealm.add(company)
        }
        waitForNotifications()
        
        XCTAssertTrue(adapter.hasChanges)
        
        let records = adapter.recordsToUpload(limit: 0)
        debugPrint("RealmSwiftAdapterTests >> uploaded records count: \(records.count)")
        for record in records {
            debugPrint("RealmSwiftAdapterTests >> record type: \(record.recordType), id: \(record.recordID.recordName)")
        }
        let companyRecord = records.first { $0.recordType == "Company" }
        XCTAssertNotNil(companyRecord)
        if let val = companyRecord?["employees"] {
            debugPrint("RealmSwiftAdapterTests >> employees type: \(type(of: val))")
            debugPrint("RealmSwiftAdapterTests >> employees value: \(val)")
        }
        let employees = companyRecord?["employees"] as? [CKRecord.Reference]
        XCTAssertNotNil(employees)
        XCTAssertEqual(employees?.count, 1)
        XCTAssertEqual(employees?.first?.recordID.recordName, "Employee.E1")
    }
    
    private func waitForNotifications() {
        let expectation = self.expectation(description: "Wait for notification")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1, handler: nil)
    }
}
