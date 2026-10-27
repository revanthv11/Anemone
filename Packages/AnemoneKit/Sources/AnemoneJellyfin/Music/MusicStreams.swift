import Foundation
import JellyfinAPI

public extension MusicItem {
    /// Ported from Wholphin's `MusicService.convert`, with its missing `&&` fixed: a song takes
    /// the AC3 transcode only when the setting is on and it has an audio stream with more than
    /// two channels that isn't AC3 already. Wholphin's check lost the channel count, so with the
    /// setting on, every song that wasn't AC3 was transcoded.
    static func needsAC3Transcode(_ streams: [AudioStreamInfo], prefersAC3Surround: Bool) -> Bool {
        prefersAC3Surround && streams.contains { stream in
            (stream.channels ?? 0) > 2 && stream.codec?.lowercased() != "ac3"
        }
    }
}

public extension JellyfinSession {
    /// The containers Apple TV plays as they are, with the codecs it decodes in each. Anything
    /// else comes from the server as MP3, the universal endpoint's default transcode.
    static let musicContainers = [
        "mp3", "aac", "m4a|aac", "m4a|alac", "m4b|aac", "mp4|aac", "mp4|alac", "flac", "wav", "aiff",
    ]

    /// How to fetch a song, through Jellyfin's universal audio endpoint as Wholphin does.
    ///
    /// - Parameters:
    ///   - allowsDirect: `false` forces the server's MP3 transcode, which the player falls back to
    ///     when the file itself won't play.
    ///   - prefersAC3Surround: Wholphin's experimental "Use AC3 for surround sound audio": songs
    ///     with surround audio are transcoded to 5.1 AC3. AVPlayer can't play Wholphin's
    ///     Matroska, so the AC3 comes in fragmented MP4 over HLS.
    func audioStream(
        for song: MusicItem,
        allowsDirect: Bool = true,
        prefersAC3Surround: Bool = false,
    ) -> PlaybackStream? {
        var parameters = Paths.GetUniversalAudioStreamParameters(
            deviceID: client.configuration.deviceID,
            userID: userID,
        )
        let method: PlaybackMethod
        if MusicItem.needsAC3Transcode(song.audioStreams, prefersAC3Surround: prefersAC3Surround) {
            parameters.audioCodec = "ac3"
            parameters.maxAudioChannels = 6
            parameters.transcodingAudioChannels = 6
            parameters.transcodingContainer = "mp4"
            parameters.transcodingProtocol = .hls
            method = .transcode
        } else if allowsDirect {
            parameters.container = Self.musicContainers
            method = .directPlay
        } else {
            method = .transcode
        }
        // AVPlayer can't add the authorization header, so the token goes in the query.
        let request = Paths.getUniversalAudioStream(itemID: song.id, parameters: parameters)
        guard let url = client.url(with: request, queryAPIKey: true) else { return nil }
        return PlaybackStream(itemID: song.id, url: url, method: method)
    }
}
