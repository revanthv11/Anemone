import AnemoneCore
import AnemoneJellyfin
import JellyfinAPI

/// The tracks to ask the server for when an entry loads.
struct TrackRequest: Hashable, Sendable {
    /// The version the indices belong to. The server ignores the indices without it and picks
    /// tracks itself, from what was last reported for the item.
    var mediaSourceID: String?
    var audioIndex: Int?
    /// `nil` for no subtitles.
    var subtitleIndex: Int?
    /// Whether the server is to draw the subtitles into the video, for subtitles the engine
    /// can't show as they should look.
    var burnsInSubtitles = false

    /// What PlaybackInfo takes, where -1 is none.
    var subtitleStreamIndex: Int {
        subtitleIndex ?? -1
    }

    /// Puts these tracks in a request for a stream: the version, unless the request already has
    /// the one playing, the indices, and the profile.
    func apply(to request: inout StreamRequest) {
        request.mediaSourceID = request.mediaSourceID ?? mediaSourceID
        request.audioStreamIndex = audioIndex
        request.subtitleStreamIndex = subtitleStreamIndex
        request.profile = profile(from: request.profile)
    }

    /// `profile`, or for burned-in subtitles a copy that has the server burn in every subtitle,
    /// as Swiftfin's "force subtitle burn-in" does. Otherwise the server would convert ASS to
    /// WebVTT for the HLS playlist, losing its styling and positions.
    func profile(from profile: DeviceProfile) -> DeviceProfile {
        guard burnsInSubtitles else { return profile }
        var profile = profile
        let formats = Set((profile.subtitleProfiles ?? []).compactMap(\.format)).union(["ass", "ssa"])
        profile.subtitleProfiles = formats.sorted().map { SubtitleProfile(format: $0, method: .encode) }
        return profile
    }

    /// Whether an engine with `profile` shows `track`, ASS or SSA, with its styling itself, as
    /// MPV does with libass: its profile takes the format in the file or beside it. Otherwise
    /// the server burns it in, as for AVPlayer, which would show it as plain text.
    static func showsStyled(_ track: MediaTrack, with profile: DeviceProfile) -> Bool {
        let codec = track.codec?.lowercased()
        return (profile.subtitleProfiles ?? []).contains { subtitle in
            subtitle.format == codec && [.embed, .external].contains(subtitle.method)
        }
    }
}

/// Which subtitles the engine playing shows by itself, which decides what the server burns in
/// and what Anemone draws.
enum SubtitleRendering: Hashable, Sendable {
    /// AVPlayer. Anemone draws the text subtitles the server sends as files of their own
    /// (`DrawnSubtitles`); ASS and SSA would lose their styling, and picture subtitles can't
    /// show, so the server burns them in.
    case avPlayer
    /// MPV, which shows text, ASS with its styling and picture subtitles (PGS, DVD) itself, in
    /// the file or beside it: it adds the files the server sends beside the stream to its own
    /// tracks, after the stream's (`MPVExternalSubtitles`). The server burns in only what a
    /// transcode can't carry.
    case mpv

    /// Whether Anemone draws the text subtitles the server sends as files of their own.
    var drawsFiles: Bool {
        self == .avPlayer
    }
}

/// How to show another audio or subtitle track: in the stream that's playing, which the engine
/// switches to at once, by drawing text subtitles over it, or by asking the server for another
/// stream. Adapted from Swiftfin's track index map and rebuild rules (MPL-2.0).
enum TrackSwitching {
    enum Switch: Equatable {
        /// The engine selects this track, or turns subtitles off.
        case inPlace(PlayerTrack?)
        /// Anemone draws these text subtitles itself (`DrawnSubtitles`), from a file of their own.
        case drawn(MediaTrack)
        /// The server has to send another stream.
        case reload
    }

    static func audio(_ track: MediaTrack, in stream: PlaybackStream, options: [PlayerTrack]) -> Switch {
        // Jellyfin's HLS carries only the audio it was asked for.
        guard stream.method == .directPlay, let option = playerTrack(for: track, in: stream, options: options) else {
            return .reload
        }
        return .inPlace(option)
    }

