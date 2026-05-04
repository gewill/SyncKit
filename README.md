# SyncKit

![GitHub Workflow Status (branch)](https://img.shields.io/github/workflow/status/mentrena/synckit/Test/master)
[![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://github.com/Carthage/Carthage)
[![License](https://img.shields.io/cocoapods/l/SyncKit.svg?style=flat)](http://cocoapods.org/pods/SyncKit)

SyncKit automates the process of synchronizing RealmSwift models using CloudKit.

SyncKit uses introspection to work with any model. It sits next to your Realm stack, making it easy to add synchronization to existing apps.

## Features

- [x] CloudKit synchronization for RealmSwift.
- [x] Automatic conflict resolution.
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
