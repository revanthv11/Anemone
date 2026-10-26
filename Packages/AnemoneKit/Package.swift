// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AnemoneKit",
    platforms: [
        .tvOS(.v26),
        .iOS(.v26),
        // macOS is only here so `swift test` can run on a Mac; there is no macOS app.
        .macOS(.v26),
    ],
    products: [
        .library(name: "AnemoneCore", targets: ["AnemoneCore"]),
        .library(name: "AnemoneJellyfin", targets: ["AnemoneJellyfin"]),
        .library(name: "AnemonePlayback", targets: ["AnemonePlayback"]),
        .library(name: "AnemoneSeerr", targets: ["AnemoneSeerr"]),
        .library(name: "AnemoneUI", targets: ["AnemoneUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jellyfin/jellyfin-sdk-swift", from: "3.3.0"),
    ],
    targets: [
        .target(name: "AnemoneCore"),
        .target(
            name: "AnemoneJellyfin",
            dependencies: [
                "AnemoneCore",
                .product(name: "JellyfinAPI", package: "jellyfin-sdk-swift"),
            ],
        ),
        .target(name: "AnemonePlayback", dependencies: ["AnemoneCore", "AnemoneJellyfin"]),
        .target(name: "AnemoneSeerr", dependencies: ["AnemoneCore"]),
        .target(name: "AnemoneUI", dependencies: ["AnemoneCore"]),
        .testTarget(name: "AnemoneCoreTests", dependencies: ["AnemoneCore"]),
        .testTarget(name: "AnemoneJellyfinTests", dependencies: ["AnemoneJellyfin"]),
    ],
)
