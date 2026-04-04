// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SyncKit",
    platforms: [
        .macOS(.v10_13),
        .iOS(.v12),
        .tvOS(.v12),
        .watchOS(.v4)
    ],
    products: [
        .library(name: "SyncKitCoreData", targets: ["SyncKit/CoreData"]),
        .library(name: "SyncKitRealm", targets: ["SyncKit/Realm"]),
        .library(name: "SyncKit_RealmSwift", targets: ["SyncKit/RealmSwift"])
    ],
    dependencies: [
        .package(url: "https://github.com/realm/realm-swift", from: "20.0.0")
    ],
    targets: [
        .target(
            name: "SyncKit/CoreData",
            dependencies: [],
            path: "SyncKit/Classes/CoreData",
            resources: [
                .process("QSCloudKitSyncModel.xcdatamodeld")
            ],
            swiftSettings: [
                .define("SPM")
            ]
        ),
         .target(
            name: "SyncKit/Realm",
            dependencies: [
                .product(name: "Realm", package: "realm-swift")
            ],
            path: "SyncKit/Classes/Realm"
        ),
        .target(
            name: "SyncKit/RealmSwift",
            dependencies: [
                .product(name: "RealmSwift", package: "realm-swift")
            ],
            path: "SyncKit/Classes/RealmSwift"
        )
    ],
    swiftLanguageVersions: [.v5]
)
