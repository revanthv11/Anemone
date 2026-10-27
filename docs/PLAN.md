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
- **Queue:** the controller plays a `PlaybackQueue` of entries (item, start position, metadata). Pages ask for playback with a `PlaybackRequest` (a queue, whether to shuffle, and what follows) from the builders in `App/Playback/PlaybackSupport.swift`, and `.player($request)` builds the controller. `play(entryAt:)` and `playNext()` play another entry with its own PlaybackInfo and play session, after ending the current session.
- **Playback features:** each `PlaybackFeature` hears the controller's events in order (loaded, started, position once a second, paused, resumed, ended, failed, stopped), acts through the controller, and shows controls through `PlayerAccessories`: actions, transport-bar menus and a card. The system player shows them as `contextualActions`, `transportBarCustomMenuItems` and a card over the video; Anemone's overlay will show the same. Features are listed in `PlaybackController.features(for:)`; the first is `ProgressReporting`. At the end of an entry the player closes, unless a feature played another entry or set `closesAtEnd` to `false`; `finish()` closes it. Before each PlaybackInfo request the controller lets every feature `prepare(_:)` the `StreamRequest` (version, device profile, audio and subtitle indices), so a feature such as `TrackSelection` asks for its tracks without the controller knowing about it. `reload()` asks for the current entry again (for a track the stream doesn't carry) and plays on from the same position: features hear `stopped`, then `reloaded` instead of `loaded`, so what they keep for an entry, such as skipped segments or a cancelled Up Next, carries on.
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
- [x] Server discovery in AnemoneJellyfin: `ServerDiscovery` sends Jellyfin's "who is JellyfinServer?" to UDP port 7359 at each network's broadcast address and 255.255.255.255, then for 5 s lists each server that answers, once, from its JSON reply (id, name and address). BSD sockets, since a Network.framework connection only hears from the address it sends to; the port and addresses can be set, so tests answer on 127.0.0.1
- [ ] Discovered servers on the add-server screen: waits on Apple's multicast entitlement and the multicast spike
- [x] Sign in with a password or Quick Connect
- [x] Multiple servers and profiles; switching protected by a hashed PIN or by requiring sign-in
- [x] Everything stored in one Keychain item; last profile restored on launch unless it's locked
- [x] Sign out via `/Sessions/Logout` (the SDK's `signOut()` needs admin rights)

Tested live against the Jellyfin 12.3 demo server (adding the server, the profile list, getting a Quick Connect code) and against the maintainer's own Jellyfin 12.2 server: password sign-in, session restore, PIN lock and unlock, a locked profile not being restored on launch, and sign-out.

tvOS ignores `.keyboardType(.numberPad)`, so PIN entry uses the full on-screen keyboard. A custom PIN pad is an idea for later.

Server discovery is tested only by unit tests on macOS, against a stand-in server on 127.0.0.1 at a port the system picks: the probe's text, a reply becoming a server, a server answering twice listed once, stray datagrams ignored, a nameless server going by its host, the search ending on time, stopping early closing its socket, and which interfaces' broadcast addresses are used. Not verified: a real Jellyfin server answering a broadcast, and anything on Apple TV. Nothing in the app calls it yet.

Not yet: the multicast entitlement (`com.apple.developer.networking.multicast`), which iOS needs to send a broadcast and tvOS may too (the multicast spike checks on hardware). It's a user and Apple step: the maintainer asks Apple for it (developer.apple.com/contact/request/networking-multicast), then it goes in the app's entitlements and provisioning profile. After that, a "found nearby" list on the add-server screen, each server added through `ServerConnector` like a typed address, as Wholphin's server list does.

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
- Play, Resume and Restart play since Phase 3a; Play and Shuffle on series, collections and playlists since 3b
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

Not started. Wholphin's other library tabs (Recommended, Collections, Genres, Studios), list layouts, the details header and backdrop options, page jumps with the remote, and remembered tabs.

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

- [x] Favorites page in the sidebar, before the libraries as in Wholphin's drawer: a row per type where Wholphin has a tab per type, in its order, for the types the user's libraries can hold (up to 100 per row, by name), with a header and backdrop for the focused card. It reloads when it shows again and after a card's menu changes something; a row that fails is left out with a notice
- [x] Card context menu on a long press of Select, in Wholphin's order: Go to, Play or Resume and Restart, Add to playlist, Remove from Continue Watching, Remove from Next Up (Home's, from 2e), Mark as watched or unwatched, Add to or remove from favorites, and Go to series; people get Go to and favourites. `MediaCard` says what it shows, `CardRow` opens the menu on the card's button, and one handler set in `SignedInView` does the work, so every card on item pages and in Search has it
- [x] A change from the menu shows at once on every card of that item, until the card's page reloads with newer state
- [x] Add to playlist lists the 25 newest playlists the user may edit, as Wholphin does. One that already holds the item has a check, and choosing it takes the item out again; Wholphin doesn't look inside, so it can add an item twice
- Cards that hold only a `MediaItem` don't know whether it's watched or a favourite, so their menu offers both ways. Home and library grids don't pass their items to the menu yet, and Home sets which of its rows are Continue Watching and Next Up (`cardMenuSource`)

Tested live in the simulator against the Jellyfin 12.3 demo server, with throwaway UI tests: on The Great Train Robbery's card on a person page, the menu added it to favorites and marked it unwatched and watched again, with the card's heart and check following each time; the Favorites page then listed it under Movies, and removing it there from the card's menu took it off the page. "Go to series" on a Pioneer One episode card on the season page opened the series page, and Back returned to the season page. Add to playlist added the movie to playlist "123", showed the check the next time, and took it out again. Play from the menu played the movie and closed back to the page. Long-pressing a person card shows no menu. Not verified live: Resume and Restart, Remove from Continue Watching and Next Up (Home doesn't pass its items to the menu yet), the menu in Search results, and an item whose state the card doesn't know.

Not yet: Home rows and library grids passing their items (and Home its row types) to the menu; creating a playlist from Add to playlist; Wholphin's person card menu; delete (with 2g's option); after playing from a menu, focus returns to the page's first control rather than the card.

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

Not yet: nothing left from this part; skip-back on resume, pausing and playing on around the background, version choice and the bitrate setting came with 3f.

