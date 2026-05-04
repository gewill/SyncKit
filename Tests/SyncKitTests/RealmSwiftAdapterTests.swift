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
        
        var targetConfig = Realm.Configuration(inMemoryIdentifier: "target")
        targetConfig.objectTypes = [Company.self, Employee.self]
        targetRealm = try! Realm(configuration: targetConfig)
        
        var persistenceConfig = Realm.Configuration(inMemoryIdentifier: "persistence")
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
    
    func testHasChanges_whenObjectAdded_isTrue() {
        XCTAssertFalse(adapter.hasChanges)
        
        try! targetRealm.write {
            let company = Company()
            company.name = "Test Company"
            targetRealm.add(company)
        }
        
        let expectation = self.expectation(description: "Wait for notification")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1, handler: nil)
        
        XCTAssertTrue(adapter.hasChanges)
    }
}
