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
        // Image loading and caching for artwork.
        .package(url: "https://github.com/kean/Nuke", from: "13.2.0"),
        // What the Seerr client that scripts/generate-seerr-client.sh generates runs on. Always
        // resolved, so Package.resolved is the same with or without ANEMONE_SEERR (docs/seerr.md).
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.13.0"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession", from: "1.4.0"),
        .package(url: "https://github.com/apple/swift-http-types", from: "1.7.0"),
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
        .target(
            name: "AnemonePlayback",
            dependencies: [
                "AnemoneCore",
                "AnemoneJellyfin",
                .product(name: "JellyfinAPI", package: "jellyfin-sdk-swift"),
            ],
        ),
        // Built empty unless ANEMONE_SEERR is set; see docs/seerr.md.
        .target(
            name: "AnemoneSeerr",
            dependencies: [
                "AnemoneCore",
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
            ],
        ),
        .target(
            name: "AnemoneUI",
            dependencies: [
                "AnemoneCore",
                .product(name: "Nuke", package: "Nuke"),
                .product(name: "NukeUI", package: "Nuke"),
            ],
        ),
        .testTarget(name: "AnemoneCoreTests", dependencies: ["AnemoneCore"]),
        .testTarget(name: "AnemoneJellyfinTests", dependencies: ["AnemoneJellyfin"]),
        .testTarget(name: "AnemoneSeerrTests", dependencies: ["AnemoneSeerr", "AnemoneCore"]),
        .testTarget(
            name: "AnemonePlaybackTests",
            dependencies: [
                "AnemonePlayback",
                .product(name: "JellyfinAPI", package: "jellyfin-sdk-swift"),
            ],
        ),
    ],
)
