import AnemoneJellyfin
import AnemoneUI
import SwiftUI

/// Wholphin's playlist page (`PlaylistDetails`) in its default list view: the playlist's title
/// and actions, the focused entry's details on the left, and the entries in order on the right.
struct PlaylistPage: View {
    @Binding var playlist: ItemDetails

    @Environment(BrowseModel.self) private var browse
    @FocusState private var focus: ItemFocus?
    @State private var memory = RowMemory()
    @State private var entries: [ItemDetails]?
    /// Whether the user may reorder the playlist, which shows Wholphin's move buttons.
    @State private var canEdit = false
    /// Set while a move is with the server, so moves go one at a time and in order.
    @State private var isMoving = false
    @State private var problem: String?
    @State private var alert: ItemAlert?
    @State private var focusedIndex = 0
    /// Follows the focused entry after a pause, like the home page's backdrop.
    @State private var backdropEntry: ItemDetails?

    private static let listID = "entries"
    private static let moveUpID = "moveUp"
    private static let moveDownID = "moveDown"

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            HStack(alignment: .top, spacing: 60) {
                EntryPanel(entry: focusedEntry)
                list
            }
        }
        .padding(.horizontal, ItemLayout.horizontalInset)
        .padding(.top, ItemLayout.topInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            BackdropImage(url: browse.imageURL(backdropEntry?.item.backdropImage, width: ItemLayout.backdropPixelWidth))
                .ignoresSafeArea()
        }
        // Wholphin starts on the list once it has loaded.
        .initialFocus($focus, entries.map { $0.isEmpty ? .action(.play) : entryFocus(0) })
        .itemAlert($alert)
        .onChange(of: focus) { _, focus in
            memory.note(focus)
            if case let .card(_, item) = focus, let index = Int(item) {
                focusedIndex = index
            }
        }
        .task(id: focusedEntry?.id) {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            backdropEntry = focusedEntry
        }
        .task(id: playlist.id) {
            let session = browse.session
            let id = playlist.id
            async let canEdit = attempt { try await session.canEditPlaylist(id: id) }
            await loadEntries()
            self.canEdit = await browse.optional(canEdit) ?? false
        }
    }

    /// Whether an item is in the playlist more than once. The server moves an entry by its item,
    /// taking the first copy it finds, so such a playlist can't be reordered reliably and gets no
    /// move buttons.
    private var hasRepeats: Bool {
        let ids = entries?.map(\.id) ?? []
        return Set(ids).count != ids.count
    }

    private var focusedEntry: ItemDetails? {
        entries.flatMap { $0.indices.contains(focusedIndex) ? $0[focusedIndex] : $0.first }
    }

    /// The same item can be in a playlist more than once, so entries are told apart by place.
    private func entryFocus(_ index: Int) -> ItemFocus {
        .card(row: Self.listID, item: String(index))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 40) {
            VStack(alignment: .leading, spacing: 8) {
                Text(playlist.item.name)
                    .font(.title.bold())
                    .lineLimit(1)
                    .accessibilityIdentifier("detail.title")
                QuickDetails(details: playlist)
            }
            HStack(spacing: 24) {
                ActionButton(title: "Play", systemImage: "play.fill") {
                    alert = .queueUnavailable
                }
                .focused($focus, equals: .action(.play))
                .accessibilityIdentifier("action.play")
                ActionButton(title: "Shuffle", systemImage: "shuffle") {
                    alert = .queueUnavailable
                }
                .focused($focus, equals: .action(.shuffle))
                PlaybackNotWiredNote()
                    .padding(.leading, 16)
            }
            .focusSection()
        }
    }

    /// Wholphin's move buttons, shown when the user can edit the playlist.
    private func moveButtons(index: Int, count: Int) -> some View {
        HStack(spacing: 12) {
            ActionButton(title: "Move up", systemImage: "chevron.up") {
                Task { await move(from: index, to: index - 1, button: Self.moveUpID) }
            }
            .disabled(index == 0)
            .focused($focus, equals: .card(row: Self.moveUpID, item: String(index)))
            ActionButton(title: "Move down", systemImage: "chevron.down") {
                Task { await move(from: index, to: index + 1, button: Self.moveDownID) }
            }
            .disabled(index == count - 1)
            .focused($focus, equals: .card(row: Self.moveDownID, item: String(index)))
        }
        .focusSection()
    }

    /// Moves an entry, keeping focus on the same button beside the entry's new place, as
    /// Wholphin does. When that button is disabled at the end of the list, focus goes to the
    /// entry itself.
    private func move(from index: Int, to newIndex: Int, button: String) async {
        // A press while the last move is still with the server is dropped, rather than racing it.
        guard !isMoving, var reordered = entries, reordered.indices.contains(index),
              reordered.indices.contains(newIndex)
        else { return }
        isMoving = true
        defer { isMoving = false }
        let entry = reordered.remove(at: index)
        reordered.insert(entry, at: newIndex)
        entries = reordered
        let stillEnabled = button == Self.moveUpID ? newIndex > 0 : newIndex < reordered.count - 1
        focus = stillEnabled ? .card(row: button, item: String(newIndex)) : entryFocus(newIndex)
        do {
            try await browse.session.movePlaylistItem(entry.id, inPlaylist: playlist.id, to: newIndex)
        } catch {
            alert = browse.problem(with: error, doing: "move \(entry.item.name)").map(ItemAlert.failed)
        }
        // Either way, show the order the server has now.
        await loadEntries()
    }

    private func loadEntries() async {
        do {
            entries = try await browse.session.playlistItems(id: playlist.id)
            problem = nil
        } catch {
            // A failed refresh keeps the entries already showing.
            let message = browse.problem(with: error, doing: "load \(playlist.item.name)")
            if entries == nil {
                problem = message
            }
        }
    }

    @ViewBuilder
    private var list: some View {
        if let entries {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                        HStack(spacing: 16) {
                            NavigationLink(value: entry.item) {
                                EntryRow(index: index, entry: entry)
                            }
                            .buttonStyle(HighlightButtonStyle())
                            .focused($focus, equals: entryFocus(index))
                            .accessibilityIdentifier("entry.\(index)")
                            if canEdit, !hasRepeats {
                                moveButtons(index: index, count: entries.count)
                            }
                        }
                    }
                }
                .padding(.vertical, 24)
                .padding(.horizontal, 24)
            }
            .scrollClipDisabled()
            .focusSection()
            .defaultFocus($focus, memory.entry(row: Self.listID, first: "0"), priority: .userInitiated)
            .overlay {
                if entries.isEmpty {
                    Text("This playlist is empty.")
                        .foregroundStyle(.secondary)
                }
            }
        } else if let problem {
            NoticeText(problem)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity)
        }
    }
}

