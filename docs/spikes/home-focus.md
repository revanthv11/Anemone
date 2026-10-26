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
- Library grids, which can hold thousands of items, need their own check. A `LazyVGrid` won't have the row-memory problem (it's one focus section), but it hasn't been tested.

## Still open

- [ ] Scrolling smoothness on real hardware, especially Apple TV HD (A8, the slowest device that runs tvOS 26). Use Instruments' hitch and animation tools while holding the remote's right arrow on a full row.
- [ ] The same tests on a tvOS 26 simulator. The deployment target is tvOS 26, and only tvOS 27 was tested.
- [x] Real images through Nuke instead of drawn placeholders: the Phase 2a home page, checked in the simulator only.
