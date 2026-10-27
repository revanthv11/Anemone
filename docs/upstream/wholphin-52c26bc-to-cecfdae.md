# Wholphin upstream changes: 52c26bc to cecfdae

A review of what [Wholphin](https://github.com/damontecres/Wholphin) changed after Anemone's parity baseline, mapped to Anemone's roadmap streams. It is the "Tracking upstream" step from [PLAN.md](../PLAN.md). Nothing here changes code. It is kept as it was written, before the ports; the baseline in `NOTICE.md` has since moved (see Status).

| | |
|---|---|
| Range | `52c26bc..cecfdae` on `damontecres/Wholphin` `main` (full tip: `cecfdaeba94560ed547288fe2cba0324ec9a9b24`) |
| Baseline | `52c26bc` "Update playlist details to match library grid (#2113)", 2026-10-25 |
| Tip | `cecfdae` "Fix unit tests after merge", 2026-10-26 |
| Dates | All five commits are from 2026-10-26 (authors' local dates) |
| Size | 5 commits, a straight line with no merges, 4 authors; 19 files changed, +797 / -162 (324 of the added lines are new test files) |
| Reviewed | 2026-10-26, by reading every patch in full |

## Status

The baseline in `NOTICE.md` and PLAN.md is now `cecfdae`. Of the five commits:

| Sha | Outcome |
|---|---|
| `f66746c` | Ported by S1 (PR #29, Phase 5d): the plugin's Seerr settings, signed in to first and kept in memory only. The three quirks listed under it were not copied. |
| `90a2d6d` | Ported by M1 (PR #24, Phase 5b): album cards show the album artist and year. |
| `de67bcc` | Skipped: it only changes the VLC external player, and external players are under "Not ported". |
| `962a14d` | Skipped: it adds a Fire OS permission for the Android MediaSession, which tvOS has no counterpart for. |
| `cecfdae` | Skipped: it only fixes the test added in `de67bcc`. |

The sections below are the review as written.

## In short

- One change is worth porting: `f66746c` lets the Wholphin server plugin hand the client a Seerr URL and login. It belongs to stream **S1** (Seerr), and it shares a plugin client with **H1** (home rows). It also has three quirks that should not be copied (listed under it).
- One small music change is worth porting: `90a2d6d` shows the album artist on album cards. It belongs to **M1**.
- Three commits are skipped: `962a14d` (a Fire OS permission), `de67bcc` (the VLC external player) and `cecfdae` (a test fix).
- There are no translation, CI or dependency commits in the range.
- **No commit fixes code that Anemone ported in Phases 1 to 3a.** The last section explains how that was checked.
- Nothing in the range blocks moving the baseline to `cecfdae`. When it moves is the orchestrator's call; the two port items above are the only open ones.

## Commits at a glance

| Sha | PR | Area | Stream | Decision |
|---|---|---|---|---|
| `f66746c` | #2134 | Discover: Seerr set up from the server plugin | S1 (with H1, Z1) | Port, in S1 |
| `90a2d6d` | #2117 | Music: album artist on album cards | M1 (Phase 2b grid is superseded) | Port, in M1 |
| `de67bcc` | #2050 | VLC external player starts from the beginning | none (external players are "Not ported") | Skip |
| `962a14d` | #2076 | Fire OS voice-command permission | none (a note for P4) | Skip |
| `cecfdae` | none | Fix a test added in `de67bcc` | none | Skip |

## Discover and the server plugin

### `f66746c` Auto-configure Discover from Wholphin server plugin (#2134), stream S1, port

**What changed**

- **New plugin endpoint.** The client now reads `GET {server}/wholphin/seerrsettings` from the companion plugin ([jellyfin-plugin-wholphin](https://github.com/damontecres/jellyfin-plugin-wholphin), its PR #3, merged 2026-10-12).
  - The response is `SeerrPluginSettings { version = 1, serverUrl?, login? }`.
  - `login` is polymorphic on a `type` field: `ApiKey { apiKey }`, `Local { local: { username, password } }`, or `None`.
  - The plugin README documents only `ApiKey` and `Local`. It says that when `login` is omitted, only the URL is pushed and the user supplies authentication.
  - A 404 means the plugin isn't installed or has nothing configured, and the call returns null.
- **Plugin client refactor.** `ServerPluginApi` gets a generic `executeRequest<T>(path)`. `fetchHomePageSettings` is rewritten on top of it, with the same behaviour.
- **In-memory connection.** `SeerrServerRepository.usePluginProvidedServer(settings)` builds a `SeerrServer(id = -1)` and a `SeerrUser` with no password and no credential, then logs in. An API key goes through `seerrApi.update(url, key)`. A local login goes through `seerrLogin(LOCAL, username, password)`.
  - Nothing is written to the local database, so a change in the plugin shows up on the next user switch or app start. This is the stated reason for replacing the earlier PR #1418, which inserted a database row that then took precedence over the plugin.
  - The connection state becomes `SeerrState(connection, pluginProvided)`.
- **Load order.** `UserSwitchListener` checks that the plugin is installed first. Home settings and Seerr then load in two parallel jobs. Seerr tries the plugin first, and falls back to the user's saved Seerr account when the plugin has nothing or its login fails.
- **Settings UI.**
  - The Seerr dialogs move out of `PreferencesContent` into `SeerrDialog`.
  - When the account came from the plugin, the Remove dialog becomes read-only ("Managed by server"), and the Error dialog's action becomes Retry, which re-fetches the plugin settings.
  - The Add dialog waits for the plugin fetch, then pre-fills the URL and focuses the first empty field.
  - `ConfirmDialog` takes custom button labels.
- **Strings.** Two new English strings: `managed_by_server` ("Managed by server") and `error` ("Error").

**Why it matters for Anemone**

- It is the larger of the two port items. It is also the one part of S1 that needs no Seerr instance to test: the decode, the precedence rules and the failure paths can all run against `MockServer`.
- `ServerPluginApi` at `cecfdae` is the version H1 should port for its `GET /wholphin/public` and `/wholphin/homesettings` calls. The generic request helper is already there, and the home-settings behaviour is unchanged.

**Notes for whoever ports it**

1. **Share one plugin client between H1 and S1.** `AnemoneSeerr` depends only on `AnemoneCore` (`Packages/AnemoneKit/Package.swift`), so the authenticated request has to live in `AnemoneJellyfin`.
   - A suggestion: whichever stream merges first creates `AnemoneJellyfin/ServerPlugin.swift` (the generic GET, the 404 means nil rule, and the installed check). The other adds its endpoint as an extension in its own file.
   - The `SeerrPluginSettings` Codable types can live in `AnemoneCore` so that `AnemoneSeerr` can use them.
2. **Keep plugin-provided credentials in memory only, never in the Keychain, UserDefaults or logs.** This matches Wholphin's design, and there is nothing to store for such an account. It fits the "Seerr password in plaintext" item under "Fix while porting".
3. **Confirm the scope with the user.** S1's brief says Seerr credentials are typed by the user only. Plugin auto-login is different: the app fetches the login from the user's own Jellyfin server and nobody types it.
   - The plugin PR lists `GET /wholphin/seerrsettings` as an authenticated endpoint, not an admin-only one, so every signed-in user's client receives the shared login. It also adds a README warning that the password is stored in clear text on the server.
   - The orchestrator should confirm that auto-login is in S1's scope. The suggestion is yes, with mock tests only.
4. **Decode tolerantly.** The plugin PR's description mentions a third login mode (`Jellyfin`, with a "use current user" option) that Wholphin's sealed `SeerrPluginLogin` doesn't model, and kotlinx.serialization throws on an unknown subclass. Treat an unknown `type` as "URL only".
5. **Don't copy these three quirks** (from reading the code at `cecfdae`; they were not run, and upstream may fix them in a later commit):
   - In `UserSwitchListener` the `fetchSeerrSettings()` call isn't wrapped in a try/catch. A 500 or a malformed body ends the coroutine, so the fallback to the user's saved account never runs. Make every plugin failure fall through to the saved account.
   - When the plugin login fails, the state is set to Error with `pluginProvided = true`. If the saved account then logs in, `set(...)` keeps `pluginProvided = true`, so the user's own account would show as "Managed by server" and could not be removed. Reset the flag when a saved account takes over.
   - In `SwitchSeerrViewModel` the add dialog's `loading` state starts as Pending and is set to Success only inside `if (serverPluginInstalled)`. On a server without the plugin it never leaves Pending, and `SeerrDialog` shows only the loading page. That contradicts the PR's "nothing changes" claim. Anemone's add flow must not wait on the plugin check.
6. **Version note.** The plugin README requires Jellyfin 12.1 or newer. Anemone requires 12.0 or newer, so the plugin must stay optional, as it is in Wholphin.
7. **Z1.** If S1 reuses the strings "Managed by server" and "Error", the localization import will find them by their English text. No extra work is needed.

## Music

### `90a2d6d` Show album artist under album name on album cards (#2117), stream M1, port

**What changed**

- `BaseItem.subtitle` for a `MUSIC_ALBUM` is now the album artist, falling back to the joined track artists, then the production year, joined with " - " and with blank parts dropped. Before this, albums fell into the default case and showed only the year.
- In the list layout (`ListItemAlbum` in `CollectionFolderList.kt`) the album artist is already shown above the title, so the supporting line now shows only the year, instead of repeating the artist.
- A new `BaseItemSubtitleTest` covers four cases:
  - album artist plus year gives "Album Artist - 2021";
  - with no album artist, artists "A, B" plus the year give "A, B - 2021";
  - an album with no year gives just the artist;
  - an album with no artist gives just the year, and one with neither gives null.

**Why it matters for Anemone**

- Two albums with the same title by different artists look identical without the artist, so this matters in a music library.
- Wholphin's library grid (`CollectionFolderView.kt`) requests `SlimItemFields`, which contains no artist field, so the server sends `AlbumArtist` and `Artists` by default.
- Anemone's Phase 2b music grid today shows `item.subtitle ?? year` (`App/Library/LibraryGrid.swift`), and `MediaItem` carries no artist fields. S0, per its brief, routes music libraries to `App/Music/MusicLibraryView.swift`, which M1 fills in. M1's cards replace that grid, so the Phase 2b code needs no separate change.

**Port.** M1 should add the artist fields to its own album model, and a small pure function for the subtitle with these four test cases ported, in `AnemoneJellyfin/Music.swift`. It should also use the "year only under the artist" rule in any list layout (L1's list layout for music, if it reaches albums).

## Playback and platform

### `de67bcc` Fix: VLC doesn't restart playback from the beginning as expected (#2050), no stream, skip

- **What changed.** In `PlayExternalPage.kt`, the intent sent to the VLC Android app now carries `from_start = (positionMs == 0)`, because a zero position alone doesn't override VLC's own saved resume point. A new Robolectric test file, `PlayExternalViewModelTest`, makes up about 270 of the lines in this commit.
- **Why it doesn't apply.** Wholphin's external-player intents are an Android feature, and PLAN.md lists "External-player intents" under "Not ported". tvOS has no equivalent.
- **Related.** A reminder for P1 and P4: any "Restart" action must start at position 0 and not fall back to a saved resume point. Anemone's Restart already does this from 3a.

### `962a14d` Add Fire OS voice command permission for MediaSession (#2076), no stream, skip

- **What changed.** Only Android manifests change. The `main` manifest requests the Amazon permission `com.amazon.permission.media.session.voicecommandcontrol`, the `appstore` flavor removes it, and a new `firetv` manifest copies the existing "remove `REQUEST_INSTALL_PACKAGES`" rule (the `firetv` flavor already exists at the baseline).
- **Why it doesn't apply.** It is a Fire TV and Alexa permission for the Android MediaSession, with no tvOS counterpart.
- **Note for P4.** Siri voice commands on tvOS reach an app through `MPRemoteCommandCenter`. When P4 builds the Now Playing path, registering the skip, seek and play/pause commands is what makes voice control work. This is a suggestion, not something this commit requires.

## Tests only

### `cecfdae` Fix unit tests after merge, no stream, skip

- It edits only `PlayExternalViewModelTest` (+7 / -2). The test used older `StreamChoiceService` signatures.
  - `chooseSubtitleStream` now returns `StreamChoiceResult(stream, StreamChoiceReason.Unknown)`.
  - The mocks call `getSeriesTrackChoices(item, SeriesTrackChoiceType.SUBTITLE)` in place of the removed `getPlaybackLanguageChoice`.
- Both of those signatures are already in the baseline source (`StreamChoiceService.kt`, `ItemPlaybackRepository.kt`), so P3 should port the baseline versions. This commit adds nothing new.

## Commits summarised in one line each

- Translations (Weblate): 0 commits.
- CI and dependency bumps (Gradle, GitHub Actions, library updates): 0 commits. The most recent ones, `0aab839`, `f2a76a9` and `766269d`, are before the baseline.

## The "Fix while porting" list still holds

None of the five commits touch the files behind the four upstream bugs listed in [PLAN.md](../PLAN.md), so each reference below was re-read at `cecfdae` and still points at the same code:

- `PlaybackViewModel.kt:499-503` loads the per-series subtitle choices with `SeriesTrackChoiceType.AUDIO`.
- `StreamChoiceService.kt:143` is the mirror image: the audio choice loads series choices with `SUBTITLE`. P3 should fix both.
- `MusicService.kt:305-306`: the AC3 check is missing `&&`, so any non-AC3 track takes the AC3 transcode path.
- `ThemeSongPlayer.kt:88`: the `HIGHEST` volume is `75f`.
- `PlaybackPage.kt:292-296`: `ShowPlaylist` and `ShowVideoFilterDialog` call `TODO()`.

## Fixes to code Anemone already ported (Phases 1 to 3a)

**None.** No commit in `52c26bc..cecfdae` fixes a bug in code Anemone ported in Phases 1 to 3a, so there is nothing for the orchestrator to schedule from this range.

How that was checked:

| Anemone area | What upstream touched in the range | Result |
|---|---|---|
| Phase 1: servers, sign-in, profiles, PIN | `UserSwitchListener.kt` changed only in how it loads home settings and Seerr after a user switch. `ServerRepository`, Quick Connect and PIN code are untouched. | Nothing to fix |
| 2a and 2b: sidebar, Home, library grids | `BaseItem.subtitle` (albums only) and `CollectionFolderList.kt` (the album list item). | Not a fix; goes to M1 (see `90a2d6d` above) |
| 2c: item pages | Nothing touched. | Nothing to fix |
| 3a: first playback | `PlayExternalPage.kt` only (external players, not ported). Nothing in `PlaybackViewModel`, `StreamChoiceService` or the reporting code. | Nothing to fix |

One item came close and is deliberately not on the list. Anemone's music grid (`App/Library/LibraryGrid.swift:212`, `MediaItem.swift`) would show the new album subtitle if it were ported there, but M1 replaces that grid, so porting it in place would be thrown away. If M1 is delayed for a long time, a stopgap would need an artist field on `MediaItem` (`Packages/AnemoneKit/Sources/AnemoneJellyfin/MediaItem.swift`) and the grid card line in `LibraryGrid.swift`.

## Using this file

- When S1 and M1 start, hand them the `f66746c` and `90a2d6d` sections as part of their briefs. Hand the plugin-client note to H1 as well.
- After those two are ported, or skipped on purpose, the baseline in `NOTICE.md` and the sha in PLAN.md's first paragraph can move to `cecfdae`. The `NOTICE.md` sentence "Upstream changes after this commit have not been reviewed for porting" should then point at the next range.
- To produce the next file, run the same range from the new baseline in a Wholphin clone: `git fetch origin && git log --stat <baseline>..origin/main`. Read the patches rather than only the titles; here the titles alone hid that `f66746c` is mostly a settings-dialog rewrite, and that `de67bcc` is mostly a test file.
