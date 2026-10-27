import JellyfinAPI

/// What the MPV engine can play, described for Jellyfin. Ported from Wholphin's
/// `mpvDeviceProfile`: libmpv's FFmpeg plays nearly any container and codec directly, so the
/// server only transcodes what's over the bitrate limit, into HLS in MPEG-TS.
public enum MPVProfile {
    /// Wholphin's `supportedAudioCodecs`: everything FFmpeg decodes that Jellyfin names,
    /// DTS and TrueHD included, which libmpv decodes to PCM.
    static let audioCodecs = [
        "aac", "aac_latm", "ac3", "alac", "dca", "dts", "eac3", "flac", "mlp", "mp2", "mp3", "opus",
        "pcm_alaw", "pcm_mulaw", "pcm_s16le", "pcm_s20le", "pcm_s24le", "truehd", "vorbis",
    ]

    public static func deviceProfile(maxBitrate: Int = AVPlayerProfile.defaultMaxBitrate) -> DeviceProfile {
        DeviceProfile(
            directPlayProfiles: [
                DirectPlayProfile(
                    audioCodec: list(audioCodecs + ["wav", "ogg"]),
                    container: list(
                        "asf", "avi", "hls", "m4v", "mpeg", "mpegts", "mkv", "mov", "mp4", "mpg", "ogm", "ogv",
                        "ts", "vob", "webm", "wmv", "xvid",
                    ),
                    type: .video,
                    videoCodec: list("av1", "h264", "hevc", "mpeg", "mpeg2video", "vp8", "vp9"),
                ),
            ],
            maxStaticBitrate: maxBitrate,
            maxStreamingBitrate: maxBitrate,
            name: "Anemone MPV",
            subtitleProfiles: subtitleProfiles,
            transcodingProfiles: [
                TranscodingProfile(
                    protocol: .hls,
                    audioCodec: list(audioCodecs),
                    container: "ts",
                    context: .streaming,
                    enableSubtitlesInManifest: true,
                    isCopyTimestamps: false,
                    type: .video,
                    videoCodec: list("hevc", "h264"),
                ),
            ],
        )
    }

    /// libmpv shows text subtitles, ASS with its styling, and picture subtitles itself, inside
    /// the file or beside it. Picture subtitles in a transcode are burned in.
    static let subtitleProfiles: [SubtitleProfile] = {
        let methods: [(String, [SubtitleDeliveryMethod])] = [
            ("vtt", [.embed, .external, .hls]),
            ("webvtt", [.embed, .external, .hls]),
            ("srt", [.embed, .external]),
            ("subrip", [.embed, .external]),
            ("ttml", [.embed, .external]),
            ("dvbsub", [.embed, .encode]),
            ("dvdsub", [.embed, .encode]),
            ("idx", [.embed, .encode]),
            ("pgs", [.embed, .encode]),
            ("pgssub", [.embed, .encode]),
            ("ass", [.embed, .external, .encode]),
            ("ssa", [.embed, .external, .encode]),
        ]
        return methods.flatMap { format, methods in
            methods.map { SubtitleProfile(format: format, method: $0) }
        }
    }()

    /// Jellyfin reads codec and container lists as comma-separated values.
    private static func list(_ values: String...) -> String {
        list(values)
    }

    private static func list(_ values: [String]) -> String {
        values.joined(separator: ",")
    }
}
