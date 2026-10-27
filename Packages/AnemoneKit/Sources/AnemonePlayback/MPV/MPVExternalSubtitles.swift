import AnemoneJellyfin
import Foundation

/// Gives MPV the subtitle files beside each stream's video, including ones downloaded on an
/// earlier play: MPV's profile has the server deliver them as External, so they aren't in the
/// stream. Like Wholphin's MPV player, which adds the stream's external subtitles once the
/// file loads (`MpvPlayer`, `MPV_EVENT_FILE_LOADED`), but all of them rather than only the
/// chosen one, so the track menus list them.
@MainActor
public final class MPVExternalSubtitles: PlaybackFeature {
    /// What MPV's profile asks the server to deliver as External.
    static let formats = Set(MPVProfile.subtitleProfiles.filter { $0.method == .external }.compactMap(\.format))

    private let session: JellyfinSession
    private var work: Task<Void, Never>?

    public init(session: JellyfinSession) {
        self.session = session
    }

    public func handle(_ event: PlaybackEvent, in controller: PlaybackController) async {
        switch event {
        case let .loaded(stream, _):
            work?.cancel()
            guard let mpv = controller.engine.mpv else { return }
            work = Task { [session] in
                guard let subtitles = try? await session.externalSubtitles(for: stream, formats: Self.formats),
                      !subtitles.isEmpty, !Task.isCancelled
                else { return }
                // The engine drops them if another stream has replaced this one meanwhile.
                mpv.addExternalSubtitles(subtitles, toStreamFrom: stream.url)
            }
        case .stopped:
            if controller.isStopped {
                work?.cancel()
            }
        default:
            break
        }
    }
}
