/// Which playback engine to use, mirroring Wholphin's `PlayerBackend` preference.
public enum PlayerBackend: String, CaseIterable, Codable, Sendable {
    /// AVPlayer: Dolby Vision, Atmos, AirPlay and frame-rate matching, but a narrower set of
    /// containers and codecs. Takes the place of Wholphin's ExoPlayer backend.
    case avPlayer
    /// MPV: direct-plays almost anything, including MKV, DTS, TrueHD and ASS subtitles.
    case mpv
    /// MPV, except HDR and Dolby Vision content goes to AVPlayer.
    case preferMPV
}
