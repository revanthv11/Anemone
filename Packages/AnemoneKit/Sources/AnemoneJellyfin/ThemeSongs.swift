import Foundation
import JellyfinAPI

/// Theme music for item pages, as Wholphin's `ThemeSongPlayer` finds and streams it.
public extension JellyfinSession {
    /// What Apple TV plays as it is. Wholphin offers Opus, MP3, AAC and FLAC; AVPlayer can't play
    /// Opus, so it's left out, and anything else comes from the server as MP3.
    static let themeSongContainers = ["mp3", "aac", "m4a|aac", "m4a|alac", "mp4|aac", "flac", "wav"]

    /// The theme songs of `itemID`: a movie's, a series' or a collection's own.
    func themeSongs(of itemID: MediaItem.ID) async throws -> [MediaItem.ID] {
        let parameters = Paths.GetThemeSongsParameters(userID: userID)
        let result = try await send(Paths.getThemeSongs(itemID: itemID, parameters: parameters))
        return (result.items ?? []).compactMap(\.id)
    }

    /// Where to stream a theme song from: the server's universal audio endpoint, as Wholphin
    /// streams it.
    func themeSongURL(for songID: MediaItem.ID) -> URL? {
        let parameters = Paths.GetUniversalAudioStreamParameters(
            container: Self.themeSongContainers,
            deviceID: client.configuration.deviceID,
            userID: userID,
        )
        let request = Paths.getUniversalAudioStream(itemID: songID, parameters: parameters)
        // AVPlayer can't add the authorization header, so the token goes in the query.
        return client.url(with: request, queryAPIKey: true)
    }

    /// One of the item's theme songs, picked at random as Wholphin does; `nil` when it has none.
    func randomThemeSongURL(of itemID: MediaItem.ID) async throws -> URL? {
        try await themeSongs(of: itemID).randomElement().flatMap(themeSongURL(for:))
    }
}
