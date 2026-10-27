import AnemoneCore
import CoreMedia
import JellyfinAPI
import VideoToolbox

/// The hardware video decoders this device has, which decide what AVPlayer can play.
public struct VideoDecoders: Hashable, Sendable {
    public var hevc: Bool
    public var av1: Bool
    public var dolbyVision: Bool

    public init(hevc: Bool, av1: Bool, dolbyVision: Bool) {
        self.hevc = hevc
        self.av1 = av1
        self.dolbyVision = dolbyVision
    }

    /// Asks VideoToolbox. Apple TV HD has none of these.
    public static var current: Self {
        Self(
            hevc: VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC),
            av1: VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1),
            dolbyVision: VTIsHardwareDecodeSupported(kCMVideoCodecType_DolbyVisionHEVC),
        )
    }
}

/// What AVPlayer can play, described for Jellyfin, which uses it to decide between direct play,
/// direct stream and transcoding.
///
/// Wholphin builds its profile from Android's decoder list, which tvOS doesn't have. This one is
/// adapted from Swiftfin's AVPlayer profile (MPL-2.0): a fixed list per container, with HEVC,
/// AV1 and Dolby Vision offered only when the hardware decodes them.
public enum AVPlayerProfile {
    /// Wholphin's default limit, 100 Mbit/s.
    public static let defaultMaxBitrate = 100_000_000

    /// The limit the user set (Settings › Playback › Streaming and Display), which PlaybackInfo asks for.
    public static var maxBitrate: Int {
        Preferences.maxBitrate.value()
    }

    /// The profile for this device. Built once, since the decoders don't change while the app runs.
    public static let current = deviceProfile()

    public static func deviceProfile(
        decoders: VideoDecoders = .current,
        maxBitrate: Int = defaultMaxBitrate,
    ) -> DeviceProfile {
        DeviceProfile(
            codecProfiles: codecProfiles(decoders),
            directPlayProfiles: directPlayProfiles(decoders),
            maxStaticBitrate: maxBitrate,
            maxStreamingBitrate: maxBitrate,
            name: "Anemone AVPlayer",
            subtitleProfiles: subtitleProfiles,
            transcodingProfiles: transcodingProfiles(decoders),
        )
    }

    private static func directPlayProfiles(_ decoders: VideoDecoders) -> [DirectPlayProfile] {
        let pcm = ["pcm_s16le", "pcm_s16be", "pcm_s24le", "pcm_s24be"]
        var mp4Video = ["h264", "mpeg4"]
        var movVideo = ["h264", "mpeg4", "mjpeg"]
        if decoders.hevc {
            mp4Video.append("hevc")
            movVideo.append("hevc")
        }
        if decoders.av1 {
            mp4Video.append("av1")
        }
        return [
            DirectPlayProfile(
                audioCodec: list("aac", "ac3", "eac3", "alac", "flac"),
                container: list("mp4", "m4v"),
                type: .video,
                videoCodec: list(mp4Video),
            ),
            DirectPlayProfile(
                audioCodec: list(["aac", "ac3", "eac3", "alac", "mp3"] + pcm),
                container: "mov",
                type: .video,
                videoCodec: list(movVideo),
            ),
        ]
    }

    /// HLS in fragmented MP4, which AVPlayer needs for HEVC. The order of the video codecs is
    /// the server's order of preference when it has to encode.
    ///
    /// Then HLS in MPEG-TS, which the server uses only for live TV: unless a tuner allows fMP4,
    /// it sends live channels with the most compatible profile, an HLS one in TS, and without
    /// one it offers a progressive stream AVPlayer can't play. Wholphin's profiles are TS.
    private static func transcodingProfiles(_ decoders: VideoDecoders) -> [TranscodingProfile] {
        [
            TranscodingProfile(
                protocol: .hls,
                audioCodec: list("aac", "ac3", "eac3", "alac", "flac"),
                container: "mp4",
                context: .streaming,
                enableSubtitlesInManifest: true,
                isBreakOnNonKeyFrames: true,
                maxAudioChannels: "8",
                minSegments: 2,
                type: .video,
                videoCodec: list(decoders.hevc ? ["hevc", "h264"] : ["h264"]),
            ),
            TranscodingProfile(
                protocol: .hls,
                audioCodec: list("aac", "ac3", "eac3"),
                container: "ts",
                context: .streaming,
                isBreakOnNonKeyFrames: true,
                maxAudioChannels: "8",
                minSegments: 2,
                type: .video,
                videoCodec: "h264",
            ),
        ]
    }

