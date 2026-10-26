import AnemoneJellyfin
import SwiftUI

/// Phase 2b spike: the library grid on a synthetic library of `count` items, inside the same
/// sidebar as the real app. Pages arrive after a delay like a server's. Launch with
/// `-libraryGridSpike <count>`; findings are in docs/spikes/home-focus.md.
struct LibraryGridSpike: View {
    let count: Int

    @State private var pager: LibraryPager
    @State private var started = false
    @State private var path = NavigationPath()
    @State private var focusedIndex = 0
    /// How often focus landed on a card whose page hadn't arrived: pages should load ahead of focus.
    @State private var placeholderFocusCount = 0

    init(count: Int) {
        self.count = count
        _pager = State(initialValue: LibraryPager { startIndex, limit, includeTotalCount in
            try await Task.sleep(for: .milliseconds(400))
            let items = (startIndex ..< min(startIndex + limit, count)).map { SpikeLibrary.item($0, of: count) }
            return LibraryPage(items: items, totalCount: includeTotalCount ? count : nil)
        })
    }

    var body: some View {
        TabView {
            Tab("Library", systemImage: "film") {
                NavigationStack(path: $path) {
                    grid
                        .navigationDestination(for: MediaItem.self) { item in
                            Text(item.name)
                                .font(.largeTitle.bold())
                                .accessibilityIdentifier("detail.title")
                                .focusable()
                        }
                }
            }
            Tab("Other", systemImage: "gearshape") {
                Text("Another tab")
                    .focusable()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .task {
            try? await pager.start()
            started = true
        }
    }

    @ViewBuilder
    private var grid: some View {
        if started {
            LibraryGrid(
                pager: pager,
                options: GridViewOptions(shape: .poster, columns: 6),
                showsJumpBar: true,
                position: { letter in SpikeLibrary.position(of: letter, count: count) },
                imageURL: { _, _, _ in nil },
                onSelect: { path.append($0) },
                onFocus: { index in
                    focusedIndex = index
                    if pager.item(at: index) == nil {
                        placeholderFocusCount += 1
                    }
                },
            ) {
                HStack(spacing: 40) {
                    Text("Spike library")
                        .font(.title2.bold())
                    Spacer()
                    Button("Sort") {}
                    Button("Filter") {}
                }
            }
            .overlay(alignment: .topLeading) {
                // Pinned, so it stays readable in screenshots wherever the grid has scrolled.
                HStack(spacing: 24) {
                    Text(pager.item(at: focusedIndex)?.item.name ?? "placeholder")
                        .accessibilityIdentifier("spike.focusedTitle")
                    Text("loading-card focus: \(placeholderFocusCount)")
                        .accessibilityIdentifier("spike.placeholderFocusCount")
                }
                .font(.caption)
                .padding(8)
                .background(.black.opacity(0.6), in: .rect(cornerRadius: 8))
                .padding(.leading, 400)
            }
        } else {
            ProgressView()
        }
    }
}

/// Items spread evenly from A to Z: item `i` of `count` is filed under letter `i * 26 / count`.
private nonisolated enum SpikeLibrary {
    static func item(_ index: Int, of count: Int) -> LibraryEntry {
        let letter = letters[index * 26 / count]
        let name = "\(letter) item \(index)"
        return LibraryEntry(item: MediaItem(id: "item-\(index)", name: name, kind: .movie), sortName: name.lowercased())
    }

    /// The first index filed under `letter`.
    static func position(of letter: Character, count: Int) -> Int {
        guard let offset = letters.firstIndex(of: letter) else { return 0 }
        return (offset * count + 25) / 26
    }

    private static let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
}
