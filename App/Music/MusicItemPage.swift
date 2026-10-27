import AnemoneJellyfin
import AnemonePlayback
import SwiftUI

/// The page for an album, artist or song. Albums and artists get the pages Wholphin's
/// `DestinationContent` picks. A song opens its album's page with the song focused, as Wholphin's
/// `BaseItem.destination()` sends it there; one with no album gets the item page, which is
/// Anemone's choice: Wholphin gives it a `SongDetailsPage`.
struct MusicItemPage: View {
    @Binding var details: ItemDetails

    var body: some View {
        switch details.item.kind {
        case .musicAlbum:
            AlbumPage(details: $details)
        case .musicArtist:
            ArtistPage(details: $details)
        default:
            SongPage(song: $details)
        }
    }
}

/// A song opened on its own, from Search or a row: its album's page, focused on it.
private struct SongPage: View {
    @Binding var song: ItemDetails

    @Environment(BrowseModel.self) private var browse
    @State private var album: ItemDetails?
    @State private var hasNoAlbum = false

    var body: some View {
        Group {
            if let album = Binding($album) {
                AlbumPage(details: album, focusedSongID: song.id)
            } else if hasNoAlbum {
                MoviePage(item: $song)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: song.id) {
            guard album == nil else { return }
            let session = browse.session
            let id = song.id
            let albumID = await browse.optional(attempt { try await session.musicItem(id: id) })?.albumID
            if let albumID,
               let details = await browse.optional(attempt { try await session.itemDetails(id: albumID) })
            {
                album = details
            } else {
                hasNoAlbum = true
            }
        }
    }
}

/// Plays a song opened on the item page (`MoviePage`), with what the queue needs from the
/// server, then shows Now Playing.
struct SongPlayback: ViewModifier {
    let song: ItemDetails
    @Binding var isRequested: Bool

    @Environment(BrowseModel.self) private var browse
    @Environment(MusicPlayer.self) private var player
    @State private var showsNowPlaying = false
    @State private var problem: String?

    func body(content: Content) -> some View {
        content
            .onChange(of: isRequested) { _, requested in
                guard requested else { return }
                isRequested = false
                Task { await play() }
            }
            .nowPlaying(isPresented: $showsNowPlaying)
            .alert("Something went wrong", isPresented: showsProblem) {
                Button("OK") {}
            } message: {
                Text(problem ?? "")
            }
    }

    private var showsProblem: Binding<Bool> {
        Binding { problem != nil } set: { isShown in
            if !isShown {
                problem = nil
            }
        }
    }

    private func play() async {
        let session = browse.session
        let id = song.id
        switch await attempt({ try await session.musicItem(id: id) }) {
        case let .success(item):
            player.play([item])
            showsNowPlaying = true
        case let .failure(error):
            problem = browse.problem(with: error, doing: "play \(song.item.name)")
        }
    }
}

extension View {
    /// Plays `song` through the music player whenever `isRequested` turns on.
    func songPlayback(_ song: ItemDetails, isRequested: Binding<Bool>) -> some View {
        modifier(SongPlayback(song: song, isRequested: isRequested))
    }
}
