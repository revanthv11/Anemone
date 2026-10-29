# Wholphin upstream changes: cecfdae to 5f2f9a8

A review of what [Wholphin](https://github.com/damontecres/Wholphin) changed after Anemone's parity baseline, mapped to Anemone's phases. It is the "Tracking upstream" step from [PLAN.md](../PLAN.md), the second one; the first is [wholphin-52c26bc-to-cecfdae.md](wholphin-52c26bc-to-cecfdae.md). Unlike the first, this review and its ports landed together, in one PR.

| | |
|---|---|
| Range | `cecfdae..5f2f9a8` on `damontecres/Wholphin` `main` (full tip: `5f2f9a8106c73700c4d0922cb07c830d692b38e8`) |
| Baseline | `cecfdae` "Fix unit tests after merge", 2026-10-26 |
| Tip | `5f2f9a8` "Fixes to `v1.0.9` (#2072)", 2026-10-28 |
| Dates | 2026-10-27 to 2026-10-28 (authors' local dates) |
| Size | 4 commits, a straight line with no merges, 2 authors; 33 files changed, +1407 / -93 (507 of the added lines are test files) |
| Reviewed | 2026-10-28, by reading every patch in full |

## Status

The baseline in `NOTICE.md` and PLAN.md is now `5f2f9a8`. Of the four commits:

| Sha | Outcome |
|---|---|
| `811eaed` | Ported (3f): a Max bitrate menu in the player, `MaxBitrateMenu`. |
| `5f2f9a8` | Ported in part (2d, 2h): photo libraries' favourites and search include videos. The rest doesn't apply (below). |
| `6d02908` | Ported in spirit: the overlay's debug panel shows the video's range, the display mode asked for, the decoders and whether the Apple TV outputs HDR, since tvOS has none of the tables Wholphin added. |
| `2f7804f` | Skipped: an ExoPlayer bitstream filter, under "Not ported". Its device-profile half is noted for the Dolby Vision spike. |

## In short

- One feature is worth porting and was: `811eaed` lets the user change the max bitrate during playback. Anemone had the setting (3f) but no way to change it without leaving the player.
- One bug fix applies: `5f2f9a8` makes a photo library's item kinds include videos, so a photo library's videos show on the Favorites page and in Search. Anemone had already fixed the home-videos half of it (the `baseItemKinds` bug listed under "Fix while porting"); the photos half was copied from Wholphin as it was.
- `6d02908` adds HDR tables to Wholphin's debug page, which Anemone doesn't have; the closest thing, the player overlay's debug panel, gained the rows tvOS can answer.
- `2f7804f` converts Dolby Vision profile 7 to 8.1 inside ExoPlayer. It can't be done in AVPlayer, and MPV doesn't play Dolby Vision in Anemone.
- There are no translation, CI or dependency commits in the range (`2f7804f` adds a `libs.versions.toml` entry for its own test dependency only).
- The "Fix while porting" references were checked again at `5f2f9a8`; one of them, the Search `baseItemKinds` bug, is fixed upstream by `5f2f9a8`. The others still hold, two at new line numbers (below).

## Commits at a glance

| Sha | PR | Area | Phase | Decision |
|---|---|---|---|---|
| `6d02908` | #2140 | Debug page: display modes and detected HDR support | 3e (debug panel) | Port the rows tvOS can answer |
| `2f7804f` | #2017 | Dolby Vision profile 7 converted to 8.1 in ExoPlayer | none ("ExoPlayer-specific hacks") | Skip; note for the DV spike |
| `811eaed` | #2097 | Max bitrate changed during playback | 3f | Port |
| `5f2f9a8` | #2072 | Fixes to v1.0.9: favourites Videos tab, Random for photos, drawer marquee, studios View More crash | 2d, 2h; the rest none | Port the item-kind fix; the rest doesn't apply |

## Playback

### `811eaed` Change max bitrate during playback (#2097), 3f, ported

**What changed**

- `PlaybackState` gains `maxBitrate`, set in `init()` from the `maxBitrate` preference (or `DEFAULT_BITRATE`), and `changeStreams` takes a `maxBitrate` parameter that defaults to it and writes it back to the state. So a pick lasts the playback session: Next Up's episodes keep it, and backing out and playing again starts from the setting.
- `changeStreams`' direct-play shortcut (switching tracks in the player without asking the server) now also requires the bitrate to be unchanged, so a bitrate change always goes to PlaybackInfo.
- `changeMaxBitrate(newMaxBitrate)` calls `changeStreams` for the current item and version, with its audio and subtitle indices and the player's position, and `enableDirectPlay = true`.
- The settings dialog (gear icon) gets a "Max bitrate" entry showing the current value (`formatMaxBitrate`, moved out of `AppPreference` into `Formatting.kt`) and a `BITRATE` page listing `AppPreference.bitrateValues`, now public; picking one sends `PlaybackAction.ChangeBitrate`.
- `BottomDialog` scrolls its list to the current choice before focusing it (`rememberLazyListState` plus a `BringIntoViewRequester` per row), since the bitrate list is longer than the dialog.
- No new strings: `max_bitrate` already exists.

**How Anemone has it**

- `MaxBitrateMenu`, a `PlaybackFeature`, shows a "Max bitrate" menu with `AVPlayerProfile.bitrateChoices` (plus a value set by launch argument, so one option is always marked), the Streaming setting marked until a pick. A pick stores the choice in the feature, which lives as long as the controller, puts it in every later `StreamRequest` through `prepare(_:)`, and calls `controller.reload()`, which ends the play session and asks for the entry again from the same position. The queue's next entries keep it; a new player starts from the setting again, as in Wholphin.
- `StreamRequest` now carries `maxBitrate`, the Streaming setting by default, in place of the controller reading the setting itself when it asked the server. The reload path already re-asks PlaybackInfo, which is Wholphin's "no direct-play shortcut when the bitrate changed".
- The menu sits with the other transport-bar menus, in Anemone's overlay and in the system player's bar; Wholphin's lives in its settings dialog. A live stream gets no menu: a reload of a live stream reopens it, which `TrackSelection` avoids too, and Wholphin's change doesn't claim to work for Live TV.
- `Int.bitrateText` (Wholphin's `formatMaxBitrate`) moved from the app into `AnemonePlayback`, as Wholphin moved its formatter into `Formatting.kt`, so the feature and the settings page share it.
- The scroll-to-current fix applied after all: the overlay's menu panel was a plain stack, so the 23 limits ran off the screen and focus couldn't reach the top ones. It's now a scroll view sized to its content, up to about eight rows, which keeps the focused option in view, as `BottomDialog` does with its `BringIntoViewRequester`.

**Tests.** `MaxBitrateMenuTests`: the menu marks the setting's limit and a pick asks the server again under the new one from the same position; picking the marked limit asks for nothing; the next entry keeps the pick and another player starts from the setting; a live stream has no menu; the bitrate text.

**Tested live** in the simulator against the review server, as PLAN.md 3f records: the button reads the current limit, the list opens on it, picking 500 kbps reloads as a transcode in a new play session from the same position, and the button then reads 500 kbps. Not verified: the system player's rendering of the 23-item menu, which XCUITest can't read.

## Browsing

### `5f2f9a8` Fixes to `v1.0.9` (#2072), ported in part

Four fixes and some focus work in one commit. Each in turn:

- **Favourites' Videos tab (#2070).** `CollectionType.baseItemKinds` for `HOMEVIDEOS` was three `listOf` lines of which only the last, photo albums, was returned, and `PHOTOS` had no videos. Both are now `VIDEO, PHOTO, PHOTO_ALBUM`. **Ported:** the home-videos half was Anemone's already (the bug is listed under "Fix while porting", 2d); the photos half is new, so `Library.Kind.itemKinds` (favourites) and `Library.searchKinds` now give `.photos` the same kinds as `.homeVideos`. Favourite photo albums stay out: `MediaItem.Kind` has no photo album (they're folders), and the Favorites page has no row for them.
- **Random for photos (#2069).** `onClickRandom` navigated to `random.destination()`, which for a `PHOTO` isn't a slideshow. A new `goToRandom` picks an index, and for a photo opens `Destination.Slideshow` at that index with the grid's filter and sort; `Slideshow.parentId` becomes nullable for the favourites grid, and `SlideshowViewModel` reads and saves the album's image filter only with a parent. **Doesn't apply:** Anemone's photo pages (5c) have their own Random, which opens the viewer at the index picked (`PhotoFolderPage.openRandom`); its Favorites page has no Random button and no slideshow from it.
- **Long drawer names (#2135).** `NavDrawer`'s profile, icon and library items get `enableMarquee(focused)`. **Doesn't apply:** Anemone's sidebar is tvOS's own (`.sidebarAdaptable` tab view), which truncates long names itself and offers no marquee.
- **Studios View More crash.** `HomeDataService` built a studios row's `Success` without `rowType`, which View More then read. **Doesn't apply:** Anemone's Home rows have no View More yet (2f's "Not yet" list), and its row data carries the row's config throughout.
- **Server picker focus.** `SwitchServerContent` keeps a `FocusRequester` per server card plus one for Add Server, and requests focus only once loading succeeds (not while pending); the add-server dialog focuses its Enter Address button, and the first discovered server takes focus when it appears. **Doesn't apply:** Anemone's server screens (`App/Setup/ServerViews.swift`) leave initial focus to SwiftUI, and have no discovered servers yet (Phase 1, waiting on the multicast entitlement). Worth a look when discovery lands: a discovered server that appears should take focus, and nothing should ask for focus while the list is loading.

## Debugging

### `6d02908` Add detected HDR info to debug page (#2140), ported in spirit

**What changed.** `DebugViewModel` keeps the `Display` rather than its modes, asks `MediaCodecCapabilitiesTest` eight HDR questions (HEVC HDR10 and HDR10+, Dolby Vision single layer, profile 7 EL and profile 8, AV1 HDR10, HDR10+ and Dolby Vision), and the page draws two tables with Compose's new `Grid`: display modes (id, size, fps, HDR types per mode, alternative refresh rates) and detected HDR support. A test asserts the eight functions exist.

**How Anemone has it.** Anemone has no Settings debug page; the player overlay's debug panel (3e) is the counterpart. tvOS lists neither display modes nor the display's HDR formats, so the panel gained what it can answer: the video as the server read it (codec, size, frame rate, range type), the display mode `DisplayCriteria` asks for (frame rate and dynamic range), the hardware decoders VideoToolbox reports (`VideoDecoders.current`: HEVC, AV1, Dolby Vision) and `AVPlayer.eligibleForHDRPlayback`, which is the one system answer to "will this output HDR".

**Tested live** in the simulator against the review server, on Sintel: "Video: h264 2048×872 24 fps SDR", "Display asked: 24 fps, SDR", "Decodes: none" (the simulator has no hardware decoders) and "HDR output: no". Not verified: an HDR title, which the review server doesn't have.

## Platform

### `2f7804f` Convert Dolby Vision profile 7 to 8.1 on devices without a profile 7 decoder (#2017), skipped

**What changed.** An experimental setting, `convertDolbyVisionProfile7` (proto field 6, off by default). When it's on and the device decodes profile 8 but not profile 7, `DolbyVisionProfile7Filter` rewrites each access unit on its way to the decoder (RPU NAL 62 rewritten to its 8.1 form, enhancement-layer NAL 63 dropped, via a small native rewriter), `DolbyVisionProfile7ExtractorsFactory` rewrites the track's codec string from `dvhe.07`/`dvh1.07` to `.08` so media3 picks a profile 8 decoder, and `DeviceProfileService` adds profile 7's range types to `forceEnabledHdr`, so the server direct plays such a file rather than transcoding it. Three test files cover the filter, the extractor wrapper and the codec strings.

**Why it doesn't apply.** It's a bitstream filter in ExoPlayer's renderer path, the same family as the HDR10+ SEI masking it sits beside, which PLAN.md lists under "Not ported". AVPlayer gives no access to the bitstream, and Anemone's MPV engine hands HDR and Dolby Vision to AVPlayer. Apple TV 4K's own decoder takes profiles 5 and 8 and shows a profile 7 file's HDR10 base layer, which is the outcome Wholphin's filter exists to improve on.

**Note for the Dolby Vision spike (Phase 0).** Anemone's `AVPlayerProfile.videoRanges` already lets the server direct play `DOVIWithEL` and `DOVIWithELHDR10Plus` wherever HEVC decodes, counting on the base layer showing as HDR10. The spike should confirm on hardware that a profile 7 MP4 plays that way rather than failing, which would call for taking those two range types out so the server transcodes them.

## Commits summarised in one line each

- Translations (Weblate): 0 commits.
- CI and dependency bumps: 0 commits.

## The "Fix while porting" list at `5f2f9a8`

- `PlaybackViewModel.kt:499-503` (per-series subtitle choices loaded with `SeriesTrackChoiceType.AUDIO`) is now at lines 505-510; `811eaed` added lines above it. Still there.
- `StreamChoiceService.kt:143` (the mirror image, `SUBTITLE`): unchanged.
- `MusicService.kt:305-306` (the missing `&&` in the AC3 check): unchanged.
- `ThemeSongPlayer.kt:88` (`75f`): unchanged.
- `PlaybackPage.kt:292-296` (`TODO()` for the video filter and playlist dialogs): unchanged, still lines 292 and 296.
- `DvrSchedule.kt:93` (`programInfo!!`): unchanged.
- `PlaylistCreator.createFromCollection` (`recursive = true`): unchanged.
- **Search: `CollectionType.HOMEVIDEOS.baseItemKinds` returns only `PHOTO_ALBUM` (2d): fixed upstream by `5f2f9a8`.** PLAN.md's entry says so now.

## Fixes to code Anemone already ported

| Anemone area | What upstream touched in the range | Result |
|---|---|---|
| 2d Search, 2h Favorites | `CollectionFolderGrid.kt`'s `baseItemKinds` | Ported (photos include videos) |
| 2e Home rows | `HomeDataService.kt` (studios row `rowType`) | Nothing to fix: no View More yet, and the row keeps its config |
| 2f library grid | `CollectionFolderView.kt` Random | Nothing to fix: Anemone's Random for photos is its own |
| 3e debug panel | `DebugPage.kt` | Rows added |
| 3f playback settings | `PlaybackViewModel.kt`, `PlaybackDialog.kt`, `PlaybackControls.kt` | Ported as `MaxBitrateMenu` |
| 1 servers | `SwitchServerContent.kt` focus | Nothing to fix now; a note for server discovery |
| 5c photos | `SlideshowViewModel.kt` nullable parent | Nothing to fix: `SlideshowQuery` always has a folder |

## Using this file

- The next range starts at `5f2f9a8`: in a Wholphin clone, `git fetch origin && git log --stat 5f2f9a8..origin/main`, read every patch, write `wholphin-5f2f9a8-to-<tip>.md`, port or skip each commit, then move the baseline in `NOTICE.md` and PLAN.md's first paragraph.
- When server discovery lands (Phase 1), read the `SwitchServerContent.kt` hunk of `5f2f9a8` for its focus rules.
- When the Dolby Vision spike runs, test a profile 7 file and read `2f7804f`'s description for what Wholphin saw on devices without a profile 7 decoder.
