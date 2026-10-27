import AnemoneJellyfin
import AnemonePlayback
import AnemoneUI
import SwiftUI

extension EnvironmentValues {
    /// The row the cards below are in, which decides what their menus can take a card out of.
    /// Home sets it on its watching rows; everywhere else it's `.other`.
    @Entry var cardMenuSource: ItemMenuSource = .other
}

extension View {
    /// Gives every card below Wholphin's long-press menu (`ContextMenu`), with the player,
    /// alerts and playlist choice it opens. Set once, around the signed-in app.
    func itemContextActions() -> some View {
        modifier(ItemContextActionsHost())
    }
}

/// What card menus do. There's one for the signed-in app, so a change made from any card shows
/// on every card of that item.
@Observable
final class ItemContextActions {
    /// Marks changed from menus, which cards show until their pages reload.
    let marks = CardMarksStore()
    let menu: CardMenu
    /// Goes up whenever a menu saves a change or playback ends, so pages listing items by their
    /// state, like Favorites, load again.
    private(set) var revision = 0
    var playback: PlaybackRequest?
    var alert: ItemAlert?
    /// The item whose playlist choice is showing.
    var playlistItem: MediaItem?
    /// The card whose item is playing, to update once the player closes.
    @ObservationIgnored private var playing: (id: MediaItem.ID, given: CardMarks)?

    init() {
        menu = CardMenu(marks: marks) { item, given in
            ItemContextMenu(item: item, given: given)
        }
    }

    /// Saves a change to the item's watched or favourite state, and shows it on its cards.
    /// Returns whether it was saved.
    @discardableResult
    func save(_ change: UserStateChange, for target: MenuTarget, given: CardMarks, browse: BrowseModel) async -> Bool {
        guard let state = await browse.save(change, for: target.details, failed: { alert = $0 }) else {
            return false
        }
        note(state, for: target.id, given: given)
        return true
    }

    /// Plays the item from the beginning, or from where the user left off.
    func play(_ target: MenuTarget, resuming: Bool, given: CardMarks, browse: BrowseModel) async {
        var details = target.details
        // A card without the user's state, or one a menu or the player has changed since, may not
        // have the current resume position.
        if !target.knowsState || marks.savedMarks(for: target.id, given: given) != nil {
            do {
                details = try await browse.session.itemDetails(id: target.id)
            } catch {
                if let message = browse.problem(with: error, doing: "load \(target.item.name)") {
                    alert = .failed(message)
                }
                return
            }
        }
        playing = (target.id, given)
        playback = browse.playback(of: details, from: resuming ? details.userState.resumePosition : nil)
    }

    /// Once the player closes, the card shows the new progress, and Home its new Continue
    /// Watching and Next Up, as the item's own page does after playback.
    func playerClosed(browse: BrowseModel) async {
        guard let playing else { return }
        self.playing = nil
        let session = browse.session
        let id = playing.id
        if let details = await browse.optional(attempt { try await session.itemDetails(id: id) }) {
            note(details.userState, for: id, given: playing.given)
        }
        await browse.refresh()
    }

    private func note(_ state: ItemDetails.UserState, for id: MediaItem.ID, given: CardMarks) {
        var badges = CardBadges(isFavorite: state.isFavorite, isPlayed: state.isPlayed)
        // The server's answer to a change doesn't always have a count. Cards of the item that show
        // one take it from here, and only those do.
        badges.unplayedCount = state.unplayedCount ?? given.badges.unplayedCount.map { state.isPlayed ? 0 : $0 }
        marks.record(CardMarks(badges: badges, progress: state.progress), for: id, replacing: given)
        revision += 1
    }
}

/// The item a card's menu is about, and the user's state with it when the card knows it.
struct MenuTarget {
    let details: ItemDetails
    /// Whether `details` has the user's state. Home rows and library grids show a `MediaItem`
    /// without it.
    let knowsState: Bool

