# SyncKit RealmSwift Module Instructions

The RealmSwift module provides the implementation of `ModelAdapter` for Realm stores.

## Key Components

- **`RealmSwiftAdapter`**: Implements `ModelAdapter`. Manages the mapping between Realm `Object`s and `CKRecord`s.
- **`SyncedEntity`**: Internal Realm object used to track the synchronization state of user objects.
- **`DefaultRealmProvider`**: Manages the persistence and target Realms.

## Conflict Resolution

- **Smart LWW**: The `.client` policy uses the `updated` timestamp in `SyncedEntity` and compares it with CloudKit's `modificationDate` to resolve conflicts deterministically.
- **Delta Counters**: Support for properties to be treated as counters using `RealmSwiftAdapterCounterProvider`. These are merged using delta addition to prevent data loss in concurrent updates.
- **Semantic List Merging**: Realm `List` properties (to-many relationships or value arrays) are merged using set semantics: `Result = (Server ∪ LocalAdditions) - LocalDeletions`. This prevents overwriting concurrent additions from different devices.

## Guidelines

- **Threading**: Realm objects are thread-confined. Use `executeOnMainQueue` for setup and ensure that the persistence Realm is accessed on the appropriate queue.
- **Change Tracking**: Use `SyncedEntity` to track the state of each Realm object. The `changedKeys` property stores a comma-separated list of modified property names.
- **Primary Keys**: User objects must have a primary key to be synchronized.
- **Realm Collection Access**: Use reflection (`_rlmArray`) to access generic Realm `List` properties in the adapter to ensure compatibility with different Realm versions.
- **Metadata**: Local sync metadata is stored in a separate "persistence Realm".

## Performance

- Use `safeWrite` to avoid redundant write transactions.
- Batch changes during `saveChanges(in:)` to optimize Realm performance.
