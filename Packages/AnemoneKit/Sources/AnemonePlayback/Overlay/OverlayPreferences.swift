import AnemoneCore

/// Which controls the player shows.
public enum PlayerControls: String, CaseIterable, Sendable, PreferenceValue {
    /// The system player's (`AVPlayerViewController`): its transport bar, info panel and
    /// scrubbing. AVPlayer only.
    case system
    /// Anemone's own overlay, ported from Wholphin's: D-pad seeking that speeds up, trickplay
    /// thumbnails, chapters and the queue. Engines that draw their own video, such as MPV, always
    /// use it.
    case anemone
}

public extension Preferences {
    /// The system player until Anemone's overlay matches it.
    static let playerControls = Preference("playerControls", default: PlayerControls.system)
    /// How long the overlay's controls stay up without a press. Wholphin's `controllerTimeoutMs`.
    static let controllerTimeoutMs = Preference("controllerTimeoutMs", default: 5000)
    /// Shows how the stream is played, and its tracks, over the video. Wholphin's
    /// `showDebugInfo`.
    static let showDebugInfo = Preference("showDebugInfo", default: false)
}
