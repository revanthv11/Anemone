# Spike: home screen focus

**Question:** can the home screen (rows of posters, like Wholphin's) be built in SwiftUI, or does it need UIKit collection views?

**Answer:** SwiftUI works, with one rule: the outer list of rows must be a plain `VStack`, not a `LazyVStack`. Confirm scrolling speed on Apple TV hardware before committing.

## Setup

- 10 rows × 50 posters of mock data, with posters drawn off the main thread to simulate image decoding.
- A focused-item header above the rows, updated 150 ms after focus settles (Wholphin debounces its backdrop the same way).
- Selecting a poster opens a detail page.
- `UITests/HomeFocusSpikeUITests.swift` drives the Siri Remote through the same script for every variant.
- Run on the tvOS 27 simulator (Apple TV 4K, 3rd generation), Xcode 27.1.

Launch a variant with `-homeSpike <name>`, or pick one on the placeholder screen.

| Name | What it is |
|---|---|
| `swiftui` | `VStack` of rows; each row is a horizontal `ScrollView` + `LazyHStack` with `.focusSection()` and `.defaultFocus(_:_:priority: .userInitiated)` pointing at the row's last-focused item |
| `swiftui-scroll` | Same, but `LazyVStack`, with each row's scroll position stored outside the row via `.scrollPosition(id:)` |
| `swiftui-naive` | Same, but `LazyVStack` and nothing else |
| `uikit` | `UIScrollView` + `UIStackView` holding one horizontal `UICollectionView` per row, each with `remembersLastFocusedIndexPath` (the Apple TV app's pattern), hosted in SwiftUI |

## Results

| Check | `swiftui` | `swiftui-scroll` | `swiftui-naive` | `uikit` |
|---|---|---|---|---|
| Moving along a row (30 presses) | ✅ | ✅ | ✅ | ✅ |
| Row memory, row on screen: up/down returns to the item you left | ✅ | ✅ | ✅ | ✅ |
| Row memory after the row scrolled off screen and back | ✅ | ❌ `r0-i24` | ❌ `r0-i0` | ✅ |
| Focus restored after opening a detail page and pressing Back | ✅ | ✅ | ✅ | ✅ |
| Header follows focus | ✅ | ✅ | ✅ | ✅ |

The expected item for row memory was `r0-i30`.

- **Why the lazy variants fail:** `LazyVStack` throws away rows that scroll off screen. When a row comes back, its horizontal scroll has reset, so the remembered poster doesn't exist yet and `defaultFocus` can't reach it.
  - `swiftui-naive` lands on the first poster.
  - `swiftui-scroll` restores the scroll position, but focus lands on the first visible poster (`r0-i24`), not the remembered one.
- **First visit to a row:** every variant focuses the row's first item (`r1-i0`), not the poster geometrically below. That matches Wholphin.
- **Speed in the simulator:** identical across variants (about 6.7 s for 30 presses, 1.8 s for 8 rows down). Those numbers are mostly XCUITest's own pacing on a fast Mac. They say nothing about Apple TV hardware.

## Recommendation

- Build the home screen in SwiftUI:
  - a `VStack` of rows inside a vertical `ScrollView`;
  - each row a `LazyHStack` with `.focusSection()`;
  - one `.defaultFocus(..., priority: .userInitiated)` per row, fed by a remembered item per row kept above the rows.
- This needs about 145 lines here, against about 185 for UIKit, and no bridging.
- Keeping every row alive costs little: Wholphin home pages have roughly 10–20 rows, and the posters inside each row stay lazy.
- Keep the UIKit variant as the fallback if hardware testing shows dropped frames.
- Library grids, which can hold thousands of items, needed their own check; see the next section.

## Library grid (Phase 2b)

**Question:** does a `LazyVGrid` in a vertical `ScrollView` hold up for a library of thousands of items: pages loading ahead of focus, focus moving cleanly, and Back from a detail page returning to the same card?

**Answer:** yes, as long as the grid has no `.focusSection()` and no `.defaultFocus`. Either one makes every focus move take seconds when accessibility is on (VoiceOver, or XCUITest). Without them, Wholphin's "return to the last card" is done by hand.

### Setup

- `-libraryGridSpike <count>` opens the real `LibraryGrid` on a synthetic library, inside the same `.sidebarAdaptable` `TabView` as the app. Items are spread evenly from A to Z, and each page of 100 arrives 400 ms after it's asked for.
- Six poster columns, titles on, alphabet bar on; cards have no artwork.
- `UITests/LibraryGridSpikeUITests.swift` runs the checks below on 5,000 items. The 20,000-item numbers come from Instruments (Time Profiler) with arrow keys sent to the simulator, because XCUITest turns accessibility on.
- tvOS 27 simulator (Apple TV 4K, 3rd generation), Xcode 27.1.

### Results

| Check (5,000 items) | Result |
|---|---|
| 20 presses down, crossing the first page boundary | ✅ lands on `125`, loaded |
| 100 more presses down | ✅ lands on `725` |
| Focus landing on a card whose page hadn't arrived | ✅ never, at XCUITest's pace (about 4.5 presses a second) |
| Right from the last column enters the alphabet bar on the current letter | ✅ `D` |
| Jump to M: scrolls, loads the page, focuses the first M item | ✅ `2308`, settled in 0.8 s |
| Back from a detail page | ✅ same card |
| Left into the sidebar, then right | ✅ same card (by hand, best effort; see below) |
| Up into the header, then down | ✅ same card (by hand, best effort) |
| Left from the alphabet bar | ✅ same card (by hand) |
| Back from deep in the grid goes to the top; Back again opens the sidebar | ✅ |

Main-thread time per focus move, measured with Time Profiler in the simulator:

| Grid | Accessibility off | Accessibility on |
|---|---|---|
| 5,000 items, `.focusSection()` and `.defaultFocus` on the grid | under 10 ms | about 2.7 s; XCUITest dropped 4 of 5 presses |
| 5,000 items, neither | not measured | about 90 ms |
| 20,000 items, neither | under 10 ms of focus work, about 60 ms with layout | about 1.3 s |

Either modifier alone was still slow: XCUITest took about 7 s for 5 presses down with one of them, 15 s with both, and 1.1 s with neither.

- **The focus modifiers.** With accessibility on, UIKit's focus engine snapshots a focus region for every item in a lazy container and evaluates occlusion between them (`_UIFocusRegionEvaluator`), which grows with the square of the item count. A focus section or default-focus scope on the grid makes every move pay for the whole grid. Without them the cost is much lower, but it still grows with the library: 20,000 items with VoiceOver on would take over a second per move.
- **Returning to the last card by hand.** Without a focus section, coming back from the sidebar, header or alphabet bar lands on the nearest card. Wholphin goes back to the last one. When focus next lands on a card after leaving, the grid moves it to the remembered card if that's on screen. The correction takes 20–30 ms in the simulator.
  - Leaving for the alphabet bar is certain: the grid owns the bar's focus state.
  - Leaving for the header or the sidebar is inferred from `onMoveCommand` (up from the first row, left from the first column) followed by focus going to `nil`. It's best effort: the move command doesn't always arrive before the focus change, and a miss leaves focus on the nearest card, the tvOS default.
  - "Focus went to `nil`" alone can't tell: focus passes through `nil` for 80–350 ms each time it moves to a row that wasn't on screen.
- **Jumping.** `ScrollViewReader.scrollTo(id:anchor:)` also shifted the grid sideways (20 pt with `.top`, 80 pt with `.topLeading`) until the next move. The jump scrolls with `ScrollPosition.scrollTo(y:)` instead, from the measured header and card heights.
- **Speed.** The grid itself is cheap: with accessibility off, a move costs under 10 ms of focus work at 20,000 items, and the rest is layout. Every move is still a SwiftUI layout pass over the visible cards, so Apple TV HD needs checking.

### Recommendation

- Build library grids as a `LazyVGrid` with no focus modifiers on the grid, as `App/Library/LibraryGrid.swift` does.
- Fall back to a `UICollectionView` (Swiftfin's library grids use one, through `CollectionVGrid`) if VoiceOver or hardware testing shows it's needed. A collection view only gives the focus engine its visible cells, and `remembersLastFocusedIndexPath` replaces the by-hand return.

## Still open

- [ ] Scrolling smoothness on real hardware, especially Apple TV HD (A8, the slowest device that runs tvOS 26). Use Instruments' hitch and animation tools while holding the remote's right arrow on a full row.
- [ ] The same tests on a tvOS 26 simulator. The deployment target is tvOS 26, and only tvOS 27 was tested.
- [x] Real images through Nuke instead of drawn placeholders: the Phase 2a home page, checked in the simulator only.
- [ ] Library grid on hardware: scrolling a few thousand posters with artwork on Apple TV HD, and VoiceOver on a large library.
