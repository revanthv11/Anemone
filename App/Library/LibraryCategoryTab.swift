import AnemoneJellyfin
import AnemoneUI
import SwiftUI

/// A library's Genres or Studios tab, from Wholphin's `GenreCardGrid` and `StudioCardGrid`: 16:9
/// cards, four across, with the alphabet bar. A genre's card shows the backdrop of a random title
/// in it under the genre's own colour; a studio's shows its image, or its name when it has none.
/// Selecting one opens the library's titles in that genre or from that studio.
struct LibraryCategoryTab: View {
    enum Kind {
        case genres
        case studios
    }

    let library: Library
    let kind: Kind
    @Binding var path: NavigationPath
    var onPastFirstRow: (Bool) -> Void = { _ in }
    /// Called as focus goes up past the top of the alphabet bar, for the page's tabs.
    var onExitTop: (() -> Void)?

    @Environment(BrowseModel.self) private var browse
    @State private var content = Content.loading
    /// Genre cards' artwork, which arrives after the genres.
    @State private var genreArt: [String: ItemImage] = [:]

    private enum Content {
        case loading
        case loaded(LibraryPager, sortNames: [String?])
        case failed
        case signedOut
    }

    var body: some View {
        Group {
            switch content {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .loaded(pager, sortNames):
                grid(pager, sortNames: sortNames)
            case .failed:
                message("Couldn't load the \(noun) in \(library.name) from \(browse.server.name).") {
                    Button("Try again") {
                        Task { await load() }
                    }
                }
            case .signedOut:
                message("\(browse.server.name) signed you out. Go to Home to sign in again.") {}
            }
        }
        .task {
            await load()
        }
    }

    private func grid(_ pager: LibraryPager, sortNames: [String?]) -> some View {
        LibraryGrid(
            pager: pager,
            options: GridViewOptions(shape: .thumb, columns: 4, showTitles: false),
            showsJumpBar: pager.count > 0,
            position: { letter in LibraryJump.position(of: letter, in: sortNames) },
            onSelect: open,
            onPastFirstRow: onPastFirstRow,
            onExitTop: onExitTop,
            emptyMessage: "There are no \(noun) in \(library.name).",
            hearsPageButtons: true,
            card: { entry, width, pixelWidth in
                CategoryCard(
                    id: entry?.id,
                    name: entry?.item.name ?? " ",
                    imageURL: entry.flatMap { imageURL(for: $0, pixelWidth: pixelWidth) },
                    showsNameOverImage: kind == .genres,
                    width: width,
                )
            },
            header: {
                Text(pager.count == 1 ? "1 \(singular)" : "\(pager.count.formatted()) \(noun)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            },
        )
    }

    private func message(_ text: String, @ViewBuilder actions: () -> some View) -> some View {
        VStack(spacing: 24) {
            Text(text)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            actions()
        }
        // Gives focus somewhere to rest, so the tabs and the sidebar stay in reach.
        .focusable()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noun: String {
        kind == .genres ? "genres" : "studios"
    }

    private var singular: String {
        kind == .genres ? "genre" : "studio"
    }

    private func imageURL(for entry: LibraryEntry, pixelWidth: Int) -> URL? {
        let image = kind == .genres ? genreArt[entry.id] : entry.item.thumbImage
        return browse.imageURL(image, width: CGFloat(pixelWidth))
    }

    private func open(_ category: MediaItem) {
        let scope: LibraryQuery.Scope = kind == .genres ? .genre(category.id) : .studio(category.id)
        path.append(LibraryCategoryPage(library: library, scope: scope, title: "\(category.name) \(library.name)"))
    }

    private func load() async {
        let session = browse.session
        let entries: [LibraryEntry]
        do {
            entries = try await kind == .genres ? session.libraryGenres(in: library) : session
                .libraryStudios(in: library)
        } catch SessionError.signedOut {
            browse.noteSignedOut()
            content = .signedOut
            return
        } catch {
            guard !Task.isCancelled else { return }
            content = .failed
            return
        }
        // All of them are here already; the grid pages through them like a library's titles.
        let pager = LibraryPager { startIndex, limit, includeTotalCount in
            let page = entries.dropFirst(startIndex).prefix(limit)
            return LibraryPage(items: Array(page), totalCount: includeTotalCount ? entries.count : nil)
        }
        try? await pager.start()
        guard !Task.isCancelled else { return }
        content = .loaded(pager, sortNames: entries.map { $0.sortName ?? $0.item.name })
        if kind == .genres {
            do {
                let art = try await GenreArtCache.images(for: entries.map(\.id), in: library, session: session)
                guard !Task.isCancelled else { return }
                genreArt = art
            } catch {
                // Only a revoked token gets here; other failures leave their cards plain.
                browse.noteSignedOut()
                content = .signedOut
            }
        }
    }
}

/// A genre's or studio's page in a library, opened from its Genres or Studios tab.
struct LibraryCategoryPage: Hashable {
    let library: Library
    let scope: LibraryQuery.Scope
    /// Like Wholphin's: the genre or studio, then the library, as in "Drama Movies".
    let title: String
}

/// Genre cards' artwork, kept for two hours per library as Wholphin keeps it, so going back to
/// the tab doesn't ask for it all again or change every picture.
@MainActor
private enum GenreArtCache {
    private static var entries: [String: (fetched: Date, images: [String: ItemImage])] = [:]

    /// - Throws: `SessionError.signedOut`, from any genre's request.
    static func images(
        for genreIDs: [String],
        in library: Library,
        session: JellyfinSession,
    ) async throws -> [String: ItemImage] {
        let key = "\(session.serverURL.absoluteString)|\(session.userID)|\(library.id)"
        if let cached = entries[key], cached.fetched.timeIntervalSinceNow > -2 * 60 * 60 {
            return cached.images
        }
        let backdrops = try await session.genreBackdrops(for: genreIDs, in: library)
        // Only a full set is kept. Wholphin caches only when every request succeeds; one cut
        // short by leaving the tab, or missing a genre whose request failed, would otherwise
        // leave those cards plain for two hours.
        if backdrops.isComplete {
            entries[key] = (.now, backdrops.images)
        }
        return backdrops.images
    }
}

/// A 16:9 card with a name over a picture, like Wholphin's `GenreCard` and `StudioCard`.
private struct CategoryCard: View {
    let id: String?
    let name: String
    let imageURL: URL?
    /// Genres keep their name and colour over the picture; studios' pictures are their logos.
    let showsNameOverImage: Bool
    let width: CGFloat

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.quaternary)
            if let imageURL {
                ArtworkImage(url: imageURL)
                    .opacity(0.75)
            }
            if showsNameOverImage || imageURL == nil {
                Rectangle()
                    .fill(Color(id: id).opacity(showsNameOverImage ? 0.6 : 0.4))
                Text(name)
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(16)
            }
        }
        .frame(width: width, height: width / CardShape.thumb.aspectRatio)
        .clipShape(.rect(cornerRadius: 12))
        .hoverEffect(.highlight)
    }
}

private extension Color {
    /// A colour of the ID's own, like Wholphin's `rememberIdColor`: a hue from the ID, fairly
    /// saturated and dark, so white text stands out on it. The same ID always gets the same one.
    init(id: String?) {
        guard let id else {
            self = .gray
            return
        }
        // FNV-1a, since Swift's own hashes change from one launch to the next.
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in id.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100_0000_01B3
        }
        self.init(
            hue: Double(hash % 360) / 360,
            saturation: 0.6 + Double(hash / 360 % 40) / 100,
            brightness: 0.4 + Double(hash / 14400 % 30) / 100,
        )
    }
}