/// One entry, as Wholphin's `PlaylistItem` shows it: its place, title and subtitle, length and
/// when it would end, and whether it's a favourite or watched.
private struct EntryRow: View {
    let index: Int
    let entry: ItemDetails

    var body: some View {
        HStack(spacing: 24) {
            Text("\(index + 1).")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 70, alignment: .trailing)
            if entry.userState.isFavorite {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                    .accessibilityLabel("Favorite")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.cardTitle)
                    .lineLimit(1)
                Text(entry.cardSubtitle ?? " ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 24)
            length
            if entry.userState.isPlayed {
                Image(systemName: "checkmark.circle.fill")
                    .accessibilityLabel("Watched")
            }
        }
        .font(.callout)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var length: some View {
        if entry.item.kind == .audio, let runtime = entry.item.runtime {
            Text(runtime.clockText)
        } else if let runtime = entry.item.runtime?.roundedToMinutes, runtime > .zero {
            VStack(alignment: .trailing, spacing: 4) {
                Text(runtime.lengthText)
                TimelineView(.everyMinute) { context in
                    let end = context.date.addingTimeInterval(TimeInterval(runtime.components.seconds))
                    Text("Ends at \(end.formatted(date: .omitted, time: .shortened))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

/// The focused entry's art and details, like Wholphin's `CollectionFolderListDetails`.
private struct EntryPanel: View {
    let entry: ItemDetails?

    @Environment(BrowseModel.self) private var browse
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LogoImage(
                url: browse.imageURL(entry?.logo, width: Self.width * displayScale),
                maxWidth: Self.width,
                height: 100,
            ) {
                Text(entry?.cardTitle ?? " ")
                    .font(.title3.bold())
                    .lineLimit(2)
            }
            ShapedArtwork(
                url: browse.imageURL(entry?.item.posterImage, width: Self.posterWidth * displayScale),
                shape: .poster,
                width: Self.posterWidth,
            )
            if let entry {
                QuickDetails(details: entry)
            }
            Text(entry?.item.overview ?? " ")
                .font(.caption)
                .lineLimit(5)
        }
        .frame(width: Self.width, alignment: .leading)
        .animation(nil, value: entry)
    }

    private static let width: CGFloat = 520
    private static let posterWidth: CGFloat = 240
}
