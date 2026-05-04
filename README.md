# SyncKit

[![License](https://img.shields.io/cocoapods/l/SyncKit.svg?style=flat)](http://cocoapods.org/pods/SyncKit)

SyncKit automates the process of synchronizing RealmSwift models using CloudKit.

SyncKit uses introspection to work with any model. It sits next to your Realm stack, making it easy to add synchronization to existing apps.

## Features

- [x] CloudKit synchronization for RealmSwift.
- [x] Advanced conflict resolution (Vector Clocks, Delta Counters, Semantic List Merging). See [Conflict Resolution Guide](CONFLICT_RESOLUTION.md).
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

## License

SyncKit is available under the MIT license. See the LICENSE file for more info.
