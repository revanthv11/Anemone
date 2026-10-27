# Seerr

Anemone can discover and request movies and shows through a [Seerr](https://github.com/seerr-team/seerr) server (Overseerr or Jellyseerr, as Seerr is now), as Wholphin does. It's built only with `ANEMONE_SEERR`, so App Store builds can leave it out. Without it, nothing of Seerr is compiled, built or linked: no Discover tab, no Settings › Seerr, no Discover rows on item pages, an empty `AnemoneSeerr` module, none of the packages the Seerr client runs on, and no Seerr credits in Settings › About. Only their license texts are still bundled: the app copies `App/Settings/About/Licenses` whole, so the texts for Seerr and its three packages are in every build, as text files Settings › About doesn't show without Seerr. Leaving them out would take a build setting in the project, which turning Seerr on doesn't change.

## Turning it on

`ANEMONE_SEERR` is two switches, one for each side of the build:

- **The package's `ANEMONE_SEERR` trait.** It's off by default. It brings in swift-openapi-runtime, swift-openapi-urlsession and swift-http-types, which only `AnemoneSeerr` uses, and defines the `ANEMONE_SEERR` compilation condition in the package's targets.
- **The app's `ANEMONE_SEERR` compilation condition**, for the Discover tab, Settings › Seerr and the rows on item pages.

Each build sets both:

- **App builds (`xcodebuild`):** `ANEMONE_SEERR=1` in the environment turns the trait on, and the build setting turns the condition on:

  ```
  ANEMONE_SEERR=1 xcodebuild build -project Anemone.xcodeproj -scheme Anemone \
    -destination 'generic/platform=tvOS Simulator' \
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) ANEMONE_SEERR'
  ```

  The same works for `build-for-testing` and `archive`. `xcodebuild` can't choose a local package's traits on its command line, so `Package.swift` makes the trait a default one when it sees `ANEMONE_SEERR` set (to anything but `0` or `NO`) in its environment, which `xcodebuild` passes on to it, and makes the client's packages plain dependencies, since Xcode 27.1 didn't apply a default trait to the package's target dependencies.

  Xcode keeps the package graph it worked out in DerivedData: a build without Seerr after one with it, in the same DerivedData, failed with "Missing package product 'swift-openapi-runtime_OpenAPIRuntime…'" until that DerivedData's `Build/Intermediates.noindex/XCBuildData/PIFCache` was deleted. Give each build its own `-derivedDataPath`, or delete that folder when switching. CI's jobs each start fresh.
- **Package tests (`swift test`):**

  ```
  swift test --package-path Packages/AnemoneKit --traits ANEMONE_SEERR
  ```

  `ANEMONE_SEERR=1 swift test …` does the same.
- **In Xcode:** build from the command line, as above; the simulator can then run that build. The project's own build settings don't reach the package, and an Xcode launched without `ANEMONE_SEERR` in its environment leaves the trait off.

The condition without the trait, such as `swift test -Xswiftc -DANEMONE_SEERR` or the build setting without the environment variable, stops the build with an error that points here, since the client would be compiled without its packages. (In a DerivedData that has built Seerr before, the packages' old modules are still found, and it fails to link instead.)

The default build, the one CI's `build` job and App Store archives make, has Seerr off. The switch only decides what's built: both `Package.resolved` files pin the Seerr client's packages, so neither changes when Seerr is turned on or off, and Seerr-on builds use the same versions every time. After changing `Package.swift`, resolve with `ANEMONE_SEERR=1` so the files keep those pins, then check that resolving without it leaves them alone.

### Why a trait and an environment variable

- **The packages.** Before the trait, `AnemoneSeerr` always depended on the client's three packages, so every build compiled and linked them even with Seerr off. The trait leaves them out of the build graph; SwiftPM and Xcode don't even fetch them then.
- **The environment variable.** Xcode 26.4 and later can set a package's traits, but only in the project, for every build, and `xcodebuild` has no option for it. Turning the trait on by default from the environment wasn't enough either: Xcode 27.1 resolved the client's packages, then built `AnemoneSeerr` without them. Reading the environment in `Package.swift` and making them plain dependencies keeps the project file the same for both builds and lets CI turn Seerr on with a variable.
- **The app's condition.** A trait only reaches the package's targets, so the app needs its own condition either way.

## The client

The Seerr API client is generated with [swift-openapi-generator](https://github.com/apple/swift-openapi-generator) from `scripts/seerr-client/seerr-api.yml`, Wholphin's copy of Seerr's API description. Only the endpoints Anemone uses are generated; `scripts/seerr-client/openapi-generator-config.yaml` lists them.

The generated sources in `Packages/AnemoneKit/Sources/AnemoneSeerr/Generated` are committed, and `scripts/generate-seerr-client.sh` makes them again. A build plugin would generate them at build time, but `xcodebuild` then needs `-skipPackagePluginValidation`, which CI's build doesn't pass. To use another endpoint, add its path to the configuration, run the script, and commit the result.

## Signing in

As in Wholphin at `cecfdae`, when a profile signs in, Anemone:

1. reads the Seerr server the companion plugin ([jellyfin-plugin-wholphin](https://github.com/damontecres/jellyfin-plugin-wholphin)) sets up for everyone, from `GET /wholphin/seerrsettings`, and signs in with its API key or shared account. That login stays in memory: it's never saved, and a change in the plugin shows up the next time the profile signs in. Settings › Seerr shows such a server as "Managed by server", with Retry instead of Remove;
2. otherwise, or when that fails, signs in with the server the profile added in Settings › Seerr. Its address, how it signs in and its password or API key are kept in the Keychain, one item per profile, under a service of their own (`com.revanthv11.anemone.seerr`), apart from the sign-ins item that's shared with the Top Shelf.

Only the latest sign-in counts: a Retry while the first sign-in is still under way wins, even if the first ends later.

A password sign-in keeps Seerr's session cookie in memory. When Seerr turns a request down because that session has gone, as after the server restarts, Anemone signs in again once, with the plugin's login from memory or the password read again from the Keychain, and sends the request again. If that fails, or an API key stops working, Seerr shows as failed, and Settings › Seerr offers Retry.

## Trying it without a Seerr server

DEBUG builds launched with `-seerrMock YES` sign in to a made-up server inside the app (`App/Seerr/SeerrDebugServer.swift`), as if the plugin had set it up. `-seerrMock url` has the plugin give only its address, for the add page, `-seerrMock failing` has its sign-in turned down, for Retry, `-seerrMock lapsing` signs in with a password whose first session lapses as soon as it's used, so Anemone has to sign in again, and `-seerrMock many` adds 45 requests, so the Requests page reads three pages of them.

## CI

CI's `seerr` job builds and tests with Seerr on, so it doesn't rot while the default build leaves it out. It runs the whole package suite with `--traits ANEMONE_SEERR`, and the tvOS build with `ANEMONE_SEERR=1` and the build setting, as above. The `test` and `build` jobs keep Seerr off.
