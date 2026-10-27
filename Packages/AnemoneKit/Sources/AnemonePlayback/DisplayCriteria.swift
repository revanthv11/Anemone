import AnemoneJellyfin
import CoreMedia
import Foundation
import JellyfinAPI

/// The display mode a video would like: its frame rate and dynamic range. tvOS switches to it
/// when the user turned on Match Content (Settings › Video and Audio), which stands in for
/// Wholphin's own refresh-rate and resolution switches (`RefreshRateService`). Apple TV picks
/// the mode itself, so there's no list of modes to choose from, and resolution isn't matched.
public struct DisplayCriteria: Hashable, Sendable {
    public enum DynamicRange: Hashable, Sendable {
        case sdr
        case hdr10
        case hlg
        case dolbyVision
    }

    /// Frames per second, such as 23.976; the display picks the refresh rate that fits it.
    public var frameRate: Float
    public var dynamicRange: DynamicRange
    /// What the stream is encoded as when it reaches the player, for the format description.
    public var codec: CMVideoCodecType
    public var width: Int32
    public var height: Int32

    public init(frameRate: Float, dynamicRange: DynamicRange, codec: CMVideoCodecType, width: Int32, height: Int32) {
        self.frameRate = frameRate
        self.dynamicRange = dynamicRange
        self.codec = codec
        self.width = width
        self.height = height
    }

    /// For the stream PlaybackInfo offered, from the video it describes. `nil` without a frame
    /// rate, when Wholphin doesn't switch either.
    ///
    /// A transcode keeps the frame rate, and its codec and range are what the server's
    /// transcoding URL says it sends (`TranscodedVideo`); when the URL doesn't say, it counts as
    /// H.264 in SDR, the server's usual choice. Dolby Vision counts as its base layer when this
    /// Apple TV can't decode Dolby Vision, as AVPlayer then shows that layer.
    public init?(stream: PlaybackStream, decoders: VideoDecoders = .current) {
        guard let video = stream.video else { return nil }
        guard stream.method == .transcode else {
            self.init(video: video, codec: video.codec, range: video.range ?? .sdr, decoders: decoders)
            return
        }
        let output = TranscodedVideo(url: stream.url, source: video)
        self.init(video: video, codec: output?.codec ?? "h264", range: output?.range ?? .sdr, decoders: decoders)
    }

    init?(video: MediaVersion.Video, codec: String?, range: VideoRangeType, decoders: VideoDecoders) {
        guard let frameRate = video.frameRate, frameRate.isFinite, frameRate > 0 else { return nil }
        let dynamicRange = Self.dynamicRange(range, dolbyVision: decoders.dolbyVision)
        self.init(
            frameRate: frameRate,
            dynamicRange: dynamicRange,
            codec: Self.codec(codec, range: dynamicRange),
            width: Int32(clamping: video.width ?? 1920),
            height: Int32(clamping: video.height ?? 1080),
        )
    }

    static func dynamicRange(_ range: VideoRangeType, dolbyVision: Bool) -> DynamicRange {
        switch range {
        case .hdr10, .hdr10Plus:
            .hdr10
        case .hlg:
            .hlg
        case .dovi:
            dolbyVision ? .dolbyVision : .sdr
        case .doviWithHDR10, .doviWithHDR10Plus, .doviWithEL, .doviWithELHDR10Plus:
            dolbyVision ? .dolbyVision : .hdr10
        case .doviWithHLG:
            dolbyVision ? .dolbyVision : .hlg
        case .doviWithSDR:
            dolbyVision ? .dolbyVision : .sdr
        case .sdr, .unknown, .doviInvalid:
            .sdr
        }
    }

    private static func codec(_ name: String?, range: DynamicRange) -> CMVideoCodecType {
        if range == .dolbyVision {
            return kCMVideoCodecType_DolbyVisionHEVC
        }
        return switch name {
        case "hevc", "h265": kCMVideoCodecType_HEVC
        case "av1": kCMVideoCodecType_AV1
        default: kCMVideoCodecType_H264
        }
    }

