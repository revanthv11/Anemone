// swift-tools-version: 6.2

import PackageDescription

/// Only here to run swift-openapi-generator for scripts/generate-seerr-client.sh. The app doesn't
/// build it: the generated client is committed, because a build plugin needs
/// `-skipPackagePluginValidation`, which CI's `xcodebuild build` doesn't pass.
let package = Package(
    name: "SeerrClientGenerator",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-openapi-generator", exact: "1.14.2"),
    ],
)
