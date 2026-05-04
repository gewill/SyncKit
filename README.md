# SyncKit

SyncKit automates the process of synchronizing RealmSwift models using CloudKit.

SyncKit uses introspection to work with any model. It sits next to your Realm stack, making it easy to add synchronization to existing apps.

## Features

- [x] CloudKit synchronization for RealmSwift.
- [x] Advanced conflict resolution (Version Tracking, Delta Counters, Semantic List Merging). See [Conflict Resolution Guide](CONFLICT_RESOLUTION.md).
- [x] Migration support from older versions. See [Migration Guide](MIGRATION_2.0.md).
- [x] Resilient sync with Exponential Backoff and Jitter retries.
- [x] Support for custom record zones.
- [x] Support for sharing records.

## Installation

### Swift Package Manager

Add SyncKit to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mentrena/SyncKit", from: "2.0.0")
]
```

## Quick Start

Syncing your Realm data with CloudKit takes just 3 steps:

### 1. Configure CloudKit
Ensure your app has the **iCloud** capability enabled in Xcode with **CloudKit** checked. Create a custom Zone in the CloudKit Dashboard if you don't want to use the default one.

### 2. Initialize the Synchronizer

```swift
import SyncKit

// Define your Realm configurations
let targetConfig = Realm.Configuration(...)
let persistenceConfig = Realm.Configuration(...) // Used by SyncKit for metadata

// Initialize the RealmSwift adapter provider
let adapterProvider = DefaultRealmSwiftAdapterProvider(
    targetRealmConfiguration: targetConfig,
    persistenceRealmConfiguration: persistenceConfig
)

// Create the synchronizer
let synchronizer = CloudKitSynchronizer(
    identifier: "MySynchronizer",
    containerIdentifier: "iCloud.com.mycompany.myapp",
    database: CKContainer.default().privateCloudDatabase,
    adapterProvider: adapterProvider
)
```

### 3. Start Syncing

```swift
synchronizer.synchronize { error in
    if let error = error {
        print("Sync failed: \(error)")
    } else {
        print("Sync completed successfully!")
    }
}
```

## Advanced Conflict Resolution

SyncKit provides several advanced mechanisms to handle data synchronization conflicts. For a detailed guide on how Version Tracking, Delta Counters, and Semantic Merging work, see the [Conflict Resolution Guide](CONFLICT_RESOLUTION.md).

## License

SyncKit is available under the MIT license. See the LICENSE file for more info.