#### 3b: queues and Up Next with pass-out protection

- [x] Play and Shuffle on series, collections and playlists, ported from Wholphin's `PlaylistCreator`. Series Play starts at the episode next up, at its resume position, or at the first episode when nothing is next up, then goes on in order across seasons. Specials are left out: when Jellyfin's next up is a special it places between seasons, Play starts at the regular episode after it, and the fallback is the first regular episode, where Wholphin would play the special. A special next up after the last season plays, with any specials after it, as in Wholphin, rather than the series starting over. Series Shuffle has the server pick up to 100 random episodes, specials included as in Wholphin. Season Play and Shuffle are built for the card context menu (2h); the season page has no buttons for them, as in Wholphin
- [x] Collections play what's in them, with the episodes of any series in them, in the order and with the filters their page shows (as Wholphin's Play All takes them) or at random. In the collection's own order, the queue follows the page item by item, with a series' episodes where the series is. That fixes an upstream bug while porting: Wholphin's page asks for the collection's items (`recursive = false`), but its Play All asks for everything in it at once (`recursive = true`, `PlaylistCreator.createFromCollection`), which the server sorts by name, so Play All in the collection's own order doesn't play in the order the page shows. Playlists play in their own order from `/Playlists/{id}/Items`, or shuffled. Items that aren't videos, such as music or photos, are skipped and the player says how many; with nothing else to play, the page says so. A collection plays up to 100 items, Wholphin's limit for a queue; Wholphin leaves out the rest without a word, while the player here says how many play ("Playing 100 of 130 items")
- [x] An episode goes on through the episodes after it however it starts, as in Wholphin. They're found once it's loading, so it starts as quickly as before
- [x] Each entry has its own PlaybackInfo, play session and reports, and its stop report goes out before the next one's start report. Entries after the first start from the beginning, as in Wholphin
- [x] Up Next, from Wholphin's `PlaybackPage`: when an entry with another after it ends, a card over the last frame shows the next one's still and title and counts down (15 s by default) to playing it. Play Now plays it at once; Cancel closes the player. With "During the credits", it comes when segment skipping (3c) finds the outro playing, in place of the "Skip Outro" button: Cancel keeps the credits playing, and the card comes back at the end, as in Wholphin. It comes once for each outro, by its segment ID as Wholphin's `outroShownSegments` does, so a retry as a transcode in the credits doesn't bring back a card the user cancelled (one still up when the stream failed does come back). Moving on from the credits, by the countdown, Play Now or Keep Watching, ends the entry at its end, so the server marks it played. That fixes an upstream bug while porting: Wholphin's stop report carries where playback stopped (`TrackActivityPlaybackListener.release`), so an episode whose credits start before Jellyfin's played threshold (90%) stays resumable and in Continue Watching. Closing the player stops the countdown. Wholphin has no rule for showing it some time before the end: its choices are the end of playback (the default), the credits, or never. "Never" isn't ported
- [x] Pass-out protection: once 3 entries (by default) in a row have played on their own with no press on the remote, the card asks "Still watching?" instead, and playback stops when nobody answers within 60 s. Wholphin counts hours since the last press instead (2 by default). Presses are noticed at the window while the player shows, since the system player keeps them to itself; resuming from a pause counts too
- [x] Settings › Playback › Autoplay: when Up Next shows, autoplay on or off, the countdown (Wholphin's 0 to 60 s) and when to ask "Still watching?"

What tvOS offers the system player for this, checked in the tvOS 27 SDK's headers (each available since tvOS 15 or earlier and none deprecated, so all are in tvOS 26):

- `contextualActions` (tvOS 15): buttons over the video; `PlayerAccessories.actions` maps onto it. Suits "Next Episode" during the credits.
- `transportBarCustomMenuItems` (tvOS 15): `UIMenu`s and `UIAction`s above the transport bar, one level deep; `PlayerAccessories.menus` maps onto it.
- `customOverlayViewController` (tvOS 13): shown only when the user asks for it (swiping up, or a button in the transport bar), so it can't pop up an Up Next card on its own. `PlayerAccessories.card` shows as a SwiftUI card over the player instead; in the simulator, focus moved to its first button when it appeared, and its buttons worked.
- `AVContentProposal` and `AVContentProposalViewController` (tvOS 10): tvOS's own Up Next. Set `AVPlayerItem.nextContentProposal` with `contentTimeForTransition` and `automaticAcceptanceInterval`; at that time the player shows the app's `contentProposalViewController` subclass and shrinks the video into its `preferredPlayerViewFrame`, with `dateOfAutomaticAcceptance` for a countdown. The delegate's `playerViewController(_:didAcceptContentProposal:)` must load the next item (`playNext()`), and rejecting dismisses the player unless the delegate handles it. It's the native look, but only for the system player; Anemone's overlay (3e) and MPV need the card, so an Up Next built on the card works in both.

For pass-out protection, the system player keeps remote presses to itself. Pausing, resuming and scrubbing reach features as events; noticing any press takes a press observer, which `PlayerScreen` puts on the window while the player shows.

Tested live in the simulator against the Jellyfin 12.3 demo server and the local fixture server, mostly with a debug-only `-upNextCreditsAt <seconds>` launch argument that treats that point as the start of the credits in every entry. On the demo's Pioneer One: Play started S1E1 (with everything watched, so nothing was next up), Up Next offered S1:E2 with focus on Play Now, counted down and played it, and offered S1:E3 in turn; Cancel there took the card down and the episode played on until Menu closed the player. Shuffle played a random episode with another offered next. With "Still watching?" after 1 autoplay, the second episode asked instead of counting down, and unanswered, the player closed after 60 s; a press of Up on the remote during the second episode made it count down instead, so the system player's presses do reach the observer. Play on the playlist My New Playlist started The Boy in the Plastic Bubble with Caminandes: Gran Dillama next; no page linked to a playlist then (Search came later), so a temporary debug hook, not committed, opened it. On the fixture's Fixture Show: Play went S1E1, S1E2, S1E3, then S2E1, past the special; played to their real ends, S1E1 and S1E2 each showed Up Next over the last frame and autoplayed the next, and Cancel at the end closed the player; from unwatched, after S1E1 autoplayed into S1E2, the season page showed both watched and S1E3 not. With "During the credits", the episode's real Credits segment at 2:30 brought Up Next, Cancel kept the credits playing, and the card came back at the end. Settings › Playback › Autoplay showed each setting with its value, and its choices on a page of their own.

Not verified live: the note about skipped items (no mixed playlist), Season Play and Shuffle (no buttons yet), autoplay off and an immediate countdown, the Still watching buttons themselves, and a transcode retry after a stream fails partway (unit tests, and a test that AVPlayer keeps playing into the next item unless paused).

Follow-up fixes, tested live against the fixture server with Anemone's overlay, whose title and queue row XCUITest can read; each entry was paused within a second of starting and closed, so the server changed nothing. The collection Anemone Fixtures (6 movies, found through Search): in its own order, Play queued the movies as the page listed them (Anemone H264 Chapters first), where before the fix it began with Anemone DTS TrueHD, as a name sort would; sorted by name, either way, Play followed the page; with Played set to Unplayed, it queued the 4 unwatched movies in the page's order; Shuffle twice gave two different orders of all 6. The page's sort and filter were put back. On Fixture Show, with "During the credits" and a fake outro at 0:02 (`-fakeSegments`), Up Next came up with no "Skip Outro" button before or under it, and after Cancel the button showed, as in Wholphin. The test user doesn't see the playlist Fixture Mix: a search with playlists included finds no playlist.

Not verified live: that moving on from the credits marks an entry played (Jellyfin marks an item shorter than its minimum resume duration, 5 minutes by default, played when it stops partway, so the fixture's 3-minute episodes can't show the difference; unit tests check the stop report goes out at the end), the note when a collection has more than 100 items, a special next up after the last season, and a retry as a transcode in the credits (unit tests).

Not yet: the queue row and next and previous controls in Anemone's overlay (3e), playing a playlist from one of its entries, a movie's additional parts, cinema intros before the first entry (5c), and Wholphin's "Never" timing.

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

- [x] Wholphin's `StreamChoiceService` in `AnemoneCore/StreamChoice`: the user's pick for the item, else their pick in another episode of the season or series (scored by language, flags, position and channels), else the language and subtitle-mode settings, which fall back to the Jellyfin profile's. Wholphin's own test cases are ported. Language codes match however they're spelled (`fre`, `fra`, `fr`)
- [x] Tracks are chosen before PlaybackInfo, which `TrackSelection` asks for them through the features' `prepare(_:)` hook, together with their version (the one picked on the item's page while the item has it, else the first); without the version the server ignores them and uses what it last heard for the item
- [x] Audio and Subtitles menus in the player through `PlayerAccessories`: every audio and subtitle track, Off, and Only forced when the file has forced or signs subtitles. A menu with nothing to choose isn't shown. Only forced, picked for the item or kept for the season or series, shows as Only forced and finds the forced track again when the audio changes
- [x] Picks are remembered per item and, for episodes, per season and series (Wholphin also keeps a movie's pick for its parent folder; Anemone doesn't). They're kept in UserDefaults: the latest 200 items and 100 seasons or series per user, read once per player and written once per pick
- [x] Audio in a file that plays directly and text subtitles in Jellyfin's HLS switch in the player. Anything else asks the server for another stream and plays on from the same position after ending the play session (`PlaybackController.reload()`), as Wholphin's `changeStreams` does. It's still the same entry to the other features, so an Up Next cancelled during the credits and skip buttons already gone stay gone, a switch before the stream is ready keeps the resume position, and a switch while paused stays paused
- [x] Picture subtitles (PGS, DVD) and, on AVPlayer, ASS and SSA are burned in by the server, so ASS keeps its styling. `MediaTrack.isStyledText` and `isPicture` mark what MPV (Phase 4) can draw itself; `TrackSelection.burnsInStyledSubtitles` turns ASS burn-in off
- [x] Settings › Playback › Audio and Subtitles: audio and subtitle language from the server's list, when subtitles show, and forgetting picked tracks. Settings › Subtitles has the subtitle rows too
- [x] Fixed from Wholphin: per-series subtitle choices were looked up as audio ones (`PlaybackViewModel.kt:499-503`), so they never applied

