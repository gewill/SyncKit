import XCTest
import CloudKit
@testable import SyncKit

final class CoderTests: XCTestCase {
    func testEncodeDecodeRecord() {
        let recordID = CKRecord.ID(recordName: "testRecord")
        let record = CKRecord(recordType: "TestType", recordID: recordID)
        record["testKey"] = "testValue" as CKRecordValue
        
        let data = Coder.shared.encode(record)
        let decodedRecord: CKRecord? = Coder.shared.decode(from: data)
        
        XCTAssertNotNil(decodedRecord)
        XCTAssertEqual(decodedRecord?.recordID.recordName, "testRecord")
        XCTAssertEqual(decodedRecord?["testKey"] as? String, "testValue")
    }
}
