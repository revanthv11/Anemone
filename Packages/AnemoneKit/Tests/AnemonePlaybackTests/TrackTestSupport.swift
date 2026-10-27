import AnemoneCore
import AnemoneJellyfin
@testable import AnemonePlayback
import Foundation
import JellyfinAPI
import QuartzCore
import Synchronization

/// An engine whose audio and subtitle tracks the test sets, and that records what's selected.
@MainActor
final class TrackEngine: PlayerEngine {
    private(set) var loads: [(url: URL, position: Duration?)] = []
    var currentTime = Duration.zero
    var duration: Duration? = .seconds(120)
    var rate: Float = 1
    /// Each kind's tracks, as the player lists them.
    var options: [PlayerTrack.Kind: [PlayerTrack]] = [
        .subtitle: (0 ..< 4)
            .map { PlayerTrack(id: $0, kind: .subtitle, title: "\($0)", language: nil, isSelected: false) },
    ]
    /// The last selection of each kind: `.some(nil)` for subtitles turned off.
    private(set) var selected: [PlayerTrack.Kind: Int?] = [:]
    /// Every subtitle selection, in order; `nil` turns them off.
    private(set) var subtitleSelections: [Int?] = []
    private var events: AsyncStream<PlayerEvent>.Continuation?

    var deviceProfile: DeviceProfile {
        DeviceProfile(name: "Tracks")
    }

    var videoOutput: PlayerVideoOutput {
        .layer(CALayer())
    }

    func load(_ url: URL, from position: Duration?, metadata _: PlaybackMetadata) -> AsyncStream<PlayerEvent> {
        events?.finish()
        let (stream, events) = AsyncStream.makeStream(of: PlayerEvent.self)
        self.events = events
        loads.append((url, position))
        events.yield(.status(.paused))
        // A reload plays on by itself once it's ready, as AVPlayer does.
        if loads.count > 1 {
            events.yield(.ready)
        }
        return stream
    }

    func send(_ event: PlayerEvent) {
        events?.yield(event)
    }

    func play() {
        send(.status(.playing))
    }

    func pause() {
        send(.status(.paused))
    }

    func stop() {
        events?.finish()
        events = nil
    }

    func seek(to position: Duration) async -> Bool {
        currentTime = position
        return true
    }

    func tracks(_ kind: PlayerTrack.Kind) async -> [PlayerTrack] {
        (options[kind] ?? []).map { option in
            PlayerTrack(
                id: option.id,
                kind: kind,
                title: option.title,
                language: option.language,
                isSelected: selected[kind].map { $0 == option.id } ?? option.isSelected,
            )
        }
    }

    func select(_ track: PlayerTrack?, _ kind: PlayerTrack.Kind) async {
        selected[kind] = .some(track?.id)
        if kind == .subtitle {
            subtitleSelections.append(track?.id)
        }
    }
}

/// The requests for a stream a test's player made, once its features prepared them.
final class StreamRequestLog: Sendable {
    private let requests = Mutex<[StreamRequest]>([])

    var sent: [StreamRequest] {
        requests.withLock(\.self)
    }

    /// The tracks each request asked for.
    var all: [TrackRequest?] {
        sent.map(\.tracks)
    }

    func append(_ request: StreamRequest) {
        requests.withLock { $0.append(request) }
    }
}

extension StreamRequest {
    /// The tracks asked for, as `TrackSelection` puts them in; `nil` when nothing chose any.
    var tracks: TrackRequest? {
        guard audioStreamIndex != nil || subtitleStreamIndex != nil else { return nil }
        return TrackRequest(
            mediaSourceID: mediaSourceID,
            audioIndex: audioStreamIndex,
            subtitleIndex: subtitleStreamIndex.flatMap { $0 < 0 ? nil : $0 },
            // The test engines' profiles burn nothing in themselves.
            burnsInSubtitles: profile.subtitleProfiles?.contains { $0.method == .encode } == true,
        )
    }
}

extension [String] {
    /// The events right after `event`, leaving out positions and the next start.
    func after(_ event: String) -> [String] {
        Array(drop { $0 != event }.dropFirst().filter { $0 != "position" && !$0.hasPrefix("started") })
    }
}

