# Seerr

Anemone can discover and request movies and shows through a [Seerr](https://github.com/seerr-team/seerr) server (Overseerr or Jellyseerr, as Seerr is now), as Wholphin does. It's built only when the `ANEMONE_SEERR` compilation condition is set, so App Store builds can leave it out. Without the condition, nothing of Seerr is compiled: no Discover tab, no Settings › Seerr, no Discover rows on item pages, and an empty `AnemoneSeerr` module.

## Turning it on

`ANEMONE_SEERR` is an active compilation condition. It has to reach both the app target and the package's targets, which take their build settings from different places, so it's set where each build gets its settings:

- **App builds (`xcodebuild`):** pass it as a build setting on the command line. Settings given there apply to every target in the build, the package's included:

  ```
  xcodebuild build -project Anemone.xcodeproj -scheme Anemone \
    -destination 'generic/platform=tvOS Simulator' \
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) ANEMONE_SEERR'
  ```

  The same works for `build-for-testing` and `archive`.
- **Package tests (`swift test`):**

  ```
  swift test --package-path Packages/AnemoneKit -Xswiftc -DANEMONE_SEERR
  ```

- **In Xcode:** the project's own build settings don't reach package targets, so adding the condition to the project or the app target alone breaks the build: the app then uses Seerr types the package didn't build. Build with the flag from the command line, as above; the simulator can then run that build.

The default build, the one CI and App Store archives make, has Seerr off.

The package always depends on swift-openapi-runtime, swift-openapi-urlsession and swift-http-types, whether Seerr is on or not, so `Package.resolved` is the same for both builds. With Seerr off they're built but nothing uses them.

A package trait was the other option. `swift build --traits` would cover the package, but `xcodebuild` has no way to turn on a trait of a local package, and the app would still need its own condition.

## The client

The Seerr API client is generated with [swift-openapi-generator](https://github.com/apple/swift-openapi-generator) from `scripts/seerr-client/seerr-api.yml`, Wholphin's copy of Seerr's API description. Only the endpoints Anemone uses are generated; `scripts/seerr-client/openapi-generator-config.yaml` lists them.

The generated sources in `Packages/AnemoneKit/Sources/AnemoneSeerr/Generated` are committed, and `scripts/generate-seerr-client.sh` makes them again. A build plugin would generate them at build time, but `xcodebuild` then needs `-skipPackagePluginValidation`, which CI's build doesn't pass. To use another endpoint, add its path to the configuration, run the script, and commit the result.

## Signing in

As in Wholphin at `cecfdae`, when a profile signs in, Anemone:

1. reads the Seerr server the companion plugin ([jellyfin-plugin-wholphin](https://github.com/damontecres/jellyfin-plugin-wholphin)) sets up for everyone, from `GET /wholphin/seerrsettings`, and signs in with its API key or shared account. That login stays in memory: it's never saved, and a change in the plugin shows up the next time the profile signs in. Settings › Seerr shows such a server as "Managed by server", with Retry instead of Remove;
2. otherwise, or when that fails, signs in with the server the profile added in Settings › Seerr. Its address, how it signs in and its password or API key are kept in the Keychain, one item per profile.

## Trying it without a Seerr server

DEBUG builds launched with `-seerrMock YES` sign in to a made-up server inside the app (`App/Seerr/SeerrDebugServer.swift`), as if the plugin had set it up. `-seerrMock url` has the plugin give only its address, for the add page, and `-seerrMock failing` has its sign-in turned down, for Retry.

## CI

A second job builds and tests with Seerr on, so it doesn't rot while the default build leaves it out:

```yaml
  seerr:
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v7
      - name: Select Xcode
        run: sudo xcode-select -s "$XCODE_PATH"
      - name: Package tests with Seerr
        run: swift test --package-path Packages/AnemoneKit -Xswiftc -DANEMONE_SEERR
      - name: Build tvOS app with Seerr
        run: >
          xcodebuild build
          -project Anemone.xcodeproj
          -scheme Anemone
          -destination 'generic/platform=tvOS Simulator'
          CODE_SIGNING_ALLOWED=NO
          'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) ANEMONE_SEERR'
```
