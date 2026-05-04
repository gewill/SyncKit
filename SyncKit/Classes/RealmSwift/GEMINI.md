# SyncKit RealmSwift Module Instructions

The RealmSwift module provides the implementation of `ModelAdapter` for Realm stores.

## Key Components

- **`RealmSwiftAdapter`**: Implements `ModelAdapter`. Manages the mapping between Realm `Object`s and `CKRecord`s.
- **`SyncedEntity`**: Internal Realm object used to track the synchronization state of user objects.
- **`DefaultRealmProvider`**: Manages the persistence and target Realms.

## Guidelines

- **Threading**: Realm objects are thread-confined. Use `executeOnMainQueue` for setup and ensure that the persistence Realm is accessed on the appropriate queue.
- **Change Tracking**: Changes are tracked using Realm's `NotificationToken`. Always ensure these tokens are invalidated in `deinit` or when the adapter is removed.
- **Primary Keys**: User objects must have a primary key to be synchronized. This is enforced through the `PrimaryKey` protocol in the example, but the adapter uses introspection.
- **Relationships**: Parent-child relationships are supported through a naming convention or custom configuration to ensure hierarchical CloudKit record structures.
- **Metadata**: Local sync metadata (tokens, record system fields) is stored in a separate "persistence Realm" to avoid polluting the user's data Realm.

## Performance

- Use `safeWrite` to avoid redundant write transactions.
- Batch changes during `saveChanges(in:)` to optimize Realm performance.
