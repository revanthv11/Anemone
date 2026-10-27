import AnemoneJellyfin
import CoreMedia
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

    /// From the server's description of the version playing. `nil` without a frame rate, when
    /// Wholphin doesn't switch either.
    ///
    /// A transcode keeps the frame rate, but the server tone-maps HDR when it re-encodes to
    /// H.264, its usual choice, so it counts as SDR. Dolby Vision counts as its base layer when
    /// this Apple TV can't decode Dolby Vision, as AVPlayer then shows that layer.
    public init?(video: MediaVersion.Video, method: PlaybackMethod, decoders: VideoDecoders = .current) {
        guard let frameRate = video.frameRate, frameRate.isFinite, frameRate > 0 else { return nil }
        let width = Int32(clamping: video.width ?? 1920)
        let height = Int32(clamping: video.height ?? 1080)
        let isTranscode = method == .transcode
        let range = isTranscode ? .sdr : Self.dynamicRange(video.range ?? .sdr, dolbyVision: decoders.dolbyVision)
        self.init(
            frameRate: frameRate,
            dynamicRange: range,
            codec: isTranscode ? kCMVideoCodecType_H264 : Self.codec(video.codec, range: range),
            width: width,
            height: height,
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
