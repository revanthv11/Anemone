import AnemoneCore
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
    let menu: CardMenu
    /// The last favourite a menu added or removed, so the Favorites page can load that row again.
    /// Other changes show on the cards through `marks`, and need no reload.
    private(set) var favoriteChange: FavoriteChange?
    var playback: PlaybackRequest?
    var alert: ItemAlert?
    /// The item whose playlist choice is showing.
    var playlistItem: MediaItem?
    /// The item a menu's Delete is asking about.
    var deleting: ItemDetails?
    /// Whether Now Playing shows, for a playlist of songs played from its card.
    var showsNowPlaying = false
    /// The card whose item is playing, to update and focus again once the player closes.
    @ObservationIgnored private var playing: Playing?
    /// The card whose menu asked to delete its item, to focus again if the user cancels: the
    /// confirmation shows over the whole app, so tvOS doesn't know the card when it goes.
    @ObservationIgnored private var deletingCard: CardFocusToken?

    private struct Playing {
        let id: MediaItem.ID
        /// The marks the card's caller passed.
        let given: CardMarks
        let card: CardFocusToken?
    }

    /// - Parameter marks: the session's, `BrowseModel.cardMarks`, which item pages' own changes
    ///   go to as well.
    init(marks: CardMarksStore) {
        menu = CardMenu(marks: marks) { item, given in
            ItemContextMenu(item: item, given: given)
        }
    }

    /// Changes saved from menus and item pages, which cards show until their pages reload.
    var marks: CardMarksStore {
        menu.marks
    }

    /// Saves a change to the item's watched or favourite state, and shows it on its cards.
    /// Returns whether it was saved.
    @discardableResult
    func save(_ change: UserStateChange, for target: MenuTarget, given: CardMarks, browse: BrowseModel) async -> Bool {
        guard await browse.save(change, for: target.details, given: given, failed: { alert = $0 }) != nil else {
            return false
        }
        if case .favorite = change {
            favoriteChange = FavoriteChange(serial: (favoriteChange?.serial ?? 0) + 1, kind: target.item.kind)
            // Home's favourites row of that type gains or loses the item, which only a reload shows.
            if browse.homeRows?.contains(where: { $0.showsFavorites(of: target.item.kind) }) == true {
                await browse.refresh()
            }
        }
        return true
    }

    /// Plays the item from the beginning, or from where the user left off.
    func play(_ target: MenuTarget, resuming: Bool, given: CardMarks, browse: BrowseModel) async {
        // Read before the request below, while focus can't have moved on from the menu's card.
        let card = menu.focusReturn.menuCard
        var details = target.details
        // A card without the user's state, or one a menu or the player has changed since, may not
        // have the current resume position.
        if !target.knowsState || marks.savedMarks(for: target.id, given: given) != nil {
            do {
                details = try await browse.session.itemDetails(id: target.id)
            } catch {
                if let message = browse.problem(with: error, failure: "Couldn't load \(target.item.name).") {
                    alert = .failed(message)
                }
                return
            }
        }
        playing = Playing(id: target.id, given: given, card: card)
        playback = browse.playback(of: details, from: resuming ? details.userState.resumePosition : nil)
    }

    /// Play or Shuffle on a series, season, collection or playlist: what's in it, queued as the
    /// page's own buttons queue it (3b). Series Play resumes the episode next up. A playlist of
    /// songs plays as music, as its page plays it (5b); its entries are asked for first, so a
    /// playlist of videos doesn't stop the music on its way to the video player.
    func playQueue(
        _ target: MenuTarget,
        shuffled: Bool,
        given: CardMarks,
        browse: BrowseModel,
        music: MusicPlayer,
    ) async {
        let card = menu.focusReturn.menuCard
        if target.item.kind == .playlist {
            let session = browse.session
            let id = target.id
            // When the entries can't be read, the video player's request says why.
            if let entries = await browse.optional(attempt { try await session.playlistItems(id: id) }),
               await music.playPlaylist(target.details, entries: entries, shuffled: shuffled, browse: browse, failed: {
                   self.alert = .failed($0)
               })
            {
                showsNowPlaying = true
                return
            }
        }
        await browse.playQueue(of: target.details, shuffled: shuffled) { request in
            playing = Playing(id: target.id, given: given, card: card)
            playback = request
        } failed: { alert = $0 }
    }

    /// Asks whether to delete the item, from its card's menu.
    func askToDelete(_ item: ItemDetails) {
        deletingCard = menu.focusReturn.menuCard
        deleting = item
    }

    /// The user backed out of Delete: focus goes back to the card.
    func deleteCancelled() {
        if let card = deletingCard {
            menu.focusReturn.returnFocus(to: card)
        }
        deletingCard = nil
    }

    /// Deletes the item, once Delete was confirmed, as the item page's button does: the pages
    /// showing it drop its cards, and Home loads again.
    func delete(_ item: ItemDetails, browse: BrowseModel) async {
        deletingCard = nil
        do {
            try await browse.delete(item)
            await browse.refresh()
        } catch {
            if let message = browse.problem(with: error, failure: "Couldn't delete \(item.item.name).") {
                alert = .failed(message)
            }
        }
    }

    /// Once the player closes, focus goes back to the card, which shows the new progress, and
    /// Home its new Continue Watching and Next Up, as the item's own page does after playback.
    func playerClosed(browse: BrowseModel) async {
        guard let playing else { return }
        self.playing = nil
        if let card = playing.card {
            menu.focusReturn.returnFocus(to: card)
        }
        let session = browse.session
        let id = playing.id
        if let details = await browse.optional(attempt { try await session.itemDetails(id: id) }) {
            let given = playing.given
            marks.record(CardMarks(details.userState, replacing: given), for: id, replacing: given)
        }
        await browse.refresh()
    }
}

