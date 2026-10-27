import AnemoneCore

extension PlayerBackend: PreferenceValue {}

public extension Preferences {
    /// Which engine plays video. Wholphin's `playerBackend`, whose default, ExoPlayer, is
    /// AVPlayer here.
    static let playerBackend = Preference("playerBackend", default: PlayerBackend.avPlayer)
    /// Lets MPV decode video with VideoToolbox. Wholphin's `mpvOptions.enableHardwareDecoding`.
    static let mpvHardwareDecoding = Preference("mpvHardwareDecoding", default: true)
    /// MPV's newer renderer, libplacebo's `gpu-next`, rather than `gpu`. Wholphin's
    /// `mpvOptions.useGpuNext`, off by default as there.
    static let mpvGpuNext = Preference("mpvGpuNext", default: false)
}

/// How libmpv is set up when an MPV engine starts, from the settings above.
struct MPVOptions: Equatable {
    var hardwareDecoding: Bool
    var gpuNext: Bool

    static var current: Self {
        Self(hardwareDecoding: Preferences.mpvHardwareDecoding.value(), gpuNext: Preferences.mpvGpuNext.value())
    }

    /// Video through Vulkan on MoltenVK, as MPVKit's tvOS demo draws it; libmpv's own input and
    /// on-screen display off, since Anemone's overlay does that; and the last frame kept at
    /// the end, as AVPlayer does, for Up Next to show over. The cache sizes are Wholphin's.
    var libmpvOptions: [(String, String)] {
        [
            ("vo", gpuNext ? "gpu-next" : "gpu"),
            ("gpu-api", "vulkan"),
            ("gpu-context", "moltenvk"),
            ("hwdec", hardwareDecoding ? "videotoolbox" : "no"),
            ("keep-open", "yes"),
            ("idle", "yes"),
            ("force-window", "no"),
            ("input-default-bindings", "no"),
            ("input-vo-keyboard", "no"),
            ("osd-level", "0"),
            ("ytdl", "no"),
            ("config", "no"),
            ("load-scripts", "no"),
            ("demuxer-max-bytes", "64MiB"),
            ("demuxer-max-back-bytes", "64MiB"),
            ("video-rotate", "no"),
        ]
    }
}
