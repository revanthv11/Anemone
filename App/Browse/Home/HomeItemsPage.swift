import AnemoneJellyfin
import AnemoneUI
import SwiftUI

/// A genre's or studio's items in one library, opened from its card on Home, like Wholphin's
/// genre and studio destinations: the library's grid with only that genre or studio.
struct HomeItemsPage: View {
    let link: HomeItemsLink

    @Environment(BrowseModel.self) private var browse
    @Environment(\.pageStack) private var stack
    @Environment(\.theme) private var theme
    @State private var content = Content.loading

    private enum Content {
        case loading
        case loaded(LibraryPager)
        case failed
    }

    var body: some View {
        Group {
            switch content {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .loaded(pager):
                LibraryGrid(
                    pager: pager,
                    options: GridViewOptions.defaults(for: link.query.library.kind),
                    showsJumpBar: false,
                    position: { _ in 0 },
                    imageURL: { item, shape, pixels in
                        browse.imageURL(item.image(for: shape), width: CGFloat(pixels))
                    },
                    onSelect: { stack?.path.append($0) },
                    header: { header(count: pager.count) },
                )
            case .failed:
                VStack(spacing: 24) {
                    Text("Couldn't load \(link.title) from \(browse.server.name).")
                        .foregroundStyle(theme.secondaryText)
                    Button("Try again") {
                        Task { await load() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            await load()
        }
    }

    private func header(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(link.title)
                .font(.title2.bold())
                .foregroundStyle(theme.onBackground)
                .lineLimit(1)
            Text([link.query.library.name, count == 1 ? "1 item" : "\(count.formatted()) items"]
                .filter { !$0.isEmpty }
                .joined(separator: " · "))
                .font(.callout)
                .foregroundStyle(theme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Gives focus somewhere to rest above the grid, as the library page's buttons do, and
        // VoiceOver reads it as the page's heading when it's there.
        .focusable()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func load() async {
        content = .loading
        let session = browse.session
        let query = link.query
        let pager = LibraryPager { startIndex, limit, includeTotalCount in
            try await session.libraryItems(
                query,
                startIndex: startIndex,
                limit: limit,
                includeTotalCount: includeTotalCount,
            )
        }
        do {
            try await pager.start()
            content = .loaded(pager)
        } catch SessionError.signedOut {
            browse.noteSignedOut()
            content = .failed
        } catch {
            guard !Task.isCancelled else { return }
            content = .failed
        }
    }
}
