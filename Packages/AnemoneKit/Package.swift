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
        // Pinned: 3.3.1 uses `any Error?` syntax that only compiles with Xcode 27, and CI runs Xcode 26.
        .package(url: "https://github.com/jellyfin/jellyfin-sdk-swift", exact: "3.3.0"),
        // The SDK's HTTP client; imported directly to match on its status-code errors.
        .package(url: "https://github.com/kean/Get", from: "2.2.1"),
    ],
    targets: [
        .target(name: "AnemoneCore"),
        .target(
            name: "AnemoneJellyfin",
            dependencies: [
                "AnemoneCore",
                .product(name: "JellyfinAPI", package: "jellyfin-sdk-swift"),
                .product(name: "Get", package: "Get"),
            ],
        ),
        .target(name: "AnemonePlayback", dependencies: ["AnemoneCore", "AnemoneJellyfin"]),
        .target(name: "AnemoneSeerr", dependencies: ["AnemoneCore"]),
        .target(name: "AnemoneUI", dependencies: ["AnemoneCore"]),
        .testTarget(name: "AnemoneCoreTests", dependencies: ["AnemoneCore"]),
        .testTarget(name: "AnemoneJellyfinTests", dependencies: ["AnemoneJellyfin"]),
    ],
)
