# Migration Guide to SyncKit 2.0

SyncKit 2.0.0 is a major refactor that modernizes the codebase and focuses exclusively on **RealmSwift**. This guide outlines the key changes and steps required to migrate from SyncKit 0.7.x or earlier.

## 1. Scope and Platform Support

### RealmSwift Only
SyncKit no longer supports Core Data or the legacy Objective-C Realm (RLMObject). If your project still relies on these storage engines, you should remain on the 0.7.x branch.

### Modern Swift
- **Swift 5.9+**: SyncKit 2.0 uses modern Swift features.
- **Minimum Requirements**: iOS 12.0+, macOS 10.13+, tvOS 12.0+, watchOS 4.0+.

## 2. API Renaming (SK Prefix)

To align with modern naming conventions and avoid confusion with other libraries, internal and public constants have been renamed from the legacy `QS` prefix to `SK`.

### Public Constant Mappings

| Old Name | New Name |
|---|---|
| `QSCloudKitDeviceUUIDKey` | `SKCloudKitDeviceUUIDKey` |
| `QSCloudKitModelCompatibilityVersionKey` | `SKCloudKitModelCompatibilityVersionKey` |
| `QSCloudKitEntityVersionKey` | `SKCloudKitEntityVersionKey` |
| `QSSynchronizerWillSynchronizeNotification` | `SKCloudKitSynchronizerWillSynchronizeNotification` |

### Internal Key Changes (Critical for Continuity)

SyncKit 2.0 has updated several internal keys used for storing metadata in `UserDefaults` and identifying the default CloudKit zone. **If you are migrating an existing app, you must address these to avoid losing sync state or creating a new empty zone.**

| Description | 1.0 Value (Internal) | 2.0 Value (Internal) |
|---|---|---|
| Default Zone Name | `QSCloudKitCustomZoneName` | `SKCloudKitCustomZoneName` |
| Device UUID Store Key | `QSCloudKitStoredDeviceUUIDKey` | `SKCloudKitStoredDeviceUUIDKey` |
| Subscription Store Key | `QSSubscriptionIdentifierKey` | `SKSubscriptionIdentifierKey` |
| Server Token Store Key | `QSDatabaseServerChangeTokenKey` | `SKDatabaseServerChangeTokenKey` |

#### Maintaining Data Continuity
If you want to continue using the same data in CloudKit from version 1.0, you **must** explicitly set the `zoneID` to use the old name:

```swift
let oldZoneID = CKRecordZone.ID(zoneName: "QSCloudKitCustomZoneName", ownerName: CKCurrentUserDefaultName)

let adapterProvider = DefaultRealmSwiftAdapterProvider(
    targetConfiguration: targetConfig,
    zoneID: oldZoneID
)
```

If you do not specify the zone name, SyncKit 2.0 will use `SKCloudKitCustomZoneName`, which will result in a new, empty zone being created on the server.

Additionally, because the `Server Token Store Key` has changed, the first sync after upgrading to 2.0 will perform a **Full Sync** (downloading all changes from the server). This is expected and ensures that your new `persistenceRealm` is correctly populated with all required metadata.

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
