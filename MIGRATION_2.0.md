# Migration Guide to SyncKit 2.0

SyncKit 2.0.0 is a major refactor that modernizes the codebase and focuses exclusively on **RealmSwift**. This guide outlines the key changes and steps required to migrate from SyncKit 0.7.x or earlier.

## 1. Scope and Platform Support

### RealmSwift Only
SyncKit no longer supports Core Data or the legacy Objective-C Realm (RLMObject). If your project still relies on these storage engines, you should remain on the 0.7.x branch.

### Modern Swift
- **Swift 5.9+**: SyncKit 2.0 uses modern Swift features.
- **Minimum Requirements**: iOS 12.0+, macOS 10.13+, tvOS 12.0+, watchOS 4.0+.

## 2. API Renaming (SK Prefix)

To align with modern Swift naming conventions, public classes and protocol methods have been updated. However, **internal storage keys and CloudKit metadata keys have been reverted to the legacy `QS` prefix to ensure 100% data continuity.**

### Metadata Keys (Compatibility Preserved)

The following keys **remain unchanged** in their literal string values. This ensures that SyncKit 2.0 can read metadata from records created by version 1.0 and avoids a "Full Sync" or the creation of new zones.

| Variable Name | String Value (Legacy) |
|---|---|
| `CloudKitSynchronizer.deviceUUIDKey` | `QSCloudKitDeviceUUIDKey` |
| `CloudKitSynchronizer.modelCompatibilityVersionKey` | `QSCloudKitModelCompatibilityVersionKey` |
| `CloudKitSynchronizer.entityVersionKey` | `QSCloudKitEntityVersionKey` |

### Internal Key Continuity

SyncKit 2.0 uses the same internal keys as 1.0 for identifying the default record zone and storing local state in `UserDefaults`.

- **Default Zone Name**: `QSCloudKitCustomZoneName`
- **Server Token Key**: `QSDatabaseServerChangeTokenKey`

**Migration Result**: Upgrading to SyncKit 2.0 is now a **seamless process**. Your app will automatically find the existing CloudKit zone and continue syncing from the last stored token without requiring a full re-download.

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
import SyncKit

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
