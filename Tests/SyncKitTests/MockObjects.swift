import Foundation
import RealmSwift

class Company: Object {
    @Persisted(primaryKey: true) var name: String = ""
    @Persisted var employees: List<Employee>
    
    override static func primaryKey() -> String? {
        return "name"
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