    init?(_ menuItem: CardMenuItem) {
        switch menuItem.value {
        case let details as ItemDetails:
            self.details = details
            knowsState = true
        case let item as MediaItem:
            details = ItemDetails(item: item)
            knowsState = false
        default:
            return nil
        }
    }

    var id: MediaItem.ID {
        details.id
    }

    var item: MediaItem {
        details.item
    }
}

/// Puts the card menu in the environment and shows what its entries open.
private struct ItemContextActionsHost: ViewModifier {
    @Environment(BrowseModel.self) private var browse
    @State private var actions = ItemContextActions()

    func body(content: Content) -> some View {
        @Bindable var actions = actions
        content
            .environment(\.cardMenu, actions.menu)
            .environment(actions)
            .player($actions.playback) {
                await actions.playerClosed(browse: browse)
            }
            .itemAlert($actions.alert)
            .sheet(item: $actions.playlistItem) { item in
                PlaylistPicker(item: item)
            }
    }
}

/// A card's menu: Wholphin's entries for what the card knows about its item.
private struct ItemContextMenu: View {
    let item: CardMenuItem
    /// The marks the card's caller passed, which changes are recorded against.
    let given: CardMarks

    @Environment(BrowseModel.self) private var browse
    @Environment(ItemContextActions.self) private var actions
    @Environment(\.pageStack) private var stack
    @Environment(\.cardMenuSource) private var source

    var body: some View {
        if let target = MenuTarget(item) {
            ForEach(entries(for: target), id: \.self) { entry in
                Button(entry.title, systemImage: entry.systemImage) {
                    perform(entry, on: target)
                }
                .accessibilityIdentifier("menu.\(entry.identifier)")
            }
        }
    }

    private func entries(for target: MenuTarget) -> [ItemMenuEntry] {
        let state = if let saved = actions.marks.savedMarks(for: target.id, given: given) {
            // What a menu last saved for the item, from any of its cards, which is newer than what
            // this card holds.
            ItemMenuState(
                isPlayed: saved.badges.isPlayed,
                isFavorite: saved.badges.isFavorite,
                isResumable: (saved.progress ?? 0) > 0,
            )
        } else if target.knowsState {
            target.details.menuState
        } else {
            ItemMenuState(isResumable: (given.progress ?? 0) > 0)
        }
        return target.item.menuEntries(state: state, source: source, canGoTo: stack != nil)
    }

    private func perform(_ entry: ItemMenuEntry, on target: MenuTarget) {
        switch entry {
        case .goTo:
            stack?.path.append(target.item)
        case let .goToSeries(series):
            stack?.path.append(series)
        case .play, .restart:
            Task { await actions.play(target, resuming: false, given: given, browse: browse) }
        case .resume:
            Task { await actions.play(target, resuming: true, given: given, browse: browse) }
        case .addToPlaylist:
            actions.playlistItem = target.item
        case .removeFromContinueWatching:
            Task {
                if await actions.save(.played(false), for: target, given: given, browse: browse) {
                    await browse.refresh()
                }
            }
        case .removeFromNextUp:
            // Home's, which also refreshes Home.
            Task { await browse.removeFromNextUp(target.item) }
        case let .setPlayed(isPlayed):
            Task { await actions.save(.played(isPlayed), for: target, given: given, browse: browse) }
        case let .setFavorite(isFavorite):
            Task { await actions.save(.favorite(isFavorite), for: target, given: given, browse: browse) }
        }
    }
}

private extension ItemMenuEntry {
    /// Wholphin's wording, as on the item pages' buttons.
    var title: String {
        switch self {
        case .goTo: "Go to"
        case .play: "Play"
        case .resume: "Resume"
        case .restart: "Restart"
        case .addToPlaylist: "Add to playlist"
        case .removeFromContinueWatching: "Remove from Continue Watching"
        case .removeFromNextUp: "Remove from Next Up"
        case let .setPlayed(isPlayed): isPlayed ? "Mark as watched" : "Mark as unwatched"
        case let .setFavorite(isFavorite): isFavorite ? "Add to favorites" : "Remove from favorites"
        case .goToSeries: "Go to series"
        }
    }

