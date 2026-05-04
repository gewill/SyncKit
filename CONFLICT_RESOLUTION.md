# Advanced Conflict Resolution in SyncKit

SyncKit 2.1.0 introduces sophisticated conflict resolution mechanisms to ensure data integrity across multiple devices. This document explains the three pillars of our conflict resolution strategy: **Vector Clocks**, **Delta Counters**, and **Semantic List Merging**.

## 1. Vector Clocks (Version Tracking)

SyncKit uses a simplified vector clock system (version tracking) to distinguish between **concurrent modifications** and **base-revision updates**.

### How it works:
- Every `SyncedEntity` maintains a `version` integer.
- **Local Changes**: Whenever an object is modified locally, its `version` increments by 1.
- **CloudKit Sync**: This version is stored in the CloudKit record under the key `SKCloudKitEntityVersionKey`.
- **Merge Logic**:
    - **Server Version > Local Version**: The client recognizes it is working on an outdated revision. Server values will override local changes for conflicted fields (Last-Write-Wins based on history).
    - **Server Version == Local Version**: A true concurrent conflict. SyncKit falls back to timestamp-based resolution (comparing the local `updated` date with the server's `modificationDate`).

## 2. Delta Counters

Standard Last-Write-Wins (LWW) is often destructive for numeric values like scores, balances, or view counts. SyncKit supports **Delta Merging** for these properties.

### Integration:
Implement the `RealmSwiftAdapterCounterProvider` in your model:

```swift
extension MyObject: RealmSwiftAdapterCounterProvider {
    static func counterProperties() -> [String] {
        return ["points", "tapCount"]
    }
}
```

### How it works:
Instead of overwriting the value, SyncKit calculates the local delta since the last sync. When a conflict occurs on a counter property, SyncKit performs:
`New Value = Server Value + Local Delta`

This ensures that no "taps" or "points" are lost, even if multiple devices update the counter simultaneously.

## 3. Semantic List Merging

For Realm `List` properties (to-many relationships or primitive arrays), SyncKit treats the collection as a set to prevent data loss.

### Logic:
`Resulting List = (Server List ∪ Local Additions) - Local Deletions`

### Why this matters:
If Device A adds "Item 1" to a list and Device B adds "Item 2" simultaneously, a standard LWW approach would result in only one of the items existing. With SyncKit's semantic merging, **both** items will be preserved in the final list.

---

## Choosing a Merge Policy

You can configure the behavior of the `CloudKitSynchronizer` via the `ModelAdapter`:

- `.server`: Server always wins. Local changes are discarded if a conflict occurs.
- `.client` (Default): Uses the Smart LWW logic (Vector Clocks + Timestamps) described above.
- `.custom`: Allows you to provide a delegate to handle conflicts manually on a per-field basis.

## 4. Tombstone Optimization (Delete-Modify Conflicts)

SyncKit 2.1.0 improves handling of conflicts where one user deletes an object while another modifies it.

### Resurrection (Server Modify vs Local Delete)
If an object is marked for deletion locally (`.deleted` state) but a newer modification arrives from the server (based on `modificationDate` or `version`), SyncKit will **resurrect** the object. It recreates the object in the target Realm and applies the server changes, ensuring that a "late" modification from another user is not lost just because one user chose to delete their local copy.

### Local Modify Protection (Server Delete vs Local Modify)
If a deletion instruction arrives from the server for an object that has pending local changes (`.changed` or `.new` state), SyncKit will **ignore the deletion**. This prevents local data loss. The object will persist locally and be re-uploaded to CloudKit in the next sync cycle, effectively "winning" over the deletion.

These mechanisms work together to ensure that SyncKit prioritizes data preservation in collaborative environments.
