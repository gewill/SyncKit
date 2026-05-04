import Foundation
import RealmSwift
import SyncKit

class Company: Object {
    @Persisted(primaryKey: true) var name: String = ""
    @Persisted var employees: List<Employee>
    @Persisted var points: Int = 0
    
    override static func primaryKey() -> String? {
        return "name"
    }
}

extension Company: RealmSwiftAdapterCounterProvider {
    func isCounter(property: String, in entityType: String) -> Bool {
        return property == "points"
    }
}

class Employee: Object {
    @Persisted(primaryKey: true) var name: String = ""
    @Persisted var age: Int = 0
    @Persisted var company: Company?
    
    override static func primaryKey() -> String? {
        return "name"
    }
}