    /// - Parameters:
    ///   - old: the subtitles showing, looked up in `stream`.
    ///   - rendering: what the engine shows itself, and whether Anemone draws text subtitles sent
    ///     as files of their own, as over AVPlayer.
    static func subtitle(
        from old: MediaTrack?,
        to new: MediaTrack?,
        in stream: PlaybackStream,
        options: [PlayerTrack],
        rendering: SubtitleRendering = .avPlayer,
    ) -> Switch {
        // Taking burned-in subtitles away takes a stream without them.
        if let old, delivery(of: old, in: stream) == .burnedIn {
            return .reload
        }
        guard let new else { return .inPlace(nil) }
        guard !needsBurnIn(new, in: stream, rendering: rendering) else { return .reload }
        if rendering.drawsFiles, isSentAsFile(new, in: stream) {
            return .drawn(new)
        }
        guard let option = playerTrack(for: new, in: stream, options: options, rendering: rendering) else {
            return .reload
        }
        return .inPlace(option)
    }

    /// Whether `track` is a text subtitle that the stream doesn't carry, which the server sends
    /// as a file of its own instead (External delivery), as it does all text subtitles for
    /// AVPlayer. Anemone draws those over AVPlayer; MPV shows them itself.
    static func isSentAsFile(_ track: MediaTrack, in stream: PlaybackStream) -> Bool {
        track.kind == .subtitle && track.isText && delivery(of: track, in: stream) == .external
    }

    /// Whether the server has to draw `track` into the video: what the server says it can only
    /// send that way and, for AVPlayer, picture subtitles and ASS and SSA, which MPV shows itself.
    static func needsBurnIn(_ track: MediaTrack, in stream: PlaybackStream, rendering: SubtitleRendering) -> Bool {
        let burnedIn = delivery(of: track, in: stream) == .burnedIn
        return switch rendering {
        case .avPlayer: track.isPicture || track.isStyledText || burnedIn
        case .mpv: burnedIn
        }
    }

    /// Whether the engine can switch to `track` in `stream` without another stream, going by
    /// what the stream carries: audio in a file that plays directly, and subtitles it lists that
    /// needn't be burned in. All a live stream offers, since its tracks can't be asked for, and
    /// the server can't read a subtitle file out of a stream that hasn't ended.
    static func switchesInPlace(
        to track: MediaTrack,
        in stream: PlaybackStream,
        rendering: SubtitleRendering = .avPlayer,
    ) -> Bool {
        let carries = switch track.kind {
        case .audio: stream.method == .directPlay
        case .subtitle: !needsBurnIn(track, in: stream, rendering: rendering)
        }
        return carries && listed(track.kind, in: stream, rendering: rendering).contains { $0.index == track.index }
    }

    /// The engine's track for `track`: the engine lists the stream's tracks of that kind in the
    /// server's order, so by position when the counts agree, else by name, codec or language.
    /// Adapted from Swiftfin's `AVMediaPlayer.selectionOption`.
    ///
    /// MPV lists the subtitle files it adds after the stream's own, in the server's order, and
    /// any it's given later, such as a downloaded one, after those; before the file has opened it
    /// lists only the stream's. It says which are files, so the stream's own and the files are
    /// matched apart: a track in the file that the server sends as a file instead (MPV lists
    /// both) moves nothing in the other group, and the files go by position even with a
    /// downloaded one after them.
    static func playerTrack(
        for track: MediaTrack,
        in stream: PlaybackStream,
        options: [PlayerTrack],
        rendering: SubtitleRendering = .avPlayer,
    ) -> PlayerTrack? {
        var listed = listed(track.kind, in: stream, rendering: rendering)
        var options = options
        var amongFiles = false
        if rendering == .mpv, track.kind == .subtitle, options.allSatisfy({ $0.isExternal != nil }) {
            let isFile = { (other: MediaTrack) in delivery(of: other, in: stream) == .external }
            amongFiles = isFile(track)
            listed = listed.filter { isFile($0) == amongFiles }
            options = options.filter { $0.isExternal == amongFiles }
        }
        guard let position = listed.firstIndex(where: { $0.index == track.index }) else { return nil }
        if listed.count == options.count || (amongFiles && options.count > listed.count) {
            return options[position]
        }
        return matching(track, among: listed, options: options)
    }

