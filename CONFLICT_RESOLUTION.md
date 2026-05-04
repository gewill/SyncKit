# Advanced Conflict Resolution in SyncKit

SyncKit 2.0.0 introduces sophisticated conflict resolution mechanisms to ensure data integrity across multiple devices. This document provides practical, copy-paste friendly examples for the three pillars of our conflict resolution strategy: **Version Tracking**, **Delta Counters**, and **Semantic List Merging**, as well as custom merge policies.

## 1. Version Tracking (Smart LWW)

SyncKit uses a monotonic version counter to distinguish between **concurrent modifications** and **base-revision updates**.

### How it works:
- Every `SyncedEntity` maintains a `version` integer.
- **Local Changes**: Whenever an object is modified locally, its `version` increments by 1.
- **Merge Logic**:
    - **Server Version > Local Version**: The client recognizes it is working on an outdated revision. Server values will override local changes for conflicted fields (Base-revision update).
    - **Server Version == Local Version**: A potential concurrent conflict. SyncKit falls back to timestamp-based resolution (comparing the local `updated` date with the server's `modificationDate`).

## 2. Delta Counters

Standard Last-Write-Wins (LWW) is often destructive for numeric values like scores or view counts. SyncKit supports **Delta Merging** for these properties.

### Implementation:
Implement the `RealmSwiftAdapterCounterProvider` in your model or a separate provider object:

```swift
class MyObject: Object {
    @Persisted(primaryKey: true) var id: String = ""
    @Persisted var points: Int = 0
}

// 1. Conform your object or a delegate to the provider protocol
extension MyObject: RealmSwiftAdapterCounterProvider {
    func isCounter(property: String, in entityType: String) -> Bool {
        return entityType == "MyObject" && property == "points"
    }
}

// 2. Assign the provider to your adapter
let adapter = adapterProvider.adapter(for: zoneID) as! RealmSwiftAdapter
adapter.counterProvider = someObject // or your model instance
```

### How it works:
Instead of overwriting the value, SyncKit calculates the local delta since the last sync. When a conflict occurs:
`New Value = Server Value + Local Delta`

## 3. Semantic List Merging

For Realm `List` properties (to-many relationships or primitive arrays), SyncKit treats the collection as a set to prevent data loss during concurrent updates.

### Implementation:
No extra code is needed! Any Realm `List` property is automatically handled with semantic merging.

```swift
class Company: Object {
    @Persisted(primaryKey: true) var name: String = ""
    @Persisted var employees: List<Employee>
}

// If Device A adds "Alice" and Device B adds "Bob" concurrently:
// Result: employees = ["Alice", "Bob"] (both preserved)
```

### Logic:
`Resulting List = (Server List ∪ Local Additions) - Local Deletions`

---

## 4. Custom Merge Policies

If the default Smart LWW logic isn't sufficient, you can implement a custom merge policy.

### Implementation:

```swift
class MySyncDelegate: RealmSwiftAdapterDelegate {
    func realmSwiftAdapter(_ adapter: RealmSwiftAdapter, gotChanges changes: [String: Any], object: Object) {
        guard let myObject = object as? MyObject else { return }
        
        // Manual merging logic
        if let serverPoints = changes["points"] as? Int {
            // e.g., only update if server points are significantly higher
            if serverPoints > myObject.points + 100 {
                myObject.points = serverPoints
            }
        }
    }
    
    // Handle Delete-Modify Conflicts
    func realmSwiftAdapter(_ adapter: RealmSwiftAdapter, shouldIgnoreServerDeletionOf object: Object, with recordID: CKRecord.ID) -> Bool {
        // Return true (Default) to ignore server deletion and re-upload the local modified version
        // Return false to accept the server deletion and delete the local modified object
        return true 
    }
}

// Configure the adapter
let adapter = adapterProvider.adapter(for: zoneID) as! RealmSwiftAdapter
adapter.mergePolicy = .custom
adapter.delegate = mySyncDelegate
```

## 5. Tombstone Optimization (Delete-Modify Conflicts)

SyncKit 2.0.0 improves handling of cases where one user deletes an object while another modifies it.

### Resurrection (Server Modify vs Local Delete)
If an object is marked for deletion locally but a newer modification arrives from the server (based on version or date), SyncKit will **resurrect** the object automatically.

### Local Modify vs Server Delete
If a deletion instruction arrives from the server for an object that has pending local changes, SyncKit uses the delegate method shown above:
- **Return `true`**: Object "survives" the deletion and will be re-uploaded.
- **Return `false`**: Object is deleted locally, and local changes are discarded.

These mechanisms work together to ensure that SyncKit prioritizes data preservation while allowing application-level control.
