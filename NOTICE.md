# Notice

## Wholphin

Anemone is a modified version of [Wholphin](https://github.com/damontecres/Wholphin), an Android TV client for Jellyfin.

- Copyright (C) Damontecres and Wholphin contributors
- Licensed under the GNU General Public License, version 2 or (at your option) any later version
- Anemone is distributed under version 3 of that license, as the "any later version" clause permits

Anemone is a Swift rewrite for tvOS. Behaviour, data models, and logic are ported from Wholphin; the Kotlin source is not included.

**Parity baseline:** [`damontecres/Wholphin@52c26bc`](https://github.com/damontecres/Wholphin/commit/52c26bc0fcb46c11b2023d2e475bd7b17fc7939a) (2026-10-25). Upstream changes after this commit have not been reviewed for porting, except those listed in `docs/upstream/`. The companion plugin client (`ServerPlugin.swift`) follows Wholphin's `ServerPluginApi` at `cecfdae`.

Some of Wholphin's device profile code is adapted from the official [jellyfin-androidtv](https://github.com/jellyfin/jellyfin-androidtv) client (GPL-2.0). Any of it that is ported keeps that attribution.

## Swiftfin

Anemone's AVPlayer device profile, the checks it makes on the server's media segments, the way its player overlay takes the Siri Remote's presses before the focus engine and passes on those it doesn't use, the link that opens a YouTube trailer in the YouTube app, its Now Playing info and remote commands, and closing a live TV stream that never got under way are adapted from [Swiftfin](https://github.com/jellyfin/Swiftfin), the official Jellyfin client for Apple platforms.

- Copyright (c) Jellyfin & Jellyfin Contributors
- Licensed under the Mozilla Public License, version 2.0, which allows combining it into this GPL-3.0 work

## Third-party packages

| Package | License |
|---|---|
| [jellyfin-sdk-swift](https://github.com/jellyfin/jellyfin-sdk-swift) | MPL-2.0 |
| [Get](https://github.com/kean/Get) | MIT |
| [Nuke](https://github.com/kean/Nuke) | MIT |
| [swift-nio-transport-services](https://github.com/apple/swift-nio-transport-services) (via jellyfin-sdk-swift) | Apache-2.0 |
| [swift-nio](https://github.com/apple/swift-nio), [swift-atomics](https://github.com/apple/swift-atomics), [swift-collections](https://github.com/apple/swift-collections), [swift-system](https://github.com/apple/swift-system) (via swift-nio-transport-services) | Apache-2.0 |
| [MPVKit](https://github.com/mpvkit/MPVKit) (its LGPL build; the libraries it bundles are listed below) | LGPL-3.0 |

## MPVKit and the libraries it bundles

The MPV player engine uses libmpv from [MPVKit](https://github.com/mpvkit/MPVKit) 1.1.0-n9.0.2, which ships each library below as a prebuilt, statically linked xcframework. Anemone uses MPVKit's LGPL build, which leaves out the GPL-only parts (such as Samba support). Anemone's own source is published under the GPL, so it can be rebuilt and relinked against modified versions of these libraries, as the LGPL asks.

- [mpv](https://github.com/mpv-player/mpv) 0.41 (libmpv): LGPL-2.1-or-later
- [FFmpeg](https://ffmpeg.org) n9.0.2 (libavcodec, libavformat, libavfilter, libavdevice, libavutil, libswresample, libswscale): LGPL-2.1-or-later
- [libplacebo](https://code.videolan.org/videolan/libplacebo) 7.360.1: LGPL-2.1-or-later
- [MoltenVK](https://github.com/KhronosGroup/MoltenVK) 1.4.2: Apache-2.0
- [shaderc](https://github.com/google/shaderc) 2025.5: Apache-2.0
- [libass](https://github.com/libass/libass) 0.17.5: ISC
- [FreeType](https://freetype.org): FreeType License (FTL)
- [FriBidi](https://github.com/fribidi/fribidi): LGPL-2.1-or-later
- [HarfBuzz](https://github.com/harfbuzz/harfbuzz): MIT
- [libunibreak](https://github.com/adah1972/libunibreak): zlib
- [Little CMS](https://github.com/mm2/Little-CMS) 2.17: MIT
- [libdovi](https://github.com/quietvoid/dovi_tool) 3.3.2: MIT
- [dav1d](https://code.videolan.org/videolan/dav1d) 1.5.3: BSD-2-Clause
- [uavs3d](https://github.com/uavs3/uavs3d) 1.2.1: BSD-3-Clause
- [uchardet](https://www.freedesktop.org/wiki/Software/uchardet/) 0.0.8: MPL-1.1, GPL-2.0-or-later or LGPL-2.1-or-later
- [libbluray](https://code.videolan.org/videolan/libbluray) 1.4.0: LGPL-2.1-or-later
- [OpenSSL](https://www.openssl.org) 3.3.5 (libssl, libcrypto): Apache-2.0
- [GnuTLS](https://gnutls.org) 3.8.11: LGPL-2.1-or-later
- [Nettle](https://www.lysator.liu.se/~nisse/nettle/) (nettle, hogweed) and [GMP](https://gmplib.org): LGPL-3.0-or-later or GPL-2.0-or-later

Anemone's MPV engine is set up the way MPVKit's tvOS demo player is (`MPVMetalViewController`, `MetalLayer`; LGPL-3.0), and its device profile, player choice, subtitle style, subtitle delay and subtitle download are ported from Wholphin and its `wholphin-mpv` library ([wholphin-extensions](https://github.com/damontecres/wholphin-extensions), GPL-2.0-or-later).

<!-- Update this table whenever a dependency is added, and run scripts/update-licenses.sh. Settings › About lists it. -->
