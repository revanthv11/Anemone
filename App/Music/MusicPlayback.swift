import AnemoneCore
import AnemoneJellyfin
import AnemonePlayback
import SwiftUI

extension View {
    /// Gives the signed-in app its music player, which plays on while the user browses, as
    /// Wholphin's `MusicService` does. It stops when the profile's session ends (switching user
    /// or signing out), as Wholphin stops music on leaving for the user list.
    func musicPlayback(session: JellyfinSession) -> some View {
        modifier(MusicPlaybackModifier(session: session))
    }

    /// Wholphin's Now Playing page, over everything until Back. The music plays on after it.
    func nowPlaying(isPresented: Binding<Bool>) -> some View {
        fullScreenCover(isPresented: isPresented) {
            NowPlayingPage()
        }
    }
}

private struct MusicPlaybackModifier: ViewModifier {
    /// Made again whenever the signed-in view is; only the first is kept, and the others never
    /// play, so dropping them does nothing.
    @State private var lifetime: MusicLifetime

    init(session: JellyfinSession) {
        _lifetime = State(initialValue: MusicLifetime(session: session))
    }

    func body(content: Content) -> some View {
        content.environment(lifetime.player)
    }
}

/// Holds the player for as long as the profile's view lives, and stops it after.
@MainActor
private final class MusicLifetime {
    let player: MusicPlayer

    init(session: JellyfinSession) {
        player = MusicPlayer(session: session)
    }

    deinit {
        Task { @MainActor [player] in
            if player.hasQueue {
                player.stop()
            }
        }
    }
}

/// Wholphin's Now Playing settings (`MusicPreferences`), with its defaults.
extension Preferences {
    static let musicShowsAlbumArt = Preference("musicShowAlbumArt", default: true)
    static let musicShowsLyrics = Preference("musicShowLyrics", default: true)
    static let musicShowsBackdrop = Preference("musicShowBackdrop", default: true)
}

extension MusicPlayer {
    /// Plays an album, artist, playlist or library, showing what went wrong in `failed`.
    func play(_ source: MusicSource, shuffled: Bool, browse: BrowseModel, failed: @escaping (String) -> Void) {
        Task {
            do {
                try await play(source, shuffled: shuffled)
            } catch {
                if let message = browse.problem(with: error, doing: "load the songs from \(browse.server.name)") {
                    failed(message)
                }
            }
        }
    }

    /// Play or Shuffle on a playlist of songs, which plays as music, as Wholphin's playlist page
    /// plays one through its `MusicService` (`PlaylistDetails`). Wholphin goes by the playlist's
    /// media type, or failing that by its items being all songs; this goes by the items, fetched
    /// here when the page hasn't loaded them yet. `false` for any other playlist, which is the
    /// video player's.
    func playPlaylist(
        _ playlist: ItemDetails,
        entries: [ItemDetails]?,
        shuffled: Bool,
        browse: BrowseModel,
        failed: @escaping (String) -> Void,
    ) async -> Bool {
        var items = entries
        if items == nil {
            let session = browse.session
            let id = playlist.id
            items = await browse.optional(attempt { try await session.playlistItems(id: id) })
        }
        guard let items, !items.isEmpty, items.allSatisfy({ $0.item.kind == .audio }) else { return false }
        play(.playlist(playlist.id), shuffled: shuffled, browse: browse, failed: failed)
        return true
    }

    /// Wholphin's instant mix: songs like the item, chosen by the server.
    func playInstantMix(from itemID: MediaItem.ID, browse: BrowseModel, failed: @escaping (String) -> Void) {
        let session = browse.session
        Task {
            do {
                try await play { try await session.instantMix(from: itemID) }
            } catch {
                if let message = browse.problem(with: error, doing: "make a mix on \(browse.server.name)") {
                    failed(message)
                }
            }
        }
    }
}