Tested live in the simulator against the fixture server (Jellyfin 12.3): "Anemone Multi Track" started with English AAC and the default English SRT. SDH subtitles switched in the player; French AC3 took a new stream and went on from the same position; German PGS and the styled Spanish ASS showed burned in, ASS with its karaoke styling; playing the film again brought back French audio and the PGS. In "Fixture Show" season 2, Spanish subtitles picked in episode 1 were chosen for episode 2. On the demo server, King Lear (one audio track, no subtitles) played without the menus. Settings › Playback › Audio and Subtitles showed the profile's settings and forgot picked tracks. Checked again with Up Next and segment skipping in the player (3b, 3c): the defaults, German PGS burned in over the English audio, and French AC3 from 0:56 going on from there; in season 2 episode 2, with "During the credits", switching audio in the intro after its Skip Intro button had gone didn't bring the button back, and switching audio again after cancelling Up Next in the credits didn't bring Up Next back; episode 3 then started with the Spanish subtitles and the English audio picked in episode 2. Checked again after merging 3b's credits changes, and again after merging 3f, in Anemone's overlay: "Anemone Multi Track" paused at 0:12 and switched to French AC3 took a new play session and stayed paused at 0:12 for 17 s, then played on from there when resumed; in season 2 episode 2, with Up Next at 0:45, switching to Japanese audio after cancelling Up Next didn't bring it back, and episode 3 then started with the Japanese audio. Settings › Playback › Audio and Subtitles opened by its `settings.playback.audioSubtitles` link. Checked again after merging 5a: French AC3 picked at about 0:24 in "Anemone Multi Track" took a new play session and played on (0:44 twenty seconds later, no error), and playing the film again opened its Audio menu on the French track. A switch that reloads a live channel closes the old live stream once, through the stop report or, before playback is under way, `LiveStreamClosing` (unit-tested; not tried live).

What playing showed:

