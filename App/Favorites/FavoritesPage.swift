import AnemoneJellyfin
import AnemoneUI
import SwiftUI

/// Wholphin's Favorites page (`FavoritesPage`): the user's favourites, a row per type where
/// Wholphin has a tab per type, in its order. The header and backdrop describe the focused card,
/// as on the home page.
struct FavoritesPage: View {
    /// Whether the sidebar shows Favorites.
    static let isAvailable = true

    /// Whether Favorites is the page chosen in the sidebar.
    let isSelected: Bool

    @State private var stack = PageStack()

    var body: some View {
        NavigationStack(path: $stack.path) {
            FavoritesContentView(isSelected: isSelected)
                // The stack's root, which `itemPages(in:)` doesn't reach.
                .environment(\.pageStack, stack)
                .itemPages(in: stack)
        }
    }
}

private struct FavoritesContentView: View {
    let isSelected: Bool

    @Environment(BrowseModel.self) private var browse
    @Environment(ItemContextActions.self) private var actions
    @FocusState private var focus: ItemFocus?
    @State private var memory = RowMemory()
    @State private var content: FavoritesContent?
    @State private var problem: String?
    @State private var focusedItem: ItemDetails?
    /// Follows `focusedItem` after a pause, like the home page's backdrop.
    @State private var backdropItem: ItemDetails?

    /// What the page is loaded from. A change, such as a favourite removed from a card's menu,
    /// loads it again.
    private struct Load: Equatable {
        let isSelected: Bool
        let revision: Int
        let libraries: [Library.ID]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FavoritesHeader(item: focusedItem)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: Self.headerHeight, alignment: .bottomLeading)
                .padding(.horizontal, ItemLayout.horizontalInset)
                .padding(.top, ItemLayout.topInset)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: ItemLayout.sectionSpacing) {
                    rows
                }
                .padding(.horizontal, ItemLayout.horizontalInset)
                .padding(.bottom, ItemLayout.focusPadding)
            }
        }
        .background {
            BackdropImage(url: browse.imageURL(backdropItem?.item.backdropImage, width: ItemLayout.backdropPixelWidth))
                .ignoresSafeArea()
        }
        .onChange(of: focus) { _, focus in
            memory.note(focus)
            if case let .card(row, item)? = focus {
                focusedItem = content?.sections.first { row == "\($0.kind)" }?.items.first { $0.id == item }
            }
        }
        .task(id: focusedItem?.id) {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            backdropItem = focusedItem
        }
        .pageTask(id: Load(isSelected: isSelected, revision: actions.revision, libraries: browse.libraries.map(\.id))) {
            // Like Home: loads again when the page shows again, and after a card's menu changes
            // something. Leaving it cancels a load still under way.
            guard isSelected else { return }
            await load()
        }
    }

    /// Wholphin's `HeaderUtils.height`, as on the collection page.
    private static let headerHeight: CGFloat = 340

    @ViewBuilder
    private var rows: some View {
        if let content {
            if content.sections.isEmpty, content.failedKinds.isEmpty {
                Text("You have no favorites yet. Add them with the heart on an item's page, or hold Select on a card.")
                    .foregroundStyle(.secondary)
                    .focusable()
                    .accessibilityIdentifier("favorites.empty")
            }
            if !content.failedKinds.isEmpty {
                NoticeText("Some of your favorites couldn't be loaded. They'll be tried again next time.")
            }
            ForEach(content.sections) { section in
                ItemRow(
                    id: "\(section.kind)",
                    title: section.title,
                    items: section.items,
                    focus: $focus,
                    memory: memory,
                )
            }
        } else if let problem {
            Text(problem)
                .foregroundStyle(.secondary)
                .focusable()
        } else {
            ProgressView()
                .frame(maxWidth: .infinity)
        }
    }

    private func load() async {
        do {
            let loaded = try await browse.session.favorites(for: browse.libraries)
            guard !Task.isCancelled else { return }
            content = loaded
            problem = nil
            // The header keeps describing the focused card, with its new state, until it's gone.
            focusedItem = focusedItem.flatMap { focused in
                loaded.sections.lazy.flatMap(\.items).first { $0.id == focused.id }
            }
        } catch {
            // A failed reload keeps the rows already showing.
            let message = browse.problem(with: error, doing: "load your favorites from \(browse.server.name)")
            if content == nil {
                problem = message
            }
        }
    }
}

/// The focused card's details, like the home page header.
private struct FavoritesHeader: View {
    let item: ItemDetails?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(item?.cardTitle ?? "Favorites")
                .font(.title2.bold())
                .lineLimit(1)
            if let item {
                if item.item.kind == .episode, let subtitle = item.cardSubtitle {
                    Text(subtitle)
                        .font(.title3)
                        .lineLimit(1)
                }
                QuickDetails(details: item)
            }
            Text(item?.item.overview ?? " ")
                .font(.callout)
                .lineLimit(3, reservesSpace: true)
                .frame(maxWidth: ItemLayout.textWidth, alignment: .leading)
        }
    }
}

private extension FavoritesSection {
    /// Wholphin's tab names.
    var title: String {
        switch kind {
        case .movie: "Movies"
        case .series: "TV Shows"
        case .episode: "Episodes"
        case .collection: "Collections"
        case .person: "People"
        case .musicAlbum: "Albums"
        case .musicArtist: "Artists"
        case .audio: "Songs"
        case .musicVideo: "Music Videos"
        case .playlist: "Playlists"
        case .video: "Videos"
        case .photo: "Photos"
        case .season, .folder, .other: "Other"
        }
    }
}
