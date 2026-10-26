# Notice

## Wholphin

Anemone is a modified version of [Wholphin](https://github.com/damontecres/Wholphin), an Android TV client for Jellyfin.

- Copyright (C) Damontecres and Wholphin contributors
- Licensed under the GNU General Public License, version 2 or (at your option) any later version
- Anemone is distributed under version 3 of that license, as the "any later version" clause permits

Anemone is a Swift rewrite for tvOS. Behaviour, data models, and logic are ported from Wholphin; the Kotlin source is not included.

**Parity baseline:** [`damontecres/Wholphin@52c26bc`](https://github.com/damontecres/Wholphin/commit/52c26bc0fcb46c11b2023d2e475bd7b17fc7939a) (2026-10-25). Upstream changes after this commit have not been reviewed for porting.

Some of Wholphin's device profile code is adapted from the official [jellyfin-androidtv](https://github.com/jellyfin/jellyfin-androidtv) client (GPL-2.0). Any of it that is ported keeps that attribution.

## Third-party packages

| Package | License |
|---|---|
| [jellyfin-sdk-swift](https://github.com/jellyfin/jellyfin-sdk-swift) | MPL-2.0 |
| [Get](https://github.com/kean/Get) (via jellyfin-sdk-swift) | MIT |
| [swift-nio-transport-services](https://github.com/apple/swift-nio-transport-services) (via jellyfin-sdk-swift) | Apache-2.0 |
| [swift-nio](https://github.com/apple/swift-nio), [swift-atomics](https://github.com/apple/swift-atomics), [swift-collections](https://github.com/apple/swift-collections), [swift-system](https://github.com/apple/swift-system) (via swift-nio-transport-services) | Apache-2.0 |

Update this table whenever a dependency is added.