- AVPlayer didn't show HLS subtitles selected before playback got under way, the server's default included, until they were selected again; `TrackSelection` selects them again once playback is under way.
- Jellyfin's HLS WebVTT subtitles show 10 s late in a remuxed (fMP4) stream. Its subtitle segments map their cues with `X-TIMESTAMP-MAP=MPEGTS:900000` (10 s), but the remuxed video starts at 0. Burned-in subtitles are in time.
- Burning subtitles in at 40–60 s while the French AC3 audio played failed each of the three times it was tried: after the server restarted the transcode there (copying the AC3), AVPlayer asked for segments near the end and gave up. Burning them in early, or at 50 s with the English AAC, worked.

Not verified live: switching audio in place in a file that plays directly (the fixture's multi-audio files are MKV, so they're remuxed), VobSub, external subtitle files, Settings › Subtitles. Not yet: drawing text subtitles in the app (P3b), which ends the 10 s offset; a fix for burning in subtitles while AC3 audio plays; progress reports keep the stream's track indices after a switch in the player; the system player still shows AVKit's own Audio and Subtitles buttons beside Anemone's.

#### 3e: Anemone player overlay, seeking, chapters, trickplay

- [x] Settings › Playback › Player Controls: the system player, still the default, or Anemone's overlay, with Wholphin's skip amounts (10 s back, 30 s forward), how long the controls stay up (5 s) and a debug panel. Engines that draw their own video, as MPV will, always get the overlay
- [x] Wholphin's overlay over an `AVPlayerLayer`, driven only through the controller and its `PlayerEngine`: the title, episode, tracks playing and "Ends at"; the seek bar and its times; Previous, skip back, Play/Pause, skip forward and Next; a pause indicator. Previous restarts the entry unless it's within 3 s of the start, as in Wholphin
- [x] D-pad seeking that speeds up while held. SwiftUI's move commands don't say how long a press lasts, so a view controller takes `pressesBegan` and `pressesEnded` before the focus engine, as Swiftfin's player does, and repeats a held press at Android's pace (every 50 ms after 500 ms) through Wholphin's `SeekAcceleration` tiers; with the controls hidden the first 8 repeats pass, as in Wholphin. The seek lands 750 ms after the last press, as Wholphin's seek bar waits; Select seeks at once and Menu drops it. Menu then hides the controls, then closes the player
- [x] Swipe scrubbing on the clickpad, with the controls hidden or on the seek bar: a swipe across the surface covers a fifth of the video, between 2 and 10 minutes
- [x] Trickplay thumbnails over the seek bar, from the item's trickplay for the version playing, at the widest width up to 480 px. Sheets come through the session, since they need the token, and only the three asked for last stay decoded: a sheet that finishes loading after seeking has moved on keeps just its JPEG
- [x] The chapter row with the chapters' images, starting on the chapter playing, and the queue row with what plays after this entry, below the transport as in Wholphin
- [x] What features add through `PlayerAccessories`: their actions over the video take focus when they appear, their menus open as lists over the controls, and the card shows above everything, as with the system player
- [x] A debug panel behind a setting: the engine, play method and session, version, position, speed, trickplay, chapters and tracks

Wholphin's `TODO()` crashes for the playlist and video-filter dialogs (`PlaybackPage.kt:292-296`) aren't ported: the overlay has neither action.

Tested live in the simulator against the fixture server, with Anemone H264 Chapters (3 minutes, 6 chapters, trickplay): right twice with the controls hidden showed the compact seek bar with a thumbnail and landed a minute on; Select brought up the controls on Play/Pause; on the seek bar two presses moved 60 s with a thumbnail over the bar; down from the transport opened the chapter row on the chapter playing, and choosing an earlier one jumped there; Play/Pause paused and resumed, as the debug panel showed the controller heard; Menu hid the controls, then closed the player; and with 3c's `-fakeSegments`, Skip Intro showed over the video with focus and skipped the intro. And against the demo server, with Night of the Living Dead (96 minutes, trickplay): holding right for 2 s moved 11 minutes and then holding for 5 s moved 47, where the 2 s hold's pace would have reached 41 (a hold starts seeking after 0.9 s), and after closing the page offered Resume from where the seek had landed. With the setting left at System, the system player is unchanged. Jellyfin keeps no resume position for videos under 5 minutes, so the fixture movie's page offered Play again. After review: on the fixture movie, paused at 2:35 in the last chapter, whose card starts off screen, down from the transport opened the row on that card, and after choosing the second chapter the row opened on it; the times read 2:35 and -0:25 beside "Ends at"; and on the demo movie, a 5 s hold and then a 2 s one crossed three trickplay sheets and the compact bar still showed the thumbnail for where each landed.

Not verified live: swiping on the clickpad, which the simulator's UI tests can't do (the scrubbing itself is unit-tested), the queue row, which needs more than one entry (3b), and features' menus and cards in the overlay, since no feature adds any yet.

Not yet: Now Playing and remote commands while the overlay plays, which 3f adds for both players; skip-back on resume; a playback speed menu.

#### 3f: Now Playing, display matching and playback settings

