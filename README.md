# Anemone

An open-source Apple TV client for [Jellyfin](https://jellyfin.org), written in Swift.

Anemone is a tvOS port of [Wholphin](https://github.com/damontecres/Wholphin), the Android TV client by damontecres. It aims to bring Wholphin's Plex-inspired interface, home page customization, and playback controls to Apple TV.

> [!WARNING]
> Anemone is in early development and is not usable yet. See the [plan](docs/PLAN.md) for what's coming.

## Requirements

- Apple TV running tvOS 26 or later
- Jellyfin server 12.0 or later

## Building

You need Xcode 26 or later with the tvOS SDK.

1. Open `Anemone.xcodeproj`.
2. Select the `Anemone` scheme and an Apple TV simulator or device.
3. Build and run.

From the command line:

```bash
xcodebuild -project Anemone.xcodeproj -scheme Anemone -destination 'generic/platform=tvOS Simulator' build
```

The shared code lives in a local Swift package. Its tests run on macOS:

```bash
swift test --package-path Packages/AnemoneKit
```

## Project layout

| Path | What it is |
|---|---|
| `App/` | The tvOS app target |
| `TopShelf/` | Top Shelf extension (Continue Watching / Next Up on the Apple TV home screen) |
| `Packages/AnemoneKit/` | Shared code, split into `AnemoneCore`, `AnemoneJellyfin`, `AnemonePlayback`, `AnemoneSeerr` and `AnemoneUI` |
| `docs/PLAN.md` | The port plan and roadmap |

## License

Anemone is licensed under the [GNU General Public License v3.0](LICENSE).

It is a modified version of Wholphin, which is licensed under GPL-2.0-or-later. See [NOTICE.md](NOTICE.md) for attribution and third-party licenses.

Anemone is not affiliated with or endorsed by the Wholphin or Jellyfin projects.
