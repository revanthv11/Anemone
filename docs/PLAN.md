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

### Seams

So the rest of the plan can be built in separate files, side by side:

- **Player engine:** `PlaybackController` drives a `PlayerEngine`, never AVPlayer itself. An engine loads a URL at a start position, plays, pauses, seeks exactly, reports the time, duration and rate, sends status, end and failure events, lists and selects audio and subtitle tracks, and gives the UI its video output. `AVPlayerEngine` is the only one so far; MPV will conform the same way, as Swiftfin's AVPlayer and MPV players do.
- **Queue:** the controller plays a `PlaybackQueue` of entries (item, start position, metadata). Pages ask for playback with a `PlaybackRequest` (a queue, and whether to shuffle) from the builders in `App/Playback/PlaybackSupport.swift`, and `.player($request)` builds the controller. Every queue holds one item for now. `play(entryAt:)` and `playNext()` play another entry with its own PlaybackInfo and play session, after ending the current session.
- **Playback features:** each `PlaybackFeature` hears the controller's events in order (loaded, started, position once a second, paused, resumed, ended, failed, stopped), acts through the controller, and shows controls through `PlayerAccessories`: actions, transport-bar menus and a card. The system player shows them as `contextualActions`, `transportBarCustomMenuItems` and a card over the video; Anemone's overlay will show the same. Features are listed in `PlaybackController.features(for:)`; the first is `ProgressReporting`. At the end of an entry the player closes, unless a feature played another entry or set `closesAtEnd` to `false`; `finish()` closes it.
- **Settings:** `App/Settings/SettingsView.swift` has the account (switch user, profile lock, sign out) and a page each for Sidebar, Home, Playback, Subtitles, Appearance and About. Playback links to a page per part of playback. A setting is a `Preference` (a UserDefaults key and a default, with Wholphin's name and default where it has one), declared in an extension of `Preferences` next to what uses it, read with `value()` and bound with `@AppStorage(Preferences.someSetting)`.
- **Library kinds:** Live TV, music and photo libraries open `App/LiveTV`, `App/Music` and `App/Photos`.
- **UI tests:** `UITests/Support` has helpers to launch, wait for Home, press sequences, move and wait for focus, open a sidebar destination and attach screenshots. `UITests/SmokeUITests.swift` plays an item from Continue Watching for about 10 s, and runs only when asked to; its doc comment has the command.

Apart from Settings, now a list with a page for each part of the app, nothing visible changed. Tested live in the simulator against the Jellyfin 12.3 demo server: resuming a movie by direct play and closing with Menu still updates Resume on its page; Settings opens each page and comes back; the music library still shows its grid. With a throwaway feature, the system player showed a card over the video with focus on its first button, a contextual action, and a menu above the transport bar whose choice showed as selected. Not verified live: the Live TV and photo pages (the demo server has neither kind of library), listing and choosing tracks through the engine, and moving through a queue of more than one entry, which only the unit tests cover.

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

#### 2d: search

- [x] Search tab with the system search keyboard: results appear as the user types, 750 ms after typing pauses, as in Wholphin. The keyboard's dictation stands in for Wholphin's voice search button, so its "show voice search button" setting is left out
- [x] Submitting from the keyboard searches at once, like Wholphin's search button, and moves focus to the first row with results for the new term; rows that failed are tried again. A typed search leaves focus on the keyboard
- [x] Results in a row per type, in Wholphin's order: movies, TV shows, episodes, collections, people, albums, artists, songs, music videos, playlists, videos, photos and photo albums. Each row says "Searching…" until its own search ends; rows with nothing found are hidden. People are always searched, other types only when one of the user's libraries holds them. Results are ranked by Wholphin's `SearchRelevance`: exact name, then prefix, word start, anywhere, near miss, with `/pattern/` queries matched as regular expressions
- [x] View options: combined results (one grid of everything, best match first) and the types to include, kept per profile on the device. With every type left out, the page says no search types are selected instead of searching
- [x] Recent searches, which Wholphin doesn't have: a search is kept when one of its results is opened, up to 10, and offered before anything is typed, with a button to clear them. Picking one searches at once and moves focus to the first row with results, as Wholphin does after a search is submitted
- [x] Selecting a result opens its page on the Search tab's own stack; Back returns focus to the result, with the query and results still there. Like Home and item pages, the results are searched again whenever the page shows again (after Back, or back in the foreground), so cards show their new watched, favourite and progress state, and rows that failed are tried again
- [x] The requests behind Wholphin's `SearchForDialog` (search one type, and its newest items as suggestions), for picking a collection or playlist in Settings › Home (2e)

Fixed while porting: a home-videos library makes videos, photos and photo albums searchable (Wholphin's list keeps only photo albums), and a library of mixed content or folders makes movies, series, episodes and videos searchable (Wholphin searches none of them there).

Tested live in the simulator against the Jellyfin 12.3 demo server: typing "St. Louis" shows The Great St. Louis Bank Robbery in a Movies row; selecting it opens the movie page, and Back returns focus to its card with the query and results still showing. "th" gives Movies, Episodes, People, Albums and Songs rows. After relaunching, "St. Louis" is under Recent Searches, and picking it searches at once and moves focus to the result. After searching "Caminandes", then "St. Louis" with its card focused, picking "Caminandes" from Recent Searches moves focus to the first Caminandes card. Within one search ("th"), leaving the Movies row from its second card and coming back lands on that card, and so does Back from its page. Combined results show one grid; leaving People out hides its row, and including it again brings the row back. After picking a recent search (focus moves to its first result), going back to the keyboard and typing another term leaves focus on the keyboard when its results show. With every type left out, "St. Louis" shows the no-types message and no rows; switching the types back on brings the results without taking focus. Back from a result, which now searches again, keeps focus on its card. Not verified live: submitting from the keyboard, since XCUITest can't trigger the tvOS search keyboard's submit (Return and Play/Pause don't), so a submit during the debounce is covered by reasoning and the shared pick path only; dictation (the simulator has no microphone); rows for collections, playlists, music videos, videos and photos (the demo server has none of those libraries); a failed search's message and its retry; the refresh on returning to the foreground; and the `SearchForDialog` requests, which only the unit tests cover.

Not yet: Live TV channels and programs in results (with 5a), Seerr's Discover row (5d), the card context menu (2h), and artist pages: an artist opens the generic item page until music (5b).

#### 2e: home row types, customization and server sync

- [x] Wholphin's home-row JSON schema v1 as `HomeRowConfig` Codable types in AnemoneCore, written as Wholphin writes it and read as leniently: unknown rows are skipped, unknown enum values take their defaults, a newer version is refused
- [x] Every row type: Continue Watching, Next Up, the two combined (most recently watched first, a next episode dated by the episode before it or its premiere, as Wholphin's `DatePlayedService`), Recently Added, Recently Released, Genres and Studios (cards open the library's grid for that genre or studio), Favorites by type, Suggestions (Wholphin's mix, kept for 12 hours), a collection's or playlist's items with a sort, item queries, and other plugins' endpoints (paths on the server only)
- [x] Live TV rows (Watch Live, Channels, Active Recordings) read a `HomeLiveTVSource`, which Live TV (5a) fills; until then they stay empty, and `-homeMockLiveTV YES` shows made-up rows in DEBUG builds
- [x] Each row's view options drawn on Home: height, spacing, image type, aspect ratio, titles, series art, and the episode settings
- [x] Settings › Home: add, remove, reorder and configure rows; combine or split Continue Watching and Next Up; Wholphin's items-per-row, rewatching and max-days settings; the series removed from Next Up
- [x] Rows are saved in the DisplayPreferences entry of client `Anemone` (id `default`, key `home_settings`) and read from it first, then from the companion plugin's `GET /wholphin/homesettings` when `GET /wholphin/public` finds it, then Wholphin's default. Reset forgets the saved rows
- [x] Import from Wholphin copies its entry (client `Wholphin`, id `default`, key `home_settings`)
- [x] Remove from Next Up as Wholphin's `removeNextUp`, on a long press of a Next Up card until the card menu (2h) takes it over
- The default page is now Wholphin's: Continue Watching and Next Up combined, then Recently Added per library (Watch Live for Live TV), with Wholphin's default card look (posters, no titles)

Tested live in the simulator against the Jellyfin 12.3 demo server: adding a Genres row for Movies and moving it up a place, relaunching and finding it there and in Settings, read back from the server; a genre card opening its movies and Back returning to the card; switching the combined row off and on; Import from Wholphin with `-homeMockWholphin YES`, since the demo user has no Wholphin entry and Anemone only reads one; and Reset, which put the entry back to no saved rows, as it was before. PR #8's checks still pass: Back from an item page returns to the card that opened it and row memory holds, Home picks up changed rows when it's chosen again in the sidebar, and with a throwaway hook that dropped the opened card from the next refresh, focus landed on the row's first card. Jellyfin 12.3 puts a null `tvhome` in every DisplayPreferences entry, which jellyfin-sdk-swift 3.3.0's `[String: String]` can't decode, so the entry is read and written as plain JSON.

Not verified live: Remove from Next Up (it marks an episode unwatched, outside this stream's demo lane), the companion plugin (the demo server doesn't have it), Suggestions, Studios, Favorites, item-query and custom-endpoint rows, and the Live TV rows; unit tests cover each request.

Not yet: Wholphin's live preview beside the settings, display presets, and loading the web client's home sections. 4:3 cards are drawn 16:9 and content scale isn't applied, since Anemone's cards have three shapes and fill their frame.

#### 2f: library tabs and layouts

- [x] Movie libraries get Wholphin's tabs Recommended, Library, Collections and Genres; TV libraries Recommended, Library, Genres and Studios. Selecting a tab shows it, and the tabs tuck away while focus is past the first row, as in Wholphin. Other libraries keep the grid alone
- [x] Recommended: Continue Watching, Next Up (TV), Recently Released, Recently Added, Top Unwatched and Suggestions, under a header for the focused title over its backdrop. Suggestions are Wholphin's mix of unwatched titles in the genres of the last three watched, new ones and random ones, worked out when the tab opens rather than in the background
- [x] Collections: the box sets holding the library's movies, in the library grid with sort, filter and view options of its own
- [x] Genres and Studios: 16:9 cards with the alphabet bar. A genre's card shows a random title's backdrop under the genre's own colour, kept for two hours; a studio's shows its image, or its name. Each opens the library's titles in it ("Drama Movies"), with options shared by all of a library's genres, or all its studios
- [x] View options on library pages: grid, list and dense list layouts; the focused title's details over the grid or beside the list; its backdrop behind the page. Grid cards now show Wholphin's watched and favourite marks and unwatched counts
- [x] Page jumps with the remote: page up and page down (channel up and down on remotes that have them) move six rows, or more in big libraries, in grids and lists
- [x] "Remember selected tab" in Settings › Sidebar, off as in Wholphin: each library opens on the tab last chosen there. Kept per profile in UserDefaults

Tested live in the simulator against the Jellyfin 12.3 demo server, read-only: every tab of the movie and TV libraries; all five of the movie library's Recommended rows, and the TV library's Continue Watching, Recently Released and Recently Added (with one series, the demo data has nothing for its other rows); choosing a genre and coming Back to the card that opened it; the Library tab's grid moving, Back to the top, and paging with page up and down; the list and dense list, the details beside them and over the grid, and the backdrop; the tabs tucking away past the first row and coming back; and a remembered tab across a relaunch, then Recommended again with the setting off. The demo server has no collections and its series lists no studios, so the Collections tab was checked with made-up collections (the `-libraryMockCollections YES` launch argument, Debug builds only) and its empty message, and the Studios tab only with its empty message; neither has been checked against a server that has them. Paging was also checked on the Phase 2b spike's 500-item grid, and the spike's own grid test still passes. Page presses came from XCUITest's remote; the Siri Remote has no page buttons.

tvOS 26 places a page 49 points lower under the sidebar's title when it doesn't treat the page's top as a scroll view, which differs between Recommended and the grids, so the tabs are padded to stay at one height.

Not yet: "View more" at the end of Recommended rows, refreshing Recommended after Back, Wholphin's on-screen jump buttons (switched off in Wholphin too), long-pressing Back to return to where a jump started, the list's spacing option, and server sync of the remembered tab.

#### 2g: item page extras: trailers, extras, chapters, delete, collection options

- [x] Trailers on movie and series pages, ported from Wholphin's `TrailerService`: one plays at once, several are listed first, local trailers before remote ones and official trailers before teasers. Local trailers play in the player. Remote trailers hand off to the YouTube app (Wholphin opens them in the browser, which Apple TV doesn't have); when YouTube isn't installed, or the trailer is on another site, the page says so
- [x] Extras row, ported from Wholphin's `ExtrasService`: featurettes, deleted scenes, behind the scenes and the rest, a card per extra or per kind when there are several, on movie and series pages and for the season on the season page. Selecting one plays it; a kind's card lists its extras first. When the player closes, the row reloads, so the card shows the new progress or the extra watched
- [x] Chapters row on movie pages and for the selected episode on the season page: each chapter's image, name and start, which plays from there
- [x] Delete, after asking, for items the server lets the user delete (`CanDelete`): movies, videos, series, episodes and collections. The page goes back afterwards, as in Wholphin; on the season page it stays, on the next episode
- [x] Collection page sort, filter and view options, kept per collection: the collection's own order or Wholphin's movie sorts, the library page's filters, and Wholphin's "Separate types" (a row per type, or one grid with the library grid's view options)
- Extras, chapters, trailers and `CanDelete` come with one `/Items/{id}` request; local trailers and special features are asked for only when the item has some. A collection's page makes only that one request, for `CanDelete`

Tested live in the simulator. Against the local fixture server: a movie's six chapters with their images, and selecting the third played from 1:00; its Extras row (a featurette and a behind-the-scenes extra) and its local trailer both played, and the extra's card showed it watched as soon as its player closed; a remote YouTube trailer said to install YouTube, which the simulator doesn't have; the season page showed each episode's own chapters as focus moved along the episodes, and asked for them only once focus had stayed on an episode for 300 ms (passing over one quickly sent nothing for it); deleting a movie in a throwaway library asked first, went back, and took its files off the server; Home dropped it, and the library page did once reopened, since it doesn't reload after Back. The collection options were checked over a library's movies standing in for a collection, since neither server has one: sorting, filtering to unplayed, one grid, the grid's view options, and putting it all back; and over a music album, whose tracks have no row, it said there was nothing in it yet. Against the Jellyfin 12.3 demo server: a movie with two YouTube trailers listed both, numbered, and said to install YouTube. Not verified live: the hand-off to the YouTube app itself, series trailers and extras, a season's extras, a kind of extra with several entries, deleting a series, episode or collection, and a real collection.

Not yet: chapters for episodes outside a season, Wholphin's "Show media management options" setting (Delete shows whenever the server allows it), delete in the card context menu, and the details header option for collections.

#### 2h: Favorites page and card context menu

Not started. The Favorites destination is in the sidebar, before the libraries as in Wholphin's drawer, and hidden until this lands.

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

#### 3b: queues and Up Next with pass-out protection

Not started. Play and Shuffle for series, seasons, collections and playlists; Up Next with an autoplay countdown, and pass-out protection.

What tvOS offers the system player for this, checked in the tvOS 27 SDK's headers (each available since tvOS 15 or earlier and none deprecated, so all are in tvOS 26):

- `contextualActions` (tvOS 15): buttons over the video; `PlayerAccessories.actions` maps onto it. Suits "Next Episode" during the credits.
- `transportBarCustomMenuItems` (tvOS 15): `UIMenu`s and `UIAction`s above the transport bar, one level deep; `PlayerAccessories.menus` maps onto it.
- `customOverlayViewController` (tvOS 13): shown only when the user asks for it (swiping up, or a button in the transport bar), so it can't pop up an Up Next card on its own. `PlayerAccessories.card` shows as a SwiftUI card over the player instead; in the simulator, focus moved to its first button when it appeared, and its buttons worked.
- `AVContentProposal` and `AVContentProposalViewController` (tvOS 10): tvOS's own Up Next. Set `AVPlayerItem.nextContentProposal` with `contentTimeForTransition` and `automaticAcceptanceInterval`; at that time the player shows the app's `contentProposalViewController` subclass and shrinks the video into its `preferredPlayerViewFrame`, with `dateOfAutomaticAcceptance` for a countdown. The delegate's `playerViewController(_:didAcceptContentProposal:)` must load the next item (`playNext()`), and rejecting dismisses the player unless the delegate handles it. It's the native look, but only for the system player; Anemone's overlay (3e) and MPV need the card, so an Up Next built on the card works in both.

For pass-out protection, the system player keeps remote presses to itself. Pausing, resuming and scrubbing reach features as events; noticing any press would take a press observer in `PlayerScreen`.

#### 3c: media segments: skip intro, credits, recap and more

- [x] The item's segments from `GET /MediaSegments/{itemId}`: its own, of a known type, with a start before the end, in the order they play (checks adapted from Swiftfin's)
- [x] `SegmentSkipping`, a playback feature ported from Wholphin's `PlaybackViewModel`: for each kind, ignore it, ask (a "Skip Intro", "Skip Outro", "Skip Recap", "Skip Preview" or "Skip Ads" button over the video, which goes after 10 s), or skip it automatically. A segment is skipped or offered once per entry, so seeking back into one plays it; a retry as a transcode keeps that memory, the next entry starts afresh. A skip lands just past the segment's end, or at the end of the video, which then ends
- [x] The segment playing is published whatever the setting (`current`, and `onChange`), so Up Next can come up at the credits, as Wholphin's does. The skip button waits while a card such as Up Next shows, as Wholphin hides it while Up Next is up
- [x] Settings › Playback › Skip Segments: a choice per kind, with Wholphin's names and defaults (ask for intros, outros and commercials; ignore previews and recaps)
- [x] Debug builds take `-fakeSegments "intro:5-30,outro:45-100000"` (seconds) to give every item those segments, for servers without any; launch arguments such as `-skipIntros autoSkip` set a choice for one run

Tested live in the simulator against the local fixture server (Jellyfin 12.3 with the Chapter Segments Provider plugin), on a ten-minute video with Recap, Intro, Commercial, Credits and Preview segments and a counter burned into the picture: with the default settings the recap played with no button, "Skip Intro" appeared at 0:20 with focus, Select jumped to 1:20 and playback went on, and left alone the button went after 10 s and didn't come back; with recaps and intros skipped automatically, playback went from 0:00 to 1:20 within seconds and carried on from there; with intros ignored, the intro played with no button; with a fake segment running to the end skipped automatically, playback ended, the player closed and the server marked the video watched. The settings page showed each kind's choice and changed it. XCUITest can't see the system player's contextual actions, so those checks rest on screenshots.

Not verified live: commercial, preview and outro segments (the same code as intros and recaps; the unit tests cover them), the button waiting for an Up Next card (Up Next isn't merged yet), and keeping what was skipped across a retry as a transcode (unit tests only).

Not yet: Wholphin's skip button in its own playback controls for the rest of a segment, which waits for Anemone's overlay (3e), and dismissing the button with Back, which the system player keeps for itself.

#### 3d: audio and subtitle choice

Not started. Ported from `StreamChoiceService`, remembered per item and per series, with Audio and Subtitles menus in the player.

#### 3e: Anemone player overlay, seeking, chapters, trickplay

Not started. Plex-style overlay: D-pad seek with acceleration, clickpad scrubbing, chapters, queue, trickplay, and the controls features add.

#### 3f: Now Playing, display matching and playback settings

Not started. Now Playing artwork and remote commands, frame-rate and HDR matching, skip-back on resume, a bitrate setting, version choice, and what happens when the app goes to the background.

First TestFlight builds start once Phase 3 is done.

### Phase 4: playback v2 (MPV)

#### 4: MPV engine, ASS/PGS subtitles, styling, delay, speed, subtitle search

Not started.

- MPV engine and profile; player-choice rules (`EXO_PLAYER` → AVPlayer, `MPV`, `PREFER_MPV`)
- ASS and PGS subtitles, subtitle styling with a separate HDR style, subtitle delay, playback speed
- Subtitle search and download

### Phase 5: breadth

#### 5a: Live TV guide, recordings, DVR

Not started. Live TV libraries open `App/LiveTV`, which shows a placeholder until then.

#### 5b: music, music Now Playing, synced lyrics

Not started. Music libraries open `App/Music`, which shows the library grid until then.

#### 5c: photos slideshow, theme music, cinema-mode intros

Not started. Photo libraries open `App/Photos`, which shows the library grid until then.

#### 5d: Seerr behind a build flag

Not started.

#### 5e: Top Shelf, deep links, in-app screensaver

Not started.

### Phase 6: App Store release

#### 6a: release config: privacy, ATS, export compliance, licenses screen, EULA draft

Not started.

- Privacy manifest and privacy labels (no data collected; logs go only to the user's own server)
- Export compliance (standard encryption only)
- ATS justification for user-entered plain-HTTP servers; local network usage string
- Demo Jellyfin server and reviewer login, with legally free media
- Custom GPL EULA, source tag per build

#### 6b: colour themes, VoiceOver pass, localization import

Not started. Localization comes from Wholphin's translations.

Still to decide: whether Seerr ships in 1.0.

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
