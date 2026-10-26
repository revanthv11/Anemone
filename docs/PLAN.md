# Anemone port plan

Anemone is a Swift/tvOS port of [Wholphin](https://github.com/damontecres/Wholphin) (Android TV, Kotlin + Compose, ~92k lines). The parity baseline is Wholphin commit `52c26bc` (2026-10-25).

## Decisions

| Topic | Decision |
|---|---|
| License | GPL-3.0. Wholphin is GPL-2.0-or-later, so its logic can be ported directly. Distributed through the App Store without a separate grant from the Wholphin author; see "GPL and the App Store" below. |
| Repo | This repo, a fresh history. Wholphin is a reference, not a git remote. |
| Distribution | App Store is the goal; TestFlight along the way. |
| Platforms | tvOS 26+ now (runs on every Apple TV, including HD and 4K 1st gen). iOS/iPadOS later (Phase 7). |
| Server | Jellyfin 12.0+ only. Jellyfin 12 removed `GET /QuickConnect/Initiate`, legacy route prefixes, and legacy auth by default. Wholphin is already warning users on older servers. |
| Bundle ID | `com.revanthv11.anemone`, shared later by the iOS app for universal purchase. Confirm before registering in App Store Connect. |

### GPL and the App Store

The FSF considers Apple's App Store terms incompatible with the GPL; in practice it only matters if a copyright holder complains (VLC 2011, GNU Go 2010). To lower the risk:

- Use a custom EULA in App Store Connect that points to the GPL, not Apple's standard EULA.
- Tag the source for every TestFlight and App Store build, so each shipped build has public matching source.
- Keep an in-app licenses screen that credits Wholphin.

## Stack mapping

| Wholphin (Android) | Anemone (tvOS) |
|---|---|
| Compose for TV | SwiftUI; UIKit where focus or performance needs it |
| Navigation 3 back stack of `Destination` | `NavigationStack(path:)` over a Hashable `Destination` enum; `TabView` with `.sidebarAdaptable` replaces the nav drawer |
| Hilt | Composition root plus `@Observable` services in the SwiftUI Environment |
| jellyfin-sdk-kotlin | [jellyfin-sdk-swift](https://github.com/jellyfin/jellyfin-sdk-swift) (`JellyfinClient`, `JellyfinSocket`, Quick Connect) |
| ExoPlayer | AVPlayer / AVKit |
| libmpv AAR | [MPVKit](https://github.com/mpvkit/MPVKit) (LGPL-3.0) |
| Room + Proto DataStore | Keychain + UserDefaults + server-side prefs (see storage below) |
| Coil | Nuke |
| Android Palette (backdrop colours) | Core Image colour extraction |
| WorkManager, TV provider channels | `BGTaskScheduler`, Top Shelf extension |
| MediaSession | `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` |
| `RefreshRateService` | `AVDisplayManager.preferredDisplayCriteria` |
| Seerr client from openapi-generator | swift-openapi-generator against the same `seerr-api.yml` |
| `strings.xml` (668 strings, 40 locales) | String Catalog, converted by script |

[Swiftfin](https://github.com/jellyfin/Swiftfin) (MPL-2.0, tvOS 26+, MPV + AVPlayer) is the closest reference. MPL-2.0 code can be combined into this GPL app.

## tvOS constraints that shape the design

- **Storage can be purged.** Only a small amount of UserDefaults is guaranteed to persist; everything else can be purged when space runs low.
  - Servers and tokens go in the Keychain.
  - A local database is a cache only.
  - Anything that matters syncs to the server through DisplayPreferences `customPrefs`, as Wholphin already does for `home_settings` and `removeNextUp`.
- **Server discovery.** Jellyfin discovery is a UDP broadcast on port 7359. That needs Apple's multicast entitlement, which requires approval, and tvOS support is unclear. Manual URL and Quick Connect come first.
- **Siri Remote.** There are no key-repeat counts. Wholphin's left/right seek with hold acceleration needs press-began/ended timers, plus clickpad swipe scrubbing.
- **SwiftUI focus.** Focus restoration and performance in nested lazy rows is the biggest UI risk; it's the first spike.
- **Players.**
  - AVPlayer gives Dolby Vision (MP4 / fMP4 HLS only), Atmos via EAC3-JOC, AirPlay and frame-rate matching. It can't play MKV, DTS, TrueHD, ASS or PGS.
  - MPV direct-plays almost anything, with libass for ASS. It can't output Dolby Vision; frame-rate matching must be set manually.
  - Neither can bitstream TrueHD or DTS.
  - Mirrors Wholphin's `PREFER_MPV` rule, which sends HDR to the native player.
- **Device profile.** There's no `MediaCodecList`. Use one static profile per engine plus runtime checks (`VTIsHardwareDecodeSupported`, AVPlayer HDR eligibility).
- **No system screensaver API.** The screensaver is in-app only.
- **Per-user UI language** isn't practical on tvOS (the app language is a system setting). Dropped.

## Architecture

- **`App/`:** the tvOS app target. Composition root, navigation, and tvOS screens.
- **`TopShelf/`:** the Top Shelf extension. Will share credentials with the app through an App Group and a Keychain access group.
- **`Packages/AnemoneKit`:** one local package, five libraries:
  - **AnemoneCore:** models, `Destination`, `HomeRowConfig` Codable types, stream-choice scoring, device profiles, settings. Pure Swift; tests run on macOS.
  - **AnemoneJellyfin:** session, repositories, WebSocket, playback progress reporting.
  - **AnemonePlayback:** a `PlayerEngine` protocol with AVPlayer and MPV engines, the playback state machine, segment / next-up / pass-out logic, trickplay. One custom SwiftUI overlay shared by both engines (MPV can't use `AVPlayerViewController`).
  - **AnemoneSeerr:** the generated Seerr client, behind a build flag.
  - **AnemoneUI:** design tokens, cards, rows, grids, backdrop, context menu.
- The packages stay platform-neutral; tvOS-only code goes behind `#if os(tvOS)`. Screens are per platform, because tvOS is built around focus and iOS around touch.

### Compatibility with Wholphin

- Use the same home-row JSON schema (v1).
- Support [jellyfin-plugin-wholphin](https://github.com/damontecres/jellyfin-plugin-wholphin) (`GET /wholphin/public`, `GET /wholphin/homesettings`), so admins configure home layouts once for both apps.
- Offer "Import from Wholphin" by reading its DisplayPreferences entry (id `default`, client `Wholphin`, key `home_settings`). Anemone writes its own entry under client `Anemone`.

## Phases

### Phase 0: setup and spikes

- [x] Repo, GPL-3.0 license, notice, plan
- [x] Xcode project (tvOS app + Top Shelf extension) and the AnemoneKit package
- [x] SwiftLint / SwiftFormat config and CI
- [x] Spike: home screen with 10 rows × 50 posters. SwiftUI works with a non-lazy outer stack; hardware timing still open. See [spikes/home-focus.md](spikes/home-focus.md).
- [ ] Spike: MPVKit on Apple TV hardware with HEVC 10-bit HDR, ASS subtitles and TrueHD
- [ ] Spike: AVPlayer playing Jellyfin 12 HLS with Dolby Vision
- [ ] Spike: multicast entitlement and UDP discovery on tvOS
- [ ] App icon and Top Shelf image (tvOS layered brand assets)

### Phase 1: foundation

- [x] Add a server by URL: HTTPS first, then Jellyfin's default port; reverse-proxy paths kept; Jellyfin 12+ and finished-setup checks
- [ ] Server discovery (waits on the multicast spike)
- [x] Sign in with a password or Quick Connect
- [x] Multiple servers and profiles; switching protected by a hashed PIN or by requiring sign-in
- [x] Everything stored in one Keychain item; last profile restored on launch unless it's locked
- [x] Sign out via `/Sessions/Logout` (the SDK's `signOut()` needs admin rights)

Tested live against the Jellyfin 12.3 demo server (adding the server, the profile list, getting a Quick Connect code) and against the maintainer's own Jellyfin 12.2 server: password sign-in, session restore, PIN lock and unlock, a locked profile not being restored on launch, and sign-out.

tvOS ignores `.keyboardType(.numberPad)`, so PIN entry uses the full on-screen keyboard. A custom PIN pad is an idea for later.

### Phase 2: browsing

#### 2a: sidebar and home rows

- [x] Sidebar navigation (`TabView` with `.sidebarAdaptable`): Home, Search (placeholder), the user's libraries (placeholders), Settings
- [x] Home page with Wholphin's default rows: Continue Watching, Next Up, and Recently Added per library, with new episodes shown as their series; empty rows hidden
- [x] Focused-item header, and a backdrop that follows focus after 150 ms
- [x] Row memory and focus restore after Back, per the home-focus spike
- [x] Rows refresh quietly after Back to Home from an item page, on coming back to Home in the sidebar, and when the app returns to the foreground, like Wholphin on resume, so Continue Watching and Next Up stay current. Row memory and the header survive; if the focused card's item left its row, focus moves to that row's first card, or the next row if the row went, including when the refresh lands before Back has finished. Uses the same `pageTask` as item pages (see 2c), plus the sidebar selection
- [x] Artwork through Nuke, with Wholphin's image fallbacks
- [x] Item detail placeholder (title, year, overview) until 2c

#### 2b: libraries

- [x] Library grids, paged 100 items at a time ahead of focus, per the grid check in [spikes/home-focus.md](spikes/home-focus.md#library-grid-phase-2b)
- [x] Wholphin's sorts per library type; picking the current sort again reverses it
- [x] Filters: played, favorites, genres, studios (TV), community rating, parental rating, video type, year, decade
- [x] View options: card shape, columns, titles; defaults per library type
- [x] Alphabet jump bar when sorted by name, position footer, Back to jump to the top, random pick
- [x] Sort, filter and view options kept per library in UserDefaults (server sync later)
- [x] Pinned libraries in the sidebar: choose and order them in Settings › Sidebar; the rest go under More

Tested live in the simulator against the Jellyfin 12.3 demo server profile saved there in Phase 2a. Live TV keeps a placeholder until the guide in Phase 5. Not ported yet: Wholphin's other library tabs (Recommended, Collections, Genres, Studios), list layouts, the details header and backdrop options, and page jumps with the remote.

#### 2c: item pages

- [x] Movie page, also used for videos and types without their own page: title or logo, quick details (with "Ends at"), genres, tagline, overview, "Directed by", people, More Like This
- [x] Series page: studios and genres, Seasons row, people, More Like This; marking the whole series watched asks first
- [x] Season page (Wholphin's series overview), opened from a season or an episode: season tabs, the selected episode's details over the episode row, its actions, Cast & Crew and Guest Stars. Episodes outside a season get Wholphin's episode page
- [x] Collection page: a row per item type; the header and backdrop follow the focused card
- [x] Playlist page: numbered list beside the focused entry's details; reordering when the user can edit the playlist
- [x] Person page: photo, birth, birthplace, death, overview; Movies, TV Shows and Episodes rows
- [x] Mark watched or unwatched, and favourite, from item pages
- [x] Row memory and focus restored after Back, as on the home page
- [x] Pages reload quietly after Back from a page opened on top of them and when the app returns to the foreground, like Wholphin on resume, so watched and favourite state, seasons, episodes, collections and playlists stay current. Triggered from the stack's path, which each pushed page is handed directly: tvOS doesn't restart a covered page's tasks after Back, and doesn't pass a stack's environment on to the pages pushed on it
- Play, Resume and Restart play since Phase 3a. Play and Shuffle on series, collections and playlists are still marked as not wired up; they need queues
- Not yet: trailers, extras, chapters, version and track choice, delete, the context menu, collection sort/filter/view options, Seerr rows, theme music

#### Later in Phase 2

- Home page: the other row types (combined Continue Watching and Next Up, Recently Released, Genres, Studios, Favorites, Live TV rows, Suggestions, ByParent, GetItems, CustomEndpoint), customization, server sync, companion plugin
- Search, favorites, context menu

### Phase 3: playback v1 (AVPlayer)

#### 3a: first playback

- [x] PlaybackInfo with an AVPlayer device profile, adapted from Swiftfin's: direct play of MP4 and MOV; HEVC, AV1 and Dolby Vision offered only when VideoToolbox decodes them; HEVC only when tagged `hvc1` or `dvh1`; transcodes as HLS in fragmented MP4; 100 Mbit/s limit, Wholphin's default
- [x] The file itself when the server allows direct play, otherwise the server's HLS stream (direct stream or transcode). The token goes in the stream URL, since AVPlayer can't add headers
- [x] Wholphin's fallback: when direct play or direct stream fails, a transcode from the same position; when a transcode fails, an error page
- [x] Progress reports as in Wholphin: start once playback is under way, progress every 5 s and on pause or resume, stop with the final position. Reports go out in order, and a slow server doesn't pile them up
- [x] Play, Resume (an exact seek to the resume position) and Restart on movie, video and episode pages; selecting an episode card plays it from its resume position, as in Wholphin. The page reloads after playback, so Resume shows the new position
- [x] The system player (`AVPlayerViewController`) until Anemone's overlay: its transport bar and scrubbing, the title, episode and overview in its info panel, and Now Playing. At the end it closes, as Wholphin does with nothing up next

Tested live in the simulator against the Jellyfin 12.3 demo server: resuming a movie by direct play, the same movie forced through an HLS transcode, and closing with Menu, after which the page showed the new resume position. The demo server restores its data on a schedule, so positions there don't last between runs. A position isn't saved when the app is killed mid-play; Jellyfin keeps it with the play session until the session ends.

Resuming a transcode waits for the server to restart the transcode at the resume point, which took 9–14 s on the demo server; starting the seek before the stream is ready didn't help there. If the resume jump fails, playback stops with an error rather than starting over and overwriting the saved position.

Not yet: skip-back on resume, keeping playback going across the app going to the background, version choice, and a bitrate setting. Series, collection and playlist Play and Shuffle wait for queues.

#### Later in Phase 3

- Audio/subtitle choice, ported from `StreamChoiceService` (per-item and per-series persistence)
- Plex-style overlay: D-pad seek with acceleration, chapters, queue, trickplay
- Media segments (intro, credits, recap, preview, commercial): ignore / ask / auto-skip
- Next up with autoplay countdown and pass-out protection
- Queues: Play and Shuffle for series, collections and playlists
- Now Playing artwork and remote commands, frame-rate and HDR matching
- First TestFlight builds start here

### Phase 4: playback v2 (MPV)

- MPV engine and profile; player-choice rules (`EXO_PLAYER` → AVPlayer, `MPV`, `PREFER_MPV`)
- ASS and PGS subtitles, subtitle styling with a separate HDR style, subtitle delay, playback speed
- Subtitle search and download

### Phase 5: breadth

- Live TV guide, recordings and DVR scheduling
- Music, Now Playing, synced lyrics
- Photo slideshow
- Theme music, trailers (remote trailers hand off to the YouTube app), cinema-mode intros
- Seerr behind a build flag
- Top Shelf, `anemone://` deep links, in-app screensaver, colour themes

### Phase 6: App Store release

- Localization import from Wholphin's translations
- VoiceOver pass
- Privacy manifest and privacy labels (no data collected; logs go only to the user's own server)
- Export compliance (standard encryption only)
- ATS justification for user-entered plain-HTTP servers; local network usage string
- Demo Jellyfin server and reviewer login, with legally free media
- Custom GPL EULA, source tag per build
- Decide whether Seerr ships in 1.0

### Phase 7: iOS and iPadOS

- iOS target sharing AnemoneKit; touch-first screens
- Picture in Picture and AirPlay
- Widgets and Spotlight in place of Top Shelf
- Universal purchase with the tvOS app

## Not ported

- UpdateChecker and APK installs; AppUpgradeHandler migrations
- External-player intents
- MediaCodec probing and Fire TV defect lists
- ExoPlayer-specific hacks: HDR10+ SEI masking, tunneling, audio offload, `SubtitleView` reflection
- Android Dream screensaver; per-user UI language

## Fix while porting

- Wholphin stores tokens, PINs and the Seerr password in plaintext. Use the Keychain and a hashed PIN.
- Upstream bugs at the baseline, not to copy:
  - Per-series subtitle choices are loaded with the AUDIO type (`PlaybackViewModel.kt:499-503`; mirrored at `StreamChoiceService.kt:143`)
  - A missing `&&` in `MusicService.kt:305-306` makes any non-AC3 track trigger the AC3 transcode
  - Theme music "highest" volume is `75f` instead of `.75f` (`ThemeSongPlayer.kt:88`)
  - `TODO()` crashes for the video filter and playlist dialogs (`PlaybackPage.kt:292-296`)

## Tracking upstream

Periodically diff Wholphin from the baseline, port relevant fixes and features, and move the baseline in `NOTICE.md`.