    /// The one option with `track`'s name; else the one with its codec and language; else the
    /// one in its language, when it's the only one listed in it.
    private static func matching(_ track: MediaTrack, among listed: [MediaTrack], options: [PlayerTrack])
        -> PlayerTrack?
    {
        let named = options.filter { [track.displayTitle, track.title].contains($0.title) }
        if named.count == 1 {
            return named.first
        }
        if let codec = TrackCodec(track.codec) {
            let unknown = LanguageCode.isUnknown(track.language)
            let sameCodec = options.filter { option in
                let sameLanguage = unknown
                    ? LanguageCode.isUnknown(option.language)
                    : LanguageCode.same(option.language, track.language)
                return sameLanguage && TrackCodec(option.codec) == codec
            }
            if sameCodec.count == 1 {
                return sameCodec.first
            }
        }
        let languageOptions = options.filter { LanguageCode.same($0.language, track.language) }
        let sameLanguage = listed.filter { LanguageCode.same($0.language, track.language) }
        return sameLanguage.count == 1 && languageOptions.count == 1 ? languageOptions.first : nil
    }

    /// The tracks of a kind that the engine lists for `stream`, in order: the file's own when
    /// it plays directly; in Jellyfin's HLS, the one audio track asked for and every text
    /// subtitle, unless the one asked for is burned in (then the playlist has none). The playlist
    /// lists text subtitles the server would only burn in, such as ASS, as well.
    ///
    /// Over AVPlayer, which has Anemone draw the text subtitles sent as files, the playlist has
    /// none of those, nor any at all when the one asked for is one of them. MPV lists the
    /// subtitles the stream carries, by the same rule in HLS, then the files it adds
    /// (`MPVExternalSubtitles`).
    static func listed(
        _ kind: MediaTrack.Kind,
        in stream: PlaybackStream,
        rendering: SubtitleRendering = .avPlayer,
    ) -> [MediaTrack] {
        let tracks = stream.tracks.of(kind)
        let inFile = { (track: MediaTrack) in
            track.delivery == .embedded || (track.delivery == nil && !track.isExternal)
        }
        switch (kind, stream.method, rendering) {
        case (.audio, .directPlay, _):
            return tracks.filter { !$0.isExternal }
        case (.audio, _, _):
            return tracks.filter { $0.index == stream.audioStreamIndex }
        case (.subtitle, .directPlay, .mpv):
            return tracks.filter(inFile) + tracks.filter { $0.delivery == .external }
        case (.subtitle, _, .mpv):
            let carried = hasNoSubtitles(stream) ? [] : tracks.filter { $0.delivery == .hls }
            return carried + tracks.filter { $0.delivery == .external }
        case (.subtitle, .directPlay, .avPlayer):
            return tracks.filter(inFile)
        case (.subtitle, _, .avPlayer):
            return hasNoSubtitles(stream) ? [] : tracks.filter { $0.isText && $0.delivery != .external }
        }
    }

    /// Whether Jellyfin's HLS playlist for `stream` has no subtitles at all: it has them only when
    /// the ones asked for come in it, not when they're burned in, left out or sent as a file.
    private static func hasNoSubtitles(_ stream: PlaybackStream) -> Bool {
        stream.tracks.of(.subtitle).contains { track in
            track.index == stream.subtitleStreamIndex && [.burnedIn, .dropped, .external].contains(track.delivery)
        }
    }

    /// How `stream` carries `track`, which may differ from what the track said in another stream.
    static func delivery(of track: MediaTrack, in stream: PlaybackStream) -> MediaTrack.Delivery? {
        stream.tracks.first { $0.kind == track.kind && $0.index == track.index }?.delivery ?? track.delivery
    }
}

/// A codec under the names Jellyfin and libmpv give it, which differ for subtitles: `srt` and
/// `subrip`, or `pgssub` and `hdmv_pgs_subtitle`.
private struct TrackCodec: Equatable {
    let name: String

    init?(_ codec: String?) {
        guard let codec = codec?.lowercased(), !codec.isEmpty else { return nil }
        name = Self.aliases[codec] ?? codec
    }

    private static let aliases = [
        "srt": "subrip",
        "pgs": "pgssub",
        "hdmv_pgs_subtitle": "pgssub",
        "dvd_subtitle": "dvdsub",
        "vobsub": "dvdsub",
        "dvb_subtitle": "dvbsub",
        "ssa": "ass",
        "vtt": "webvtt",
        "tx3g": "mov_text",
    ]
}