/// A favourite added or removed from a card's menu.
struct FavoriteChange: Equatable {
    /// Counts the changes, so changing the same kind of item twice is two changes.
    let serial: Int
    /// The changed item's type, whose row on the Favorites page it's in.
    let kind: MediaItem.Kind
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
    @StateObject private var owner = ItemContextActionsOwner()

    func body(content: Content) -> some View {
        @Bindable var actions = owner.actions(marks: browse.cardMarks)
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
            .nowPlaying(isPresented: $actions.showsNowPlaying)
            .deleteConfirmation(for: $actions.deleting, cancelled: actions.deleteCancelled) { item in
                Task { await actions.delete(item, browse: browse) }
            }
    }
}

/// Builds the actions once for the host. `@State` would build a new model each time the modifier
/// is created, and throw all but the first away; `@StateObject` builds its object only for the
/// first. Nothing is published here: views observe the actions themselves.
private final class ItemContextActionsOwner: ObservableObject {
    private var built: ItemContextActions?

    /// The host's actions, built the first time with the session's marks store.
    func actions(marks: CardMarksStore) -> ItemContextActions {
        if let built {
            return built
        }
        let actions = ItemContextActions(marks: marks)
        built = actions
        return actions
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
    @Environment(MusicPlayer.self) private var music
    @AppStorage(Preferences.enableMediaManagement) private var showsManagement

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
        return target.item.menuEntries(
            state: state,
            source: source,
            canGoTo: stack != nil,
            // Known for item page rows and library grids; Home's cards don't ask.
            canDelete: showsManagement && target.details.canDelete == true,
        )
    }

    private func perform(_ entry: ItemMenuEntry, on target: MenuTarget) {
        switch entry {
        case .goTo:
            stack?.path.append(target.item)
        case let .goToSeries(series):
            stack?.path.append(series)
        case .play where target.item.playsAsQueue:
            Task { await actions.playQueue(target, shuffled: false, given: given, browse: browse, music: music) }
        case .shuffle:
            Task { await actions.playQueue(target, shuffled: true, given: given, browse: browse, music: music) }
        case .play, .restart:
            Task { await actions.play(target, resuming: false, given: given, browse: browse) }
        case .resume:
            Task { await actions.play(target, resuming: true, given: given, browse: browse) }
        case .addToPlaylist:
            actions.playlistItem = target.item
        case .delete:
            actions.askToDelete(target.details)
        case .removeFromContinueWatching, .removeFromNextUp, .setPlayed, .setFavorite:
            change(entry, on: target)
        }
    }

    /// The entries that change the user's state with the item.
    private func change(_ entry: ItemMenuEntry, on target: MenuTarget) {
        switch entry {
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
        default:
            break
        }
    }
}
