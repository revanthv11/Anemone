import AnemoneJellyfin
import AnemoneUI
import SwiftUI

/// Wholphin's collection page (`CollectionDetails`), with its default view options: the
/// collection's header and actions, then a row for each type of item in it. While a card has
/// focus, the header and backdrop describe that card instead, as in Wholphin.
struct CollectionPage: View {
    @Binding var collection: ItemDetails

    @Environment(BrowseModel.self) private var browse
    @FocusState private var focus: ItemFocus?
    @State private var memory = RowMemory()
    @State private var sections: [CollectionSection]?
    @State private var problem: String?
    @State private var alert: ItemAlert?
    /// The card the header describes; `nil` for the collection itself.
    @State private var focusedEntry: ItemDetails?
    /// Follows `focusedEntry` after a pause, like the home page's backdrop.
    @State private var backdropEntry: ItemDetails?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let focusedEntry {
                    EntryHeader(entry: focusedEntry)
                } else {
                    collectionHeader
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: Self.headerHeight, alignment: .bottomLeading)
            .padding(.horizontal, ItemLayout.horizontalInset)
            .padding(.top, ItemLayout.topInset)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: ItemLayout.sectionSpacing) {
                    buttons
                    rows
                }
                .padding(.horizontal, ItemLayout.horizontalInset)
                .padding(.bottom, ItemLayout.focusPadding)
            }
        }
        .background {
            BackdropImage(url: browse.imageURL(
                (backdropEntry ?? collection).item.backdropImage,
                width: ItemLayout.backdropPixelWidth,
            ))
            .ignoresSafeArea()
        }
        .initialFocus($focus, .action(.play))
        .itemAlert($alert)
        .onChange(of: focus) { _, focus in
            memory.note(focus)
            switch focus {
            case let .card(row, item)?:
                focusedEntry = entry(row: row, item: item)
            case .some:
                focusedEntry = nil
            case nil:
                break
            }
        }
        .task(id: focusedEntry?.id) {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            backdropEntry = focusedEntry
        }
        .task(id: collection.id) {
            do {
                sections = try await browse.session.collectionSections(id: collection.id)
                problem = nil
            } catch {
                // A failed refresh keeps the rows already showing.
                let message = browse.problem(with: error, doing: "load what's in \(collection.item.name)")
                if sections == nil {
                    problem = message
                }
            }
        }
    }

    /// Wholphin's `HeaderUtils.height`, with room for a logo.
    private static let headerHeight: CGFloat = 420

    /// Wholphin's `CollectionDetailsHeader`.
    private var collectionHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            ItemTitle(title: collection.item.name, logo: collection.logo)
            QuickDetails(details: collection)
            if !collection.genres.isEmpty {
                NameList(names: collection.genres)
            }
            if let tagline = collection.tagline {
                Text(tagline)
                    .font(.callout)
                    .italic()
            }
            if let overview = collection.item.overview {
                OverviewButton(title: collection.item.name, overview: overview)
                    .focused($focus, equals: .overview)
            }
        }
        .frame(maxWidth: ItemLayout.textWidth, alignment: .leading)
    }

    /// Wholphin's `CollectionButtons`, without sorting, filters and view options.
    private var buttons: some View {
        HStack(spacing: 24) {
            ActionButton(title: "Play", systemImage: "play.fill") {
                alert = .playbackUnavailable(resumeAt: nil)
            }
            .focused($focus, equals: .action(.play))
            .accessibilityIdentifier("action.play")
            ActionButton(title: "Shuffle", systemImage: "shuffle") {
                alert = .playbackUnavailable(resumeAt: nil)
            }
            .focused($focus, equals: .action(.shuffle))
            FavoriteButton(isFavorite: collection.userState.isFavorite) {
                Task { await setFavorite(!collection.userState.isFavorite) }
            }
            .focused($focus, equals: .action(.favorite))
            PlaybackNotWiredNote()
                .padding(.leading, 16)
        }
        .padding(.vertical, 20)
        .focusSection()
    }

    @ViewBuilder
    private var rows: some View {
        if let sections {
            if sections.isEmpty {
                Text("There's nothing in this collection yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(sections) { section in
                ItemRow(
                    id: section.rowID,
                    title: section.title,
                    items: section.items,
                    focus: $focus,
                    memory: memory,
                )
            }
        } else if let problem {
            NoticeText(problem)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity)
        }
    }

    private func entry(row: String, item: String) -> ItemDetails? {
        sections?.first { $0.rowID == row }?.items.first { $0.id == item }
    }

    private func setFavorite(_ isFavorite: Bool) async {
        if let state = await browse.save(.favorite(isFavorite), for: collection, failed: { alert = $0 }) {
            collection.apply(state)
        }
    }
}

/// The focused card's details in place of the collection's, like the home page header.
private struct EntryHeader: View {
    let entry: ItemDetails

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(entry.cardTitle)
                .font(.title2.bold())
                .lineLimit(1)
            if entry.item.kind == .episode, let subtitle = entry.cardSubtitle {
                Text(subtitle)
                    .font(.title3)
                    .lineLimit(1)
            }
            QuickDetails(details: entry)
            Text(entry.item.overview ?? " ")
                .font(.callout)
                .lineLimit(3, reservesSpace: true)
                .frame(maxWidth: ItemLayout.textWidth, alignment: .leading)
        }
    }
}

private extension CollectionSection {
    var rowID: String {
        "\(kind)"
    }

    var title: String {
        switch kind {
        case .movie: "Movies"
        case .series: "TV Shows"
        case .episode: "Episodes"
        case .video: "Videos"
        case .collection: "Collections"
        case .musicAlbum: "Albums"
        case .musicVideo: "Music Videos"
        default: "Other"
        }
    }
}