    /// How `AVDisplayCriteria` takes the dynamic range: as the colour primaries, transfer
    /// function and matrix of a format description, BT.709 for SDR and BT.2020 with PQ or HLG for
    /// HDR.
    public func formatDescription() -> CMVideoFormatDescription? {
        let isHDR = dynamicRange != .sdr
        let transfer = switch dynamicRange {
        case .sdr: kCMFormatDescriptionTransferFunction_ITU_R_709_2
        case .hdr10, .dolbyVision: kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ
        case .hlg: kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG
        }
        let extensions = [
            kCMFormatDescriptionExtension_ColorPrimaries: isHDR
                ? kCMFormatDescriptionColorPrimaries_ITU_R_2020
                : kCMFormatDescriptionColorPrimaries_ITU_R_709_2,
            kCMFormatDescriptionExtension_TransferFunction: transfer,
            kCMFormatDescriptionExtension_YCbCrMatrix: isHDR
                ? kCMFormatDescriptionYCbCrMatrix_ITU_R_2020
                : kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2,
        ] as CFDictionary
        var description: CMVideoFormatDescription?
        let status = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: codec,
            width: width,
            height: height,
            extensions: extensions,
            formatDescriptionOut: &description,
        )
        return status == noErr ? description : nil
    }
}

/// The video a transcode sends, read from the options Jellyfin puts in its transcoding URL
/// (`StreamInfo`): `VideoCodec`, the codecs it may send in its order of preference;
/// `TranscodeReasons`, why it isn't direct playing; `AllowVideoStreamCopy`, off for Wholphin's
/// retry; and `<codec>-rangetype`, the ranges the device profile takes in each codec.
///
/// When only the container or the audio doesn't suit the player, the server copies the video,
/// HDR and all. Otherwise it encodes to the first codec, keeping an HDR10 or HLG range (a Dolby
/// Vision video's base layer) only when the profile takes it in that codec, as it does in HEVC
/// on an Apple TV 4K, and tone-mapping the rest to SDR.
struct TranscodedVideo: Equatable {
    var codec: String
    var range: VideoRangeType

    /// The reasons that leave the video as it is.
    private static let copyingReasons: Set = [
        "containernotsupported", "audiocodecnotsupported", "audioprofilenotsupported",
        "audiochannelsnotsupported", "audiosampleratenotsupported", "audiobitdepthnotsupported",
        "audiobitratenotsupported", "audioisexternal", "secondaryaudionotsupported", "unknownaudiostreaminfo",
    ]

    init(codec: String, range: VideoRangeType) {
        self.codec = codec
        self.range = range
    }

    /// `nil` when the URL doesn't name the codecs.
    init?(url: URL, source: MediaVersion.Video) {
        let options = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        // Jellyfin reads its query without regard to case.
        func list(_ name: String) -> [String] {
            let value = options.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value ?? ""
            return value.split { $0 == "," || $0 == "|" }.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        }
        let codecs = list("VideoCodec")
        guard let first = codecs.first else { return nil }
        let sourceRange = source.range ?? .sdr
        let reasons = list("TranscodeReasons")
        if let sourceCodec = source.codec?.lowercased(), codecs.contains(sourceCodec),
           list("AllowVideoStreamCopy") != ["false"],
           !reasons.isEmpty, reasons.allSatisfy(Self.copyingReasons.contains)
        {
            self.init(codec: sourceCodec, range: sourceRange)
            return
        }
        let baseLayer = Self.baseLayer(of: sourceRange)
        let keepsRange = ["hevc", "av1"].contains(first)
            && list("\(first)-rangetype").contains(baseLayer.rawValue.lowercased())
        self.init(codec: first, range: keepsRange ? baseLayer : .sdr)
    }

    /// What an encode can keep: the server writes no Dolby Vision or HDR10+ metadata.
    private static func baseLayer(of range: VideoRangeType) -> VideoRangeType {
        switch range {
        case .hdr10, .hdr10Plus, .doviWithHDR10, .doviWithHDR10Plus, .doviWithEL, .doviWithELHDR10Plus:
            .hdr10
        case .hlg, .doviWithHLG:
            .hlg
        case .sdr, .unknown, .dovi, .doviWithSDR, .doviInvalid:
            .sdr
        }
    }
}
