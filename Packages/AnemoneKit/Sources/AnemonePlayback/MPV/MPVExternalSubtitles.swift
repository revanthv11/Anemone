import AnemoneJellyfin
import Foundation

/// Gives MPV the subtitles the server sends beside each stream (PlaybackInfo's External
/// delivery, which MPV's profile asks for): files beside the video, including ones downloaded on
/// an earlier play, and in a transcode, the file's text subtitles. Like Wholphin's MPV player,
/// which adds the stream's external subtitles once the file loads (`MpvPlayer`,
/// `MPV_EVENT_FILE_LOADED`), but all of them rather than only the chosen one, so they're listed
/// among the tracks.
@MainActor
public final class MPVExternalSubtitles: PlaybackFeature {
    /// What MPV's profile asks the server to deliver as External.
    static let formats = Set(MPVProfile.subtitleProfiles.filter { $0.method == .external }.compactMap(\.format))

    private let session: JellyfinSession

    public init(session: JellyfinSession) {
        self.session = session
    }

    public func handle(_ event: PlaybackEvent, in controller: PlaybackController) async {
        let stream: PlaybackStream
        switch event {
        case let .loaded(loaded, _): stream = loaded
        case let .reloaded(reloaded): stream = reloaded
        default: return
        }
        guard let mpv = controller.engine.mpv else { return }
        let subtitles = session.externalSubtitles(of: stream, formats: Self.formats)
        guard !subtitles.isEmpty else { return }
        // The engine drops them if another stream has replaced this one meanwhile.
        mpv.addExternalSubtitles(subtitles, toStreamFrom: stream.url)
    }
}
