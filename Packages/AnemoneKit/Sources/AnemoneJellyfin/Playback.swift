import AnemoneCore
import Foundation
import Get
import JellyfinAPI

/// How the server sends an item, in Jellyfin's terms.
public enum PlaybackMethod: Hashable, Sendable {
    /// The file as it is.
    case directPlay
    /// The file's streams repackaged, usually into HLS, without re-encoding the video.
    case directStream
    /// Re-encoded by the server.
    case transcode
}

/// Why the server won't play an item.
public enum PlaybackError: Error, Equatable {
    /// The user may not play it, or may not have it transcoded.
    case notAllowed
    /// The server found no way to send it that the player can play.
    case noCompatibleStream
    /// The user is already playing as many streams as they're allowed.
    case rateLimitExceeded
    /// The server answered without anything to play.
    case nothingToPlay
}

/// An item ready to hand to a player: where to fetch it, and what the server needs to hear
/// back about it.
public struct PlaybackStream: Hashable, Sendable {
    public let itemID: MediaItem.ID
    public let url: URL
    public let method: PlaybackMethod
    public let playSessionID: String?
    public let mediaSourceID: String?
    public let liveStreamID: String?
    public let audioStreamIndex: Int?
    public let subtitleStreamIndex: Int?
    /// The source's audio and subtitle tracks, with how this stream carries each subtitle.
    public let tracks: [MediaTrack]
    /// The version's video as the server read it from the file, before any transcode; `nil` when
    /// PlaybackInfo didn't describe it.
    public let video: MediaVersion.Video?
    /// How long the version runs, as the server read it from the file (PlaybackInfo's
    /// `RunTimeTicks`); `nil` for a live stream, or when the server doesn't know.
    public let runtime: Duration?

    public init(
        itemID: MediaItem.ID,
        url: URL,
        method: PlaybackMethod,
        playSessionID: String? = nil,
        mediaSourceID: String? = nil,
        liveStreamID: String? = nil,
        audioStreamIndex: Int? = nil,
        subtitleStreamIndex: Int? = nil,
        tracks: [MediaTrack] = [],
        video: MediaVersion.Video? = nil,
        runtime: Duration? = nil,
    ) {
        self.itemID = itemID
        self.url = url
        self.method = method
        self.playSessionID = playSessionID
        self.mediaSourceID = mediaSourceID
        self.liveStreamID = liveStreamID
        self.audioStreamIndex = audioStreamIndex
        self.subtitleStreamIndex = subtitleStreamIndex
        self.tracks = tracks
        self.video = video
        self.runtime = runtime
    }
}

/// Where playback is, for reports to the server.
public struct PlaybackProgress: Hashable, Sendable {
    public var position: Duration
    public var isPaused: Bool

    public init(position: Duration, isPaused: Bool) {
        self.position = position
        self.isPaused = isPaused
    }
}

/// Starting playback and reporting on it, ported from Wholphin's `PlaybackViewModel.changeStreams`
/// and `TrackActivityPlaybackListener`.
public extension JellyfinSession {
    /// Asks the server how to play an item with a player that can play what `profile` lists.
    ///
    /// - Parameters:
    ///   - allowsDirect: `false` makes the server transcode, which Wholphin falls back to when
    ///     direct play or direct stream fails.
    ///   - mediaSourceID: the version to play; the server's first when `nil`.
    ///   - audioStreamIndex: the audio to send; the server's choice when `nil`.
    ///   - subtitleStreamIndex: the subtitles to send, -1 for none; the server's choice when `nil`.
    func playbackStream(
        for itemID: MediaItem.ID,
        profile: DeviceProfile,
        maxBitrate: Int,
        allowsDirect: Bool = true,
        mediaSourceID: String? = nil,
        audioStreamIndex: Int? = nil,
        subtitleStreamIndex: Int? = nil,
    ) async throws -> PlaybackStream {
        let response = try await playbackInfo(
            for: itemID,
            profile: profile,
            maxBitrate: maxBitrate,
            allowsDirect: allowsDirect,
            mediaSourceID: mediaSourceID,
            audioStreamIndex: audioStreamIndex,
            subtitleStreamIndex: subtitleStreamIndex,
        )
        return try stream(from: response, for: itemID)
    }

    /// Tells the server playback has begun, so it shows on its dashboard.
    func reportPlaybackStart(_ stream: PlaybackStream, at progress: PlaybackProgress) async throws {
        try await send(Paths.reportPlaybackStart(PlaybackStateInfo(stream, progress)))
    }

    /// Saves the position, so the server can offer to resume from it.
    func reportPlaybackProgress(_ stream: PlaybackStream, at progress: PlaybackProgress) async throws {
        try await send(Paths.reportPlaybackProgress(PlaybackStateInfo(stream, progress)))
    }

    /// Ends the play session. The server saves the position, marks the item watched if it's
    /// near the end, and stops any transcode.
    func reportPlaybackStopped(_ stream: PlaybackStream, at position: Duration) async throws {
        let info = PlaybackStopInfo(
            isFailed: false,
            itemID: stream.itemID,
            liveStreamID: stream.liveStreamID,
            mediaSourceID: stream.mediaSourceID,
            playSessionID: stream.playSessionID,
            positionTicks: max(position, .zero).ticks,
        )
        try await send(Paths.reportPlaybackStopped(info))
    }
}