- [x] `NowPlaying`, a playback feature: the title, episode, artwork (the entry's, which Up Next's card shows too), position and queue place in `MPNowPlayingInfoCenter`, and the remote's play, pause, skips (Wholphin's 30 s forward and 10 s back), scrubbing, and next and previous through the queue (`playNext()` and `play(entryAt:)`; Previous restarts the entry after its first 3 s, as Media3's does; Next comes on once an episode's following episodes are found). A command counts as a press for pass-out protection. Commands adapted from Swiftfin's `NowPlayableObserver`. AVKit's system player publishes Now Playing and answers the remote itself, so with it the feature only adds the artwork to the AVPlayer item's metadata, for the info panel and Now Playing; with Anemone's overlay (Settings › Playback › Player Controls) or MPV, it publishes everything. The system's artwork is made once per entry, and the position updates change only the timing
- [x] Frame-rate and HDR matching: `DisplayCriteria` from the video PlaybackInfo describes, with no request of its own (frame rate as Wholphin's `RefreshRateService` reads it, dynamic range, Dolby Vision as its base layer without a Dolby Vision decoder). A transcode is what its transcoding URL says the server sends: the video as it is when only the container or the audio doesn't suit, HDR and all; otherwise the first codec it may encode to, keeping HDR10 or HLG where the profile takes that range in the codec (HEVC on an Apple TV 4K) and SDR otherwise; H.264 in SDR when the URL doesn't say. The criteria go to `AVDisplayManager.preferredDisplayCriteria` as a format description, through one display that every player's `DisplayCriteriaMatching` shares. It goes back to its usual mode 2 s after the player closes, unless the next entry or player asks for a mode first; only the player that asked last can reset it, so a closing player never undoes the next one's mode. tvOS's Match Content setting stands in for Wholphin's refresh-rate and resolution switches. The system player matches the display itself (`appliesPreferredDisplayCriteriaAutomatically`), so this is for the overlay and MPV, like Now Playing
- [x] Skip back on resume (`SkipBackOnResume`, from Wholphin's `MediaSessionPlayer`): each resume after a pause goes back by the setting, 0 (off, Wholphin's default) to 10 s
- [x] Max bitrate: Wholphin's choices from 500 kbit/s to 200 Mbit/s, 100 Mbit/s by default, sent with PlaybackInfo in place of the fixed limit
- [x] Version choice: a Version button on movie and episode pages for items with several versions (media sources), with Wholphin's "Choose Version" list. The choice is remembered per user and item, as Wholphin's `ItemPlayback` does, and the player asks for it whenever it plays that item, from a page or a queue; a retry as a transcode keeps the version playing. A version gone from the server is forgotten when the page next loads, or when PlaybackInfo answers without it, wherever the item plays from (Home, Up Next, a card menu); the server's first version then plays
- [x] The background (`PlaybackLifecycle`, from Wholphin's `PlaybackLifecycleObserver`): going home mid-play, or while the stream is still loading, pauses, which reports the position while tvOS gives the app a few seconds, and keeps the play session open; coming back plays on. Music will turn it off with `pausesInBackground`
- [x] Settings › Playback › Streaming and Display: the bitrate and skip-back settings, and whether Match Content is on
- [x] Debug builds take `-fakeVersions <n>` to give every item n versions, copies of its first, for trying the picker. Integer settings take launch arguments in plist form, such as `-maxBitrate "<integer>500000</integer>"`

Tested live in the simulator against the Jellyfin 12.3 demo server, on a movie resuming at 17:51: the system player's info panel showed the artwork beside the title and overview; with skip-back at 10 s, pausing at 17:56 and playing again went on from 17:46, and the saved position after closing was back at 17:51; going home mid-play for 15 s and coming back played on from where it was, and the saved position counted only the time on screen; with the bitrate limit at 500 kbit/s the server sent a transcode where it otherwise direct plays (the log says which); the system player reported `appliesPreferredDisplayCriteriaAutomatically` on. With Anemone's overlay, Now Playing and display matching are the features' own: the log showed the criteria asked for (29.97 fps, SDR), and Play/Pause on the remote still paused once and resumed 10 s back. Settings › Playback › Player showed and changed the bitrate. On the local fixture server, with `-fakeVersions 3`, the Version button showed on a movie page, its list marked the version that plays, and picking another moved the mark. After review, on the same movie with the overlay and P5's overlay on main: direct play logged its criteria (29.97 fps, SDR, `avc1`) from PlaybackInfo, and the system's Now Playing log showed the title, position and one artwork kept across updates; at 500 kbit/s the transcoding URL said `VideoCodec=h264`, `h264-rangetype=SDR,DOVIWithSDR` and `TranscodeReasons=ContainerBitrateExceedsLimit`, and the criteria followed it (SDR `avc1`); with a fake version picked (`-fakeVersions 2`), Resume played the server's first version instead of failing, and the pick was gone from the app's defaults afterwards; going home just after Resume on a transcode, the app reached the background 1.4 s after the stream loaded, nothing played while it was away for 25 s, and it played on when it came back. Settings › Playback now lists Streaming and Display, which opens the same settings.

Not verified live: Now Playing in Control Center (the simulator's Control Center shows no Now Playing tile), so the info and remote commands the feature publishes with the overlay rest on unit tests, and nothing sent them from a phone's Remote; the display switching itself (the simulator has no display modes and Match Content is off there; the criteria are unit-tested, and Dolby Vision and frame-rate switching need real hardware); an HDR transcode (the demo server has no HDR, and P4's lane leaves the fixture's HDR10 file alone; the transcoding-URL reading is unit-tested); going home before PlaybackInfo answers, a window too short to hit from a UI test (unit-tested); a stale version played from a card menu on Home, whose cards don't have the menu yet (the same player path, played from the page, is above); and playing a version other than the first (no demo or fixture item has several; the request is unit-tested).

Not yet: Next and Previous for the system player, which has no buttons for them (Up Next covers moving on); Wholphin's media-session artwork, the primary image (the series poster for episodes), since an entry carries one artwork URL, the thumb Up Next's card uses; and per-user skip and bitrate settings, which are per Apple TV for now.

First TestFlight builds start once Phase 3 is done.

### Phase 4: playback v2 (MPV)

#### 4: MPV engine, ASS/PGS subtitles, styling, delay, speed, subtitle search

Not started.

- MPV engine and profile; player-choice rules (`EXO_PLAYER` → AVPlayer, `MPV`, `PREFER_MPV`)
- ASS and PGS subtitles, subtitle styling with a separate HDR style, subtitle delay, playback speed
- Subtitle search and download

### Phase 5: breadth

#### 5a: Live TV guide, recordings, DVR

- [x] Live TV libraries open Wholphin's page (`CollectionFolderLiveTv`): tabs for the guide, the channels, the DVR schedule, then each folder of recordings (the library grid, with its filters and view options; as in Wholphin, a folder lists its top level, with the video sort options, whatever its collection type, so each comes back as a plain folder library). A tab shows when it's focused, and moving up into the tabs lands on the one showing
- [x] The guide (`TvGuideGrid`, `LiveTvViewModel`): channels down the side, 48 hours from the half hour before now across, the focused programme's details above, the times along the top and a line at now. Gaps in the listings are filled with "No data" an hour at a time, ending on the guide's hours. Rows scroll as focus moves; across, a window of two and a half hours moves on when focus leaves its last programme, and back when focus leaves its first while the guide is ahead of now. Left from what's on now reaches the channel; Back goes to now, then to the first channel. Listings load 20 channels at a time as rows come on screen
- [x] Wholphin's programme cells: the series' name, the episode and its title, a caret when it began earlier, red dots for a recording or a series recording, and its category's colour (kids, movie, news, sports)
- [x] Programme details (`ProgramDialog`), loaded fresh: Watch Live while it airs, Record until it ends, Record Series for a series, each becoming Cancel once set. Records from the server's default timer, as Wholphin does, so the server's padding and keep-until apply. Every row loaded so far then loads again, since a series recording marks programmes on other channels too. An empty stretch airing now plays the channel; a later one says nothing is listed
- [x] Channels: the guide's channel opens Watch Live and Add to (or Remove from) Favorites, as Wholphin's channel dialog; the Channels tab shows every channel with what's on now, selecting one watches it and a long press changes the favourite
- [x] The DVR schedule (`DvrSchedule`): recordings under way, from the server's recordings as in Wholphin, each playing what has been recorded so far, with a long press to cancel it or its series; then those scheduled, by day, each opening its programme to watch or cancel; then the series set to record, each with a way to cancel it, which Wholphin's schedule doesn't list
- [x] Wholphin's view options, kept on the device, from a button above the channels: show details, favourite channels first, channels by recently watched, colour-coded programmes
- [x] Live playback through PlaybackInfo with `isAutoOpenLiveStream`. Once playback is under way the stop report carries the live stream and the server closes it; when the player closes or fails before that, `LiveStreamClosing` closes it with `POST /LiveStreams/Close` (adapted from Swiftfin), never both, so a tuner stream another viewer shares isn't cut off. A live stream that arrives after the player closed, or after another load replaced it, is closed too
- [x] AVPlayer's device profile offers HLS in MPEG-TS after the fragmented MP4 one, since Jellyfin sends live channels with its most compatible profile, a TS one, unless the tuner allows fMP4; without it, the server offers a progressive TS stream AVPlayer can't play
- [x] Home's Watch Live, Channels and Active Recordings rows ask the server as Wholphin's `HomeDataService` does. A channel card plays the channel, as Wholphin's does; a programme card opens its details, as Wholphin's search does
- Debug builds take `-liveTVMockGuide YES` to fill the server's channels with made-up listings, for a server with channels but no guide data

Fixed while porting: Wholphin's schedule crashes on a timer set by time with no programme (`programInfo!!`); the timer's own name and times stand in. Times are instants rather than local date-times, so a programme across a daylight-saving change keeps its length without Wholphin's special case.

Tested live in the simulator against the local fixture server (Jellyfin 12.3, five M3U test channels): the guide showed the five channels with their logos; moving right past the window's end moved it on an hour at a time to 7 AM, left moved it back, Back returned to now and, from the third channel, to the first; left from now reached the channel. The fixture had no listings at the time (the server returned no programmes at all), so the programme cells, their details and colours were checked with `-liveTVMockGuide YES` over the real channels: moving along a row past the window, down to the fourth channel and back, and a series' details offering Record Series and Record. The Channels tab listed the five channels. Choosing the empty stretch airing now on the first channel played it live for 15 s, which the server sent as HLS in MPEG-TS, and on closing, the server's log showed the stop report closing the live stream at once, with no second close; without the TS profile, the player had said it couldn't play the channel ("Operation Stopped"). Closing the second channel while it was still loading sent `POST /LiveStreams/Close`, and the server closed that stream. Adding the first channel to favourites from its dialog showed the heart, and removing it took the heart away. Turning Show Details off and on hid and showed the details. The schedule, asking for the recordings under way as Wholphin does, said there were no scheduled recordings. With `-homeMockLiveTV YES`, choosing a Watch Live card asked the server for its programme instead of opening the item page (its made-up ID got "Something went wrong"). After merging Phase 3f and 5e, the empty stretch airing now on the first channel played it live again for 24 s, as HLS in MPEG-TS, and on closing, the stop report closed the live stream once.

Not verified live: recording a programme or a series and cancelling either, from the guide or the schedule, the markers on every row changing afterwards, the schedule's rows, playing or cancelling a recording under way, the recordings tabs, and Home's real Live TV rows and a channel card, since the fixture still had no listings (after another Refresh Guide every channel still showed "No data", its database held no programmes, and its Live TV settings listed no guide data provider) and no recordings or recording folders; unit tests cover each request. A live stream arriving after the player closed: the fixture opens M3U streams too fast to close the player while one is on its way, so a unit test covers it. A channel playing past a direct play attempt (Jellyfin offered live channels as transcodes only).

Not yet: Live TV channels and programmes in Search.

#### 5b: music, music Now Playing, synced lyrics

- [x] Music libraries get Wholphin's tabs (`CollectionFolderMusic`): Recommended (Recently Released, Recently Added, Top Rated and Suggestions rows of albums), Albums, Artists (every artist, from `/Artists`), Genres (each with one of its albums' covers, opening its albums) and Songs. A tab shows as soon as it's focused. The grids page in 100 at a time with Wholphin's music sorts, kept per list on the device; Albums, Songs and a genre's albums have Play and Shuffle for all of them. Songs queue in the order the tab's sort shows them (a random sort comes from the server in one draw); albums and genres queue by album artist, album and track. Album cards show the album artist and year (upstream `90a2d6d`)
- [x] Album page (`AlbumDetailsPage`): cover, artist, title, details, genres and overview; Play, Shuffle, Instant Mix, favourite, the album artist's page, and Now Playing while music plays; the songs, marked when playing or queued, naming their artists on albums by several; More Like This. Selecting a song plays it and the songs after it, as Wholphin queues them. A song opened from anywhere (the Songs tab, Search, a playlist) opens its album's page with the song focused
- [x] Artist page (`ArtistDetailsPage`): Popular Songs, then rows of Albums, Appears On and More Like This
- [x] A long press on a song: Play, Play Next, Add to Queue, Go to Album and Go to each artist; Play/Pause on a song card in the Songs tab plays it
- [x] `MusicPlayer` (Wholphin's `MusicService`): a queue with ExoPlayer's shuffle and repeat (off, all, one; Previous restarts a song after 3 s), Play Next, Add to Queue, move and remove. A library, artist or genre pages in as it plays, up to 1,000 songs; shuffled, it's a random draw from the server. Each song plays through a `PlaybackController` of its own with an AVPlayer engine and progress reports, from the universal audio endpoint: MP3, AAC, ALAC, FLAC, WAV and AIFF as they are, anything else as MP3, and a song that won't play as it is gets another try as MP3. Paused stays paused, as ExoPlayer keeps `playWhenReady`: a song paused while it loads, or moved to while paused (Next, Previous, removing the one playing), loads and waits, and so does the first song of a queue paused while it's fetched (an album or library, a shuffle, an instant mix). A page that fails once a queue has started ends the queue there, and the music plays on
- [x] Music plays on after leaving Now Playing and with the app in the background (the `audio` background mode); it stops when a video starts (the `MusicStopping` playback feature) and when the profile's session ends, as Wholphin stops it on leaving for the user list. Now Playing and the remote's play, pause, next, previous and scrubbing go through `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter`, and stopping switches those commands off again. A video stops the music before 3f's `NowPlaying` feature hears it load, so the video's Now Playing and commands aren't switched off after it takes them
- [x] Now Playing page (`NowPlayingPage`): cover, title, album and artists; lyrics from `/Audio/{id}/Lyrics` beside them, synced ones with the line being sung highlighted and kept in the middle, and a selected line jumping there; progress; Stop, Previous, Back 10 s, Play/Pause, Forward 30 s, Next, Shuffle, Repeat and options; the queue in play order as an Up Next row, where a song plays when selected and moves, plays next or goes on a long press; the first artist's backdrop behind. Play/Pause on the remote works anywhere on the page; Back from the lyrics or the queue goes to the buttons first, then leaves the page
- [x] Wholphin's Now Playing options (show cover, lyrics, backdrop) and its experimental "Use AC3 for surround sound audio", in Now Playing's options

Fixed while porting: the missing `&&` in `MusicService.kt:305-306` sent every song that wasn't AC3 to the AC3 transcode when the setting was on; now only songs with more than two channels go. Wholphin's AC3 transcode comes in Matroska, which AVPlayer can't play, so Anemone's comes as fragmented MP4 over HLS.

Wholphin's queue is a list that grows over the page when focused; here it's a row along the bottom, as Apple TV's own Up Next is, so the lyrics keep their own scrolling. Starting music from a page opens Now Playing, since tvOS has no drawer to show what's playing.

Tested live in the simulator against the Jellyfin 12.3 demo server and the local fixture server. On the demo server: the tabs show 4 albums, 3 artists and 5 songs, and Nemesis's card reads "Leap Fidei - 2024"; a song in the Songs tab opens Promo focused on it, and an artist card opens Binaerpilot's page; Play on Promo opened Now Playing with Thunderdays playing, Next went to Cornered! (Promo Edit), Down from the buttons reached the current song in the queue, selecting the first song played it, and a long press then Remove from Queue took the other out; Back left Now Playing with the album page offering Now Playing, and the song had moved on 15 s when it was opened again; with the app in the background for 8 s the song moved on 11 s; Stop closed Now Playing and the album page stopped offering it. Thraximundar's lyrics showed with their first line current, and Instant Mix on Promo queued three Binaerpilot songs. On the fixture server, whose Fixture Album has a synced `.lrc` per song: at 0:06 the first line (0:02) was highlighted and at 0:13 the third (0:13); selecting the seventh line (0:35) jumped to 0:37 with it highlighted; Back from the lyrics returned to Play/Pause without leaving the page; playback, Next, the queue, leaving, the background and Stop behaved as on the demo server. After the first review, on the demo server with the Songs tab sorted by Name descending: Play started Jellyfin, the tab's first card, with the queue in the grid's order; paused, the position held, Next went to Cornered! (Promo Edit) and stayed paused at 0:00, and removing it from the queue went to Thunderdays, still paused at 0:00; Play played it; Next followed at once by Play/Pause left Thraximundar paused at 0:00; Stop closed Now Playing. After the second review, with a 2 s delay added to the song fetches for the run (not committed), so the pause landed while the queue was still being fetched (the player's log showed it paused with no queue yet, then the queue starting paused): Shuffle on the Songs tab, paused as soon as Now Playing showed, left Cornered! (Promo Edit) paused at 0:00 for 7 s, and Play/Pause played it; Instant Mix on Promo, paused the same way, left Thunderdays paused at 0:00 until Play/Pause; Play on the Songs tab, not paused, played Bend. After merging 3f and 5e, the same two checks passed again (Thraximundar and Thunderdays held at 0:00), and Play on Promo, Next, leaving Now Playing for 6 s (the song moved on 14 s) and Stop behaved as before.

Not verified live: Now Playing's Shuffle and repeat (the unit tests cover the queue's order and the player's moves), the Recommended rows' Top Rated and Suggestions (the demo server has no ratings or history to show), a genre's albums, Shuffle on a whole library and Play on the Albums tab, a later page of a queue failing (unit tests only; the demo library has 5 songs), whether a pause straight after Next landed while the song was still loading (the unit tests cover that case), a pause while a queue is fetched at the demo server's own speed (its fetches finish before Now Playing takes a press), the AC3 transcode (no surround music on either server), Now Playing in the system's Control Center, the remote's commands from it and their switching off after Stop, a song opened from Search or a playlist, music stopping when a video starts or the profile changes (unit tests and reasoning only), and a song that fails to play.

Not yet: a Now Playing entry in the sidebar while music plays (Wholphin's drawer has one); Play and Shuffle on audio playlists, which the playlist page (3b) leaves to video for now and could hand to `MusicPlayer.play(.playlist(id))`; filters, view options, the alphabet bar and row memory on music pages; music video and extras rows; Add to Playlist and delete in the song menu; remembering the tab; keeping Suggestions for 12 hours; Wholphin's visualizer; the server's remote-control commands over the WebSocket; and moving music's Now Playing and commands onto 3f's `NowPlayingCenter` (each song's controller holds a queue of one, so Next and Previous would stay with `MusicPlayer`).

#### 5c: photos slideshow, theme music, cinema-mode intros

Not started. Photo libraries open `App/Photos`, which shows the library grid until then.

#### 5d: Seerr behind a build flag

Not started.

#### 5e: Top Shelf, deep links, in-app screensaver

- [x] Top Shelf: Continue Watching and Next Up for the profile the app opens on, picked as Wholphin's Watch Next row (`TvProviderWorker`) picks them: 10 of each, Next Up without the series already in Continue Watching or taken out of Next Up, and with the rewatching and max-days settings, which the app leaves in the App Group. 16:9 art with a progress bar and the title (series and episode for episodes). Selecting an item opens its page; Play plays it from where it was left off. It shows nothing for a locked profile or when nobody is signed in, and changes nothing on the server. tvOS loads it again when the profile changes and when the app goes to the background
- [x] The sign-ins are shared with the Top Shelf through the Keychain access group `<team>.com.revanthv11.anemone.shared`, and settings through the App Group `group.com.revanthv11.anemone`. On the first launch after the update, the Keychain item moves from the app's own group into the shared one, copied before the old one is deleted, so existing sign-ins survive; a build without the entitlement keeps the item where it was
- [x] `anemone://` links, ported from Wholphin's `IntentService`: `item/<id>` opens the item's page on Home, with Back to Home; `play/<id>` also plays it, from where it was left off (Wholphin starts from the beginning) or from `position` in milliseconds; `search?query=<term>` searches. A link may name its profile (`server`, `user`, or Wholphin's `serverId` and `userId`): it switches to that profile when it's saved and unlocked, and is dropped when it's locked or not on this Apple TV. A link that arrives before sign-in waits for it
- [x] In-app screensaver, ported from Wholphin's `AppScreensaver` and `ScreensaverService`, in Settings › Screensaver: off by default, as in Wholphin; once the remote has been left alone for the chosen time (15 minutes by default), the backdrops of random movies and shows rated up to 16 by default, 30 s each, slowly zooming, with the logo or title and the clock. Never while a video plays. It shows over everything, sheets included; the first press only closes it, and focus is back where it was. "Start screensaver" shows it at once. DEBUG builds launched with `-screensaverIdleSeconds <n>` turn it on with an n-second delay
- [x] The Top Shelf extension was built as a TVML-era `tv-app-extension`, whose `_TVExtensionMain` entry point exits at launch on tvOS 27, so the system never got content from it. It's now a plain app extension

Tested live in the simulator against the Jellyfin 12.3 demo server, on a clone signed in before the update: after installing, the clone was still signed in and its Keychain item had moved into the shared group. With Anemone in the top row of the home screen, the Top Shelf showed Continue Watching with Pioneer One S1:E3, Dracula and Sahara, with progress bars, and selecting Dracula there opened Anemone on Dracula's page. `xcrun simctl openurl … anemone://item/c541e7545e58b28cd4d0da7aac89d7e8` (after the system's "Open in Anemone?") opened Caminandes: Llama Drama's page with focus on Play, from Home and from the Movies tab, and Back went to Home. `anemone://play/…` played it, and closing the player showed its page. `anemone://search?query=Llama%20Drama` opened Search with the movie in the results. With `-screensaverIdleSeconds 6` the screensaver started after six seconds with a backdrop, logo and clock, and one press closed it with focus still on the same Home card. Not verified live: Next Up in the Top Shelf (the demo server had no next episode), Play on a Top Shelf item, a link that switches profile or is dropped for a locked one, the screensaver over a sheet and its "Couldn't reach the server" message, keeping it away during playback (covered by reasoning: a presented system player, or Anemone's overlay with its `AVPlayerLayer`, counts as keeping the screen on), and the move on a real Apple TV, where the App Group and Keychain group must be registered first.

Not yet: Wholphin's screensaver dimming and its choice of item types (photos come with 5c); after Back from a page opened by a link, focus lands on a card in view rather than the one focused before; a search link leaves focus on the keyboard rather than the first result; a Top Shelf image (Phase 0's brand assets).

### Phase 6: App Store release

#### 6a: release config: privacy, ATS, export compliance, licenses screen, EULA draft

The release work and its reasons are in `docs/release/`, starting with `checklist.md`.

- [x] Privacy manifests for the app and the Top Shelf extension: no tracking and no data collected, since everything goes only to the user's own server. The app declares UserDefaults (`CA92.1`) and file timestamps (`C617.1`, Nuke's artwork disk cache). The App Privacy answers and a privacy policy draft are in `docs/release/privacy.md` and `privacy-policy.md`
- [x] Export compliance: `ITSAppUsesNonExemptEncryption` is `NO`, since the app only uses the system's HTTPS, the Keychain and SHA-256 for PINs. To look at again if MPVKit brings its own TLS library
- [x] ATS: `NSAllowsArbitraryLoads` in the app, and now in the extension, for the plain-HTTP servers people type in, with the case for App Review in `docs/release/ats.md`. The local network usage string names the servers the user adds
- [x] Settings › About: the version, the GPL, and where the source of each build is tagged; then a page per project Anemone is based on (Wholphin, Swiftfin) and per package, each with its full license text, as Wholphin's `LicenseInfo` lists its libraries. The list is read from `NOTICE.md`, which the app bundles at build time (a link in `App/Settings/About`), so a credit added there shows up without touching the screen; a test checks that the file keeps parsing. `scripts/update-licenses.sh` copies the packages' license texts from Xcode's checkouts and warns about a package NOTICE.md doesn't credit
- [x] A custom GPL EULA draft, following Apple's minimum terms, and an App Review notes template (`docs/release/eula.md`, `app-review-notes.md`)
- [x] `scripts/tag-build.sh` tags the commit each TestFlight build is archived from as `build/<version>-<build>`, the tag Settings › About names, after checking the commit is on GitHub and the build number isn't tagged yet
- [ ] Demo Jellyfin server and reviewer login, with legally free media (the developer's to set up)

Tested live in the simulator: Settings › About showed the version, the GPL, Wholphin, Swiftfin and all eight packages, and focus scrolled it to the last package and back; the GPL's page scrolled a paragraph at a time; Wholphin's page reached its license, and Nuke's showed its MIT text. In the add-server flow, `http://localhost:8196` (the local fixture server, plain HTTP) connected and showed that server's profiles, and the demo server's saved profile then went back to Home. The built app's `Info.plist` has the export compliance and ATS keys, and both bundles carry their privacy manifest. Not verified: a plain-HTTP server on another host (the simulator only reached localhost), an archive's privacy report, and anything in App Store Connect.

Not yet: the app icon, Top Shelf image and screenshots; the EULA's final wording; the App Store Connect record. The release checklist lists them.

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