    /// Text subtitles come as files of their own, which Anemone draws over the video
    /// (`DrawnSubtitles`), rather than as WebVTT in the HLS playlist, which AVPlayer showed 10 s
    /// late in a remuxed stream. The server converts other text formats, such as ASS, to the
    /// first of these, and burns in the ASS asked for (`TrackRequest`). MP4's own text tracks
    /// play in the file; picture subtitles are burned in.
    private static let subtitleProfiles: [SubtitleProfile] = ["srt", "subrip", "vtt", "webvtt"].map {
        SubtitleProfile(format: $0, method: .external)
    } + [
        SubtitleProfile(format: "mov_text", method: .embed),
        SubtitleProfile(format: "ttml", method: .embed),
        SubtitleProfile(format: "cc_dec", method: .embed),
    ] + ["pgssub", "dvdsub", "dvbsub", "xsub"].map { SubtitleProfile(format: $0, method: .encode) }

    private static func codecProfiles(_ decoders: VideoDecoders) -> [CodecProfile] {
        let ranges = videoRanges(decoders)
        var profiles = [
            video("h264", [
                condition(.notEquals, .isAnamorphic, "true"),
                condition(.equalsAny, .videoProfile, "high|main|baseline|constrained baseline"),
                condition(.lessThanEqual, .videoLevel, "80"),
                condition(.notEquals, .isInterlaced, "true"),
                condition(.equalsAny, .videoRangeType, rangeList([.sdr, .doviWithSDR])),
            ]),
        ]
        if decoders.hevc {
            profiles.append(video("hevc", [
                condition(.notEquals, .isAnamorphic, "true"),
                condition(.equalsAny, .videoProfile, "main|main 10"),
                condition(.lessThanEqual, .videoLevel, "175"),
                condition(.notEquals, .isInterlaced, "true"),
                condition(.equalsAny, .videoRangeType, rangeList(ranges)),
                // AVPlayer only plays HEVC in MP4 tagged hvc1 (or dvh1 for Dolby Vision). The
                // server retags it when it repackages the file.
                condition(.equalsAny, .videoCodecTag, "hvc1|dvh1", isRequired: true),
                condition(.lessThanEqual, .videoFramerate, "60", isRequired: true),
            ]))
        }
        if decoders.av1 {
            profiles.append(video("av1", [
                condition(.notEquals, .isAnamorphic, "true"),
                condition(.notEquals, .isInterlaced, "true"),
                condition(.equalsAny, .videoRangeType, rangeList(ranges)),
            ]))
        }
        return profiles
    }

    /// The dynamic ranges AVPlayer can show. HDR needs HEVC; Dolby Vision with an HDR10 or HLG
    /// base layer falls back to that layer without a Dolby Vision decoder.
    static func videoRanges(_ decoders: VideoDecoders) -> [VideoRangeType] {
        var ranges: [VideoRangeType] = [.sdr, .doviWithSDR]
        if decoders.hevc {
            ranges += [.hlg, .doviWithHLG, .hdr10, .hdr10Plus]
        }
        if decoders.hevc || decoders.dolbyVision {
            ranges += [.doviWithHDR10, .doviWithHDR10Plus, .doviWithEL, .doviWithELHDR10Plus]
        }
        if decoders.dolbyVision {
            ranges.append(.dovi)
        }
        return ranges
    }

    private static func video(_ codec: String, _ conditions: [ProfileCondition]) -> CodecProfile {
        CodecProfile(codec: codec, conditions: conditions, type: .video)
    }

    private static func condition(
        _ type: ProfileConditionType,
        _ property: ProfileConditionValue,
        _ value: String,
        isRequired: Bool = false,
    ) -> ProfileCondition {
        ProfileCondition(condition: type, isRequired: isRequired, property: property, value: value)
    }

    /// Jellyfin reads codec and container lists as comma-separated values.
    private static func list(_ values: String...) -> String {
        list(values)
    }

    private static func list(_ values: [String]) -> String {
        values.joined(separator: ",")
    }

    /// `EqualsAny` conditions separate their values with pipes.
    private static func rangeList(_ ranges: [VideoRangeType]) -> String {
        ranges.map(\.rawValue).joined(separator: "|")
    }
}

/// Wholphin's `maxBitrate` setting: the server keeps a stream under it, transcoding what's above.
public extension Preferences {
    static let maxBitrate = Preference("maxBitrate", default: AVPlayerProfile.defaultMaxBitrate)
}

public extension AVPlayerProfile {
    /// Wholphin's choices for the limit, from 500 kbit/s to 200 Mbit/s, counted in the decimal
    /// megabits Jellyfin's own clients use, as `defaultMaxBitrate` is.
    static let bitrateChoices: [Int] = [500_000, 750_000]
        + [1, 2, 3, 5, 8, 10, 15, 20, 30, 40, 50, 60, 70, 80, 90, 100, 120, 140, 160, 180, 200].map { $0 * 1_000_000 }
}