extension JellyfinSession {
    /// The server's PlaybackInfo answer, for `playbackStream(for:…)`, which takes the parameters
    /// it describes.
    func playbackInfo(
        for itemID: MediaItem.ID,
        profile: DeviceProfile,
        maxBitrate: Int,
        allowsDirect: Bool,
        mediaSourceID: String?,
        audioStreamIndex: Int? = nil,
        subtitleStreamIndex: Int? = nil,
    ) async throws -> PlaybackInfoResponse {
        let request = PlaybackInfoDto(
            allowAudioStreamCopy: allowsDirect,
            allowVideoStreamCopy: allowsDirect,
            audioStreamIndex: audioStreamIndex,
            deviceProfile: profile,
            enableDirectPlay: allowsDirect,
            enableDirectStream: allowsDirect,
            enableTranscoding: true,
            isAlwaysBurnInSubtitleWhenTranscoding: false,
            isAutoOpenLiveStream: true,
            maxStreamingBitrate: maxBitrate,
            mediaSourceID: mediaSourceID,
            subtitleStreamIndex: subtitleStreamIndex,
            userID: userID,
        )
        return try await send(Paths.getPostedPlaybackInfo(itemID: itemID, request))
    }

    /// The stream the server offers first, or why there's none.
    func stream(from response: PlaybackInfoResponse, for itemID: MediaItem.ID) throws -> PlaybackStream {
        if let error = response.errorCode {
            throw PlaybackError(error)
        }
        guard let source = response.mediaSources?.first,
              let stream = PlaybackStream(
                  itemID: itemID,
                  source: source,
                  playSessionID: response.playSessionID,
                  client: client,
              )
        else { throw PlaybackError.nothingToPlay }
        return stream
    }
}

extension PlaybackStream {
    /// Picks the URL the way Wholphin does: the file itself when the server allows direct play,
    /// otherwise the server's HLS stream.
    init?(itemID: MediaItem.ID, source: MediaSourceInfo, playSessionID: String?, client: JellyfinClient) {
        let method: PlaybackMethod
        let url: URL?
        if source.isSupportsDirectPlay == true {
            method = .directPlay
            if let remote = source.remoteURL {
                url = remote
            } else {
                let parameters = Paths.GetVideoStreamParameters(
                    isStatic: true,
                    tag: source.eTag,
                    playSessionID: playSessionID,
                    mediaSourceID: source.id,
                    liveStreamID: source.liveStreamID,
                )
                // AVPlayer can't add the authorization header, so the token goes in the query.
                url = client.url(with: Paths.getVideoStream(itemID: itemID, parameters: parameters), queryAPIKey: true)
            }
        } else if let path = source.transcodingURL {
            method = source.isSupportsDirectStream == true ? .directStream : .transcode
            url = client.url(path: path).flatMap { Self.withAPIKey($0, token: client.accessToken) }
        } else {
            return nil
        }
        guard let url else { return nil }
        self.init(
            itemID: itemID,
            url: url,
            method: method,
            playSessionID: playSessionID,
            mediaSourceID: source.id,
            liveStreamID: source.liveStreamID,
            audioStreamIndex: source.defaultAudioStreamIndex,
            subtitleStreamIndex: source.defaultSubtitleStreamIndex,
            tracks: (source.mediaStreams ?? []).compactMap(MediaTrack.init),
            video: source.mediaStreams?.first { $0.type == .video }.map(MediaVersion.Video.init),
            runtime: source.runTimeTicks.map(Duration.init(ticks:)),
        )
    }

    /// The server puts the token in its stream URLs; this adds it when one doesn't, since every
    /// request AVPlayer makes for the playlist and its segments needs it.
    static func withAPIKey(_ url: URL, token: String?) -> URL? {
        guard let token, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        let items = components.queryItems ?? []
        guard !items.contains(where: { ["api_key", "apikey"].contains($0.name.lowercased()) }) else { return url }
        components.queryItems = items + [URLQueryItem(name: "ApiKey", value: token)]
        return components.url
    }
}

private extension MediaSourceInfo {
    /// Where a remote source, such as a .strm file, points.
    var remoteURL: URL? {
        guard isRemote == true, let url = path.flatMap(URL.init(string:)),
              ["http", "https"].contains(url.scheme?.lowercased())
        else { return nil }
        return url
    }
}

extension PlaybackError {
    init(_ code: PlaybackErrorCode) {
        self = switch code {
        case .notAllowed: .notAllowed
        case .noCompatibleStream: .noCompatibleStream
        case .rateLimitExceeded: .rateLimitExceeded
        }
    }
}

private extension PlaybackStateInfo {
    init(_ stream: PlaybackStream, _ progress: PlaybackProgress) {
        self.init(
            audioStreamIndex: stream.audioStreamIndex,
            canSeek: true,
            isMuted: false,
            isPaused: progress.isPaused,
            itemID: stream.itemID,
            liveStreamID: stream.liveStreamID,
            mediaSourceID: stream.mediaSourceID,
            playMethod: PlayMethod(stream.method),
            playSessionID: stream.playSessionID,
            playbackOrder: .default,
            positionTicks: max(progress.position, .zero).ticks,
            repeatMode: .repeatNone,
            subtitleStreamIndex: stream.subtitleStreamIndex,
        )
    }
}

private extension PlayMethod {
    init(_ method: PlaybackMethod) {
        self = switch method {
        case .directPlay: .directPlay
        case .directStream: .directStream
        case .transcode: .transcode
        }
    }
}
