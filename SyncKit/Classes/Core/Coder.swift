//
//  Coder.swift
//  SyncKit
//
//  Created by Manuel Entrena on 09/06/2019.
//

import Foundation
import CloudKit

class Coder {
    
    static let shared = Coder()
    
    func data(from object: Any) -> Data? {
        return try? NSKeyedArchiver.archivedData(withRootObject: object, requiringSecureCoding: false)
    }
    
    func object(from data: Data) -> Any? {
        return try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data)
    }
    
    func encode<T: CKRecord>(_ record: T, onlySystemFields: Bool = false) -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        if onlySystemFields {
            record.encodeSystemFields(with: archiver)
        } else {
            record.encode(with: archiver)
        }
        archiver.finishEncoding()
        return archiver.encodedData
    }
    
    func decode<T: CKRecord>(from data: Data) -> T? {
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        unarchiver.requiresSecureCoding = false
        let record = T(coder: unarchiver)
        unarchiver.finishDecoding()
        return record
    }
}