    var systemImage: String {
        switch self {
        case .goTo: "arrow.forward"
        case .play, .resume: "play.fill"
        case .restart: "arrow.counterclockwise"
        case .addToPlaylist: "text.badge.plus"
        case .removeFromContinueWatching: "eye"
        case .removeFromNextUp: "minus.circle"
        case let .setPlayed(isPlayed): isPlayed ? "eye.slash" : "eye"
        case let .setFavorite(isFavorite): isFavorite ? "heart" : "heart.slash"
        case .goToSeries: "tv"
        }
    }

    /// For UI tests: `menu.<identifier>`.
    var identifier: String {
        switch self {
        case .goTo: "goTo"
        case .play: "play"
        case .resume: "resume"
        case .restart: "restart"
        case .addToPlaylist: "addToPlaylist"
        case .removeFromContinueWatching: "removeFromContinueWatching"
        case .removeFromNextUp: "removeFromNextUp"
        case let .setPlayed(isPlayed): isPlayed ? "markWatched" : "markUnwatched"
        case let .setFavorite(isFavorite): isFavorite ? "addFavorite" : "removeFavorite"
        case .goToSeries: "goToSeries"
        }
    }
}

/// Wholphin's playlist dialog (`PlaylistDialog`): the playlists the user may change, newest
/// first. Choosing one adds the item; a playlist that already holds it has a check, and choosing
/// it takes the item out again.
private struct PlaylistPicker: View {
    let item: MediaItem

    @Environment(BrowseModel.self) private var browse
    @Environment(\.dismiss) private var dismiss
    @State private var playlists: [EditablePlaylist]?
    @State private var problem: String?
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            Text("Add \(item.name) to a playlist")
                .font(.title2.bold())
            if let problem {
                Text(problem)
                    .foregroundStyle(.secondary)
            }
            if let playlists {
                if playlists.isEmpty {
                    Text("You have no playlists you can change.")
                        .foregroundStyle(.secondary)
                        .focusable()
                }
                // A sheet takes its content's size, which a `List` doesn't have.
                ScrollView(.vertical) {
                    VStack(spacing: 16) {
                        ForEach(playlists) { playlist in
                            Button {
                                Task { await choose(playlist) }
                            } label: {
                                PlaylistLabel(playlist: playlist)
                            }
                            .disabled(isSaving)
                            .accessibilityValue(playlist.holdsItem ? "Has this item" : "")
                            .accessibilityIdentifier("playlist.\(playlist.id)")
                        }
                    }
                    .padding(.vertical, ItemLayout.focusPadding)
                }
                .scrollClipDisabled()
                .frame(maxHeight: 600)
            } else if problem == nil {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(width: 1100, alignment: .topLeading)
        .padding(60)
        .task {
            await load()
        }
    }

    private func load() async {
        do {
            playlists = try await browse.session.editablePlaylists(for: item.id)
        } catch {
            problem = browse.problem(with: error, doing: "load your playlists")
        }
    }

    private func choose(_ playlist: EditablePlaylist) async {
        isSaving = true
        defer { isSaving = false }
        do {
            if playlist.holdsItem {
                try await browse.session.removeFromPlaylist(playlist.id, itemID: item.id)
            } else {
                try await browse.session.addToPlaylist(playlist.id, itemID: item.id)
            }
            dismiss()
        } catch {
            problem = browse.problem(with: error, doing: "change \(playlist.name)")
        }
    }
}

private struct PlaylistLabel: View {
    let playlist: EditablePlaylist

    var body: some View {
        HStack(spacing: 24) {
            Image(systemName: playlist.holdsItem ? "checkmark" : "plus")
                .frame(width: 40)
            Text(playlist.name.isEmpty ? "Untitled" : playlist.name)
            Spacer()
            Text(playlist.itemCount == 1 ? "1 item" : "\(playlist.itemCount) items")
                .foregroundStyle(.secondary)
        }
    }
}
