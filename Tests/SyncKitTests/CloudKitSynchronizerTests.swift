import XCTest
import CloudKit
@testable import SyncKit

final class CloudKitSynchronizerTests: XCTestCase {
    var synchronizer: CloudKitSynchronizer!
    var mockDatabase: MockCloudKitDatabase!
    var mockAdapterProvider: MockAdapterProvider!
    var mockAdapter: MockModelAdapter!
    let zoneID = CKRecordZone.ID(zoneName: "testZone", ownerName: CKCurrentUserDefaultName)
    
    override func setUp() {
        super.setUp()
        mockDatabase = MockCloudKitDatabase()
        mockAdapterProvider = MockAdapterProvider()
        mockAdapter = MockModelAdapter(recordZoneID: zoneID)
        mockAdapterProvider.mockAdapter = mockAdapter
        
        synchronizer = CloudKitSynchronizer(identifier: "testSynchronizer",
                                           containerIdentifier: "testContainer",
                                           database: mockDatabase,
                                           adapterProvider: mockAdapterProvider)
    }
    
    override func tearDown() {
        synchronizer = nil
        mockDatabase = nil
        mockAdapterProvider = nil
        mockAdapter = nil
        super.tearDown()
    }
    
    func testInitialization() {
        XCTAssertNotNil(synchronizer)
        XCTAssertEqual(synchronizer.identifier, "testSynchronizer")
    }
    
    func testSynchronize_callsCompletion() {
        let expectation = self.expectation(description: "Sync completion called")
        
        synchronizer.synchronize { error in
            XCTAssertNil(error)
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 5, handler: nil)
    }
}