extension ProfileTrackSettings {
    static let english = ProfileTrackSettings(audioLanguage: "eng", subtitleLanguage: "eng", subtitleMode: .default)
}

extension [MediaTrack] {
    /// The fixture's "Anemone Multi Track" file.
    static let multiTrack = [
        MediaTrack(index: 1, kind: .audio, language: "eng", codec: "aac", channels: 2, isDefault: true),
        MediaTrack(index: 2, kind: .audio, language: "fre", codec: "ac3", channels: 6),
        MediaTrack(index: 3, kind: .audio, language: "jpn", codec: "flac", channels: 2),
        MediaTrack(
            index: 4,
            kind: .subtitle,
            language: "eng",
            displayTitle: "English - SUBRIP",
            codec: "subrip",
            isDefault: true,
        ),
        MediaTrack(index: 5, kind: .subtitle, language: "eng", codec: "subrip", isForced: true),
        MediaTrack(
            index: 6,
            kind: .subtitle,
            language: "eng",
            displayTitle: "English SDH - SUBRIP",
            codec: "subrip",
            isHearingImpaired: true,
        ),
        MediaTrack(index: 7, kind: .subtitle, language: "spa", codec: "ass"),
        MediaTrack(index: 8, kind: .subtitle, language: "ger", codec: "PGSSUB", isText: false),
        MediaTrack(index: 9, kind: .subtitle, language: "fre", codec: "dvdsub", isText: false),
    ]

    /// A "Fixture Show" episode.
    static let episode = [
        MediaTrack(index: 1, kind: .audio, language: "eng", codec: "aac", isDefault: true),
        MediaTrack(index: 2, kind: .audio, language: "jpn", codec: "aac"),
        MediaTrack(index: 3, kind: .subtitle, language: "eng", codec: "subrip"),
        MediaTrack(index: 4, kind: .subtitle, language: "spa", codec: "subrip"),
    ]

    /// An episode with forced subtitles for each audio language.
    static let forcedEpisode = [
        MediaTrack(index: 1, kind: .audio, language: "eng", codec: "aac", isDefault: true),
        MediaTrack(index: 2, kind: .audio, language: "jpn", codec: "aac"),
        MediaTrack(index: 3, kind: .subtitle, language: "eng", codec: "subrip", isForced: true),
        MediaTrack(index: 4, kind: .subtitle, language: "jpn", codec: "subrip", isForced: true),
        MediaTrack(index: 5, kind: .subtitle, language: "eng", codec: "subrip"),
    ]

    /// The tracks of a test item: episodes start with "e", episodes with forced subtitles with
    /// "f", and anything else has the multi-track file.
    static func fixture(for itemID: String) -> Self {
        if itemID.hasPrefix("e") {
            .episode
        } else if itemID.hasPrefix("f") {
            .forcedEpisode
        } else {
            .multiTrack
        }
    }
}

extension PlaybackStream {
    /// What Jellyfin sends for `request`: HLS in which text subtitles come in the playlist,
    /// unless subtitles are burned in.
    static func hls(_ itemID: String, _ request: TrackRequest?, method: PlaybackMethod) -> PlaybackStream {
        let source: [MediaTrack] = .fixture(for: itemID)
        let burnsIn = request.map { request in
            request.burnsInSubtitles || source.contains { $0.index == request.subtitleIndex && !$0.isText }
        } ?? false
        let tracks = source.map { track in
            var track = track
            if track.kind == .subtitle {
                track.delivery = switch method {
                case .directPlay: track.isText ? .embedded : .burnedIn
                default: !track.isText || burnsIn ? .burnedIn : .hls
                }
            }
            return track
        }
        return PlaybackStream(
            itemID: itemID,
            url: URL(filePath: "/\(itemID)/\(request?.audioIndex ?? 0)/\(request?.subtitleStreamIndex ?? 0)"),
            method: method,
            playSessionID: "ps",
            mediaSourceID: itemID,
            audioStreamIndex: request?.audioIndex,
            subtitleStreamIndex: request?.subtitleStreamIndex,
            tracks: tracks,
        )
    }
}
