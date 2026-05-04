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
        .library(name: "SyncKit", targets: ["SyncKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/realm/realm-swift", from: "20.0.0")
    ],
    targets: [
        .target(
            name: "SyncKit",
            dependencies: [
                .product(name: "RealmSwift", package: "realm-swift")
            ],
            path: "SyncKit/Classes",
            exclude: [
                "Core/GEMINI.md",
                "RealmSwift/GEMINI.md"
            ]
        ),
        .testTarget(
            name: "SyncKitTests",
            dependencies: ["SyncKit"],
            path: "Tests/SyncKitTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
