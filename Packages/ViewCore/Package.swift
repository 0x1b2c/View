// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ViewCore",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "ViewCore",
            targets: ["ViewCore"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.29.0"),
        .package(url: "https://github.com/LebJe/TOMLKit", from: "0.6.0")
    ],
    targets: [
        .target(
            name: "ViewCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "TOMLKit", package: "TOMLKit")
            ]
        ),
        .testTarget(
            name: "ViewCoreTests",
            dependencies: ["ViewCore"]
        )
    ]
)
