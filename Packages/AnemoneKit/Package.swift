// swift-tools-version: 6.2

import PackageDescription

/// Seerr (docs/seerr.md) is off unless asked for, so builds without it neither build nor link its
/// client's packages. `swift test --traits ANEMONE_SEERR` asks with the package's trait.
/// `xcodebuild` can't choose a local package's traits, and doesn't apply a default trait to the
/// package's target dependencies, so `ANEMONE_SEERR=1` in the environment asks instead: it turns
/// the trait on by default and makes the client's packages plain dependencies.
let seerrFromEnvironment = Context.environment["ANEMONE_SEERR"].map { !["", "0", "NO"].contains($0) } ?? false
let withSeerr: TargetDependencyCondition? = seerrFromEnvironment ? nil : .when(traits: ["ANEMONE_SEERR"])

let package = Package(
    name: "AnemoneKit",
    defaultLocalization: "en",
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
    traits: [
        .trait(
            name: "ANEMONE_SEERR",
            description: "Discover and request movies and shows through a Seerr server (docs/seerr.md).",
        ),
        .default(enabledTraits: seerrFromEnvironment ? ["ANEMONE_SEERR"] : []),
    ],
    dependencies: [
        // Pinned: 3.3.1 uses `any Error?` syntax that only compiles with Xcode 27, and CI runs Xcode 26.
        .package(url: "https://github.com/jellyfin/jellyfin-sdk-swift", exact: "3.3.0"),
        // The SDK's HTTP client; imported directly to match on its status-code errors.
        .package(url: "https://github.com/kean/Get", from: "2.2.1"),
        // Image loading and caching for artwork.
        .package(url: "https://github.com/kean/Nuke", from: "13.2.0"),
        // libmpv with FFmpeg, libass and MoltenVK as prebuilt xcframeworks, for the MPV engine. The
        // LGPL build, which leaves out samba. Pinned, since each release swaps all the binaries.
        .package(url: "https://github.com/mpvkit/MPVKit", exact: "1.1.0-n9.0.2"),
        // What the Seerr client that scripts/generate-seerr-client.sh generates runs on. Only
        // built and linked with the ANEMONE_SEERR trait (docs/seerr.md).
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
            resources: [.process("Localizable.xcstrings")],
        ),
        .target(
            name: "AnemonePlayback",
            dependencies: [
                "AnemoneCore",
                "AnemoneJellyfin",
                .product(name: "JellyfinAPI", package: "jellyfin-sdk-swift"),
                // Not on macOS, so `swift test` doesn't link libmpv; the engine's libmpv calls are
                // behind `#if os(tvOS) || os(iOS)`.
                .product(name: "MPVKit", package: "MPVKit", condition: .when(platforms: [.tvOS, .iOS])),
            ],
            resources: [.process("Localizable.xcstrings")],
        ),
        // Built empty, with none of the client's packages, unless ANEMONE_SEERR is on; see
        // docs/seerr.md.
        .target(
            name: "AnemoneSeerr",
            dependencies: [
                "AnemoneCore",
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime", condition: withSeerr),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession", condition: withSeerr),
                .product(name: "HTTPTypes", package: "swift-http-types", condition: withSeerr),
            ],
            resources: [.process("Localizable.xcstrings")],
        ),
        .target(
            name: "AnemoneUI",
            dependencies: [
                "AnemoneCore",
                .product(name: "Nuke", package: "Nuke"),
                .product(name: "NukeUI", package: "Nuke"),
            ],
            resources: [.process("Localizable.xcstrings")],
        ),
        .testTarget(name: "AnemoneCoreTests", dependencies: ["AnemoneCore"]),
        .testTarget(name: "AnemoneJellyfinTests", dependencies: ["AnemoneJellyfin"]),
        .testTarget(name: "AnemoneSeerrTests", dependencies: ["AnemoneSeerr", "AnemoneCore"]),
        .testTarget(name: "AnemoneUIModelTests", dependencies: ["AnemoneUI"]),
        .testTarget(
            name: "AnemonePlaybackTests",
            dependencies: [
                "AnemonePlayback",
                .product(name: "JellyfinAPI", package: "jellyfin-sdk-swift"),
            ],
        ),
    ],
)
