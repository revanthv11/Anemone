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
}

/// How to show another audio or subtitle track: in the stream that's playing, which the engine
/// switches to at once, or by asking the server for another stream. Adapted from Swiftfin's
/// track index map and rebuild rules (MPL-2.0).
enum TrackSwitching {
    enum Switch: Equatable {
        /// The engine selects this track, or turns subtitles off.
        case inPlace(PlayerTrack?)
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
    ///   - burnsInStyled: whether ASS and SSA are burned in rather than shown as plain text.
    static func subtitle(
        from old: MediaTrack?,
        to new: MediaTrack?,
        in stream: PlaybackStream,
        options: [PlayerTrack],
        burnsInStyled: Bool,
    ) -> Switch {
        // Taking burned-in subtitles away takes a stream without them.
        if let old, delivery(of: old, in: stream) == .burnedIn {
            return .reload
        }
        guard let new else { return .inPlace(nil) }
        guard !needsBurnIn(new, in: stream, burnsInStyled: burnsInStyled),
              let option = playerTrack(for: new, in: stream, options: options)
        else { return .reload }
        return .inPlace(option)
    }

    /// Whether the server has to draw `track` into the video: picture subtitles, ASS and SSA
    /// when they're burned in, and whatever the server says it can only send that way.
    static func needsBurnIn(_ track: MediaTrack, in stream: PlaybackStream, burnsInStyled: Bool) -> Bool {
        track.isPicture || (burnsInStyled && track.isStyledText) || delivery(of: track, in: stream) == .burnedIn
    }

    /// The engine's track for `track`: the engine lists the stream's tracks of that kind in the
    /// server's order, so by position when the counts agree, else by name or language. Adapted
    /// from Swiftfin's `AVMediaPlayer.selectionOption`.
    static func playerTrack(for track: MediaTrack, in stream: PlaybackStream, options: [PlayerTrack]) -> PlayerTrack? {
        let listed = listed(track.kind, in: stream)
        guard let position = listed.firstIndex(where: { $0.index == track.index }) else { return nil }
        if listed.count == options.count {
            return options[position]
        }
        let named = options.filter { [track.displayTitle, track.title].contains($0.title) }
        if named.count == 1 {
            return named.first
        }
        let sameLanguage = listed.filter { LanguageCode.same($0.language, track.language) }
        let languageOptions = options.filter { LanguageCode.same($0.language, track.language) }
        return sameLanguage.count == 1 && languageOptions.count == 1 ? languageOptions.first : nil
    }

    /// The tracks of a kind that the engine lists for `stream`, in order: the file's own when
    /// it plays directly; in Jellyfin's HLS, the one audio track asked for and every text
    /// subtitle, unless the one asked for is burned in. The playlist lists text subtitles the
    /// server would only burn in, such as ASS, as well.
    static func listed(_ kind: MediaTrack.Kind, in stream: PlaybackStream) -> [MediaTrack] {
        let tracks = stream.tracks.of(kind)
        switch (kind, stream.method) {
        case (.audio, .directPlay):
            return tracks.filter { !$0.isExternal }
        case (.audio, _):
            return tracks.filter { $0.index == stream.audioStreamIndex }
        case (.subtitle, .directPlay):
            return tracks.filter { $0.delivery == .embedded || ($0.delivery == nil && !$0.isExternal) }
        case (.subtitle, _):
            let leftOut = tracks.contains { track in
                track.index == stream.subtitleStreamIndex && [.burnedIn, .dropped].contains(track.delivery)
            }
            return leftOut ? [] : tracks.filter(\.isText)
        }
    }

    /// How `stream` carries `track`, which may differ from what the track said in another stream.
    static func delivery(of track: MediaTrack, in stream: PlaybackStream) -> MediaTrack.Delivery? {
        stream.tracks.first { $0.kind == track.kind && $0.index == track.index }?.delivery ?? track.delivery
    }
}
