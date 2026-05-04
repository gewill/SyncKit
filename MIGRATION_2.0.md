# Migration Guide to SyncKit 2.0

SyncKit 2.0.0 is a major refactor that modernizes the codebase and focuses exclusively on **RealmSwift**. This guide outlines the key changes and steps required to migrate from SyncKit 0.7.x or earlier.

## 1. Scope and Platform Support

### RealmSwift Only
SyncKit no longer supports Core Data or the legacy Objective-C Realm (RLMObject). If your project still relies on these storage engines, you should remain on the 0.7.x branch.

### Modern Swift
- **Swift 5.9+**: SyncKit 2.0 uses modern Swift features.
- **Concurrency**: Added support for `async/await` in synchronization operations.
- **Minimum Requirements**: iOS 12.0+, macOS 10.13+, tvOS 12.0+, watchOS 4.0+.

## 2. API Renaming (SK Prefix)

To align with modern naming conventions and avoid confusion with other libraries, internal and public constants have been renamed from the legacy `QS` prefix to `SK`.

| Old Name | New Name |
|---|---|
| `QSCloudKitDeviceUUIDKey` | `SKCloudKitDeviceUUIDKey` |
| `QSCloudKitModelCompatibilityVersionKey` | `SKCloudKitModelCompatibilityVersionKey` |
| `QSSynchronizerWillSynchronizeNotification` | `SKCloudKitSynchronizerWillSynchronizeNotification` |

## 3. Class and Protocol Changes

### ModelAdapter
The `ModelAdapter` protocol has been simplified. If you were using a custom adapter, you will need to update it to match the new Swift-only implementation.

### RealmSwiftAdapter
The `RealmSwiftAdapter` now manages metadata using a separate "persistence Realm" instead of storing sync state directly inside your target Realm objects. This leads to a cleaner data model.

## 4. Initialization

Initialization now requires passing a `Realm.Configuration` for both your target data and the metadata persistence.

**Before:**
```swift
let adapter = RealmSwiftAdapter(realm: myRealm, recordZoneID: zoneID)
```

**After:**
```swift
let adapterProvider = DefaultRealmSwiftAdapterProvider(
    targetRealmConfiguration: targetConfig,
    persistenceRealmConfiguration: persistenceConfig
)
```

## 5. Migration Strategy

When upgrading to 2.0.0, SyncKit will attempt to preserve your existing sync state. However, due to the metadata storage refactor, we recommend:

1. **Backup**: Always backup your Realm data before performing the migration.
2. **First Sync**: The first sync after upgrading might take longer as SyncKit re-maps the metadata into the new persistence store.
3. **Compatibility Version**: If you are making significant model changes alongside the upgrade, use the `compatibilityVersion` property to ensure older app versions do not attempt to sync incompatible data.
