import AnemoneJellyfin
@testable import AnemonePlayback
import CoreMedia
import Foundation
import JellyfinAPI
import Testing

/// The display mode asked for each kind of video, and when it's asked for.
@MainActor
struct DisplayCriteriaTests {
    private static let appleTV4K = VideoDecoders(hevc: true, av1: false, dolbyVision: true)
    private static let appleTVHD = VideoDecoders(hevc: false, av1: false, dolbyVision: false)

    static let film = MediaVersion.Video(
        codec: "hevc",
        width: 3840,
        height: 2160,
        frameRate: 23.976,
        range: .hdr10,
    )

    /// A stream of `video` as PlaybackInfo would offer it; a transcode's URL carries `query`.
    static func stream(
        _ video: MediaVersion.Video? = film,
        method: PlaybackMethod = .directPlay,
        query: String = "",
    ) -> PlaybackStream {
        PlaybackStream(
            itemID: "m1",
            url: URL(string: "https://jf.test/videos/m1/master.m3u8?MediaSourceId=src1&\(query)")!,
            method: method,
            video: video,
        )
    }

    private static func transcode(
        _ query: String,
        of video: MediaVersion.Video = film,
        decoders: VideoDecoders = appleTV4K,
    ) throws -> DisplayCriteria {
        try #require(DisplayCriteria(stream: stream(video, method: .transcode, query: query), decoders: decoders))
    }

    @Test func `a film asks for its frame rate and HDR`() throws {
        let criteria = try #require(DisplayCriteria(stream: Self.stream(), decoders: Self.appleTV4K))

        #expect(criteria == DisplayCriteria(
            frameRate: 23.976,
            dynamicRange: .hdr10,
            codec: kCMVideoCodecType_HEVC,
            width: 3840,
            height: 2160,
        ))
    }

    @Test(arguments: [
        (VideoRangeType.sdr, DisplayCriteria.DynamicRange.sdr, DisplayCriteria.DynamicRange.sdr),
        (.unknown, .sdr, .sdr),
        (.hdr10, .hdr10, .hdr10),
        (.hdr10Plus, .hdr10, .hdr10),
        (.hlg, .hlg, .hlg),
        (.doviWithHDR10, .dolbyVision, .hdr10),
        (.doviWithHLG, .dolbyVision, .hlg),
        (.doviWithSDR, .dolbyVision, .sdr),
        (.dovi, .dolbyVision, .sdr),
    ])
    func `dolby vision falls back to its base layer without a decoder`(
        range: VideoRangeType,
        withDecoder: DisplayCriteria.DynamicRange,
        without: DisplayCriteria.DynamicRange,
    ) {
        #expect(DisplayCriteria.dynamicRange(range, dolbyVision: true) == withDecoder)
        #expect(DisplayCriteria.dynamicRange(range, dolbyVision: false) == without)
    }

    @Test func `dolby vision is described as dolby vision`() throws {
        var video = Self.film
        video.range = .doviWithHDR10
        let stream = Self.stream(video, method: .directStream)
        let criteria = try #require(DisplayCriteria(stream: stream, decoders: Self.appleTV4K))

        #expect(criteria.codec == kCMVideoCodecType_DolbyVisionHEVC)
    }

    @Test func `a transcode that only repackages the video keeps its codec and HDR`() throws {
        let criteria = try Self.transcode(
            "VideoCodec=hevc,h264&hevc-rangetype=SDR,HDR10"
                + "&TranscodeReasons=ContainerNotSupported,AudioCodecNotSupported",
        )

        #expect(criteria.frameRate == 23.976)
        #expect(criteria.dynamicRange == .hdr10)
        #expect(criteria.codec == kCMVideoCodecType_HEVC)
    }

    @Test func `a copied dolby vision video stays dolby vision`() throws {
        var video = Self.film
        video.range = .doviWithHDR10
        let query = "VideoCodec=hevc&hevc-rangetype=SDR,HDR10,DOVIWithHDR10&TranscodeReasons=ContainerNotSupported"

        #expect(try Self.transcode(query, of: video).dynamicRange == .dolbyVision)
        #expect(try Self.transcode(query, of: video, decoders: Self.appleTVHD).dynamicRange == .hdr10)
    }

    @Test func `an encode to HEVC keeps HDR the profile takes in HEVC`() throws {
        let criteria = try Self.transcode(
            "VideoCodec=hevc,h264&hevc-rangetype=SDR,HLG,HDR10&h264-rangetype=SDR"
                + "&TranscodeReasons=ContainerBitrateExceedsLimit",
        )

        #expect(criteria.dynamicRange == .hdr10)
        #expect(criteria.codec == kCMVideoCodecType_HEVC)
    }

    @Test func `an encode keeps a dolby vision video's base layer, not dolby vision`() throws {
        var video = Self.film
        video.range = .doviWithHLG
        let criteria = try Self.transcode(
            "VideoCodec=hevc&hevc-rangetype=SDR,HLG,DOVIWithHLG&TranscodeReasons=SubtitleCodecNotSupported",
            of: video,
        )

        #expect(criteria.dynamicRange == .hlg)
        #expect(criteria.codec == kCMVideoCodecType_HEVC)
    }

    @Test func `an encode to H.264 is tone-mapped to SDR`() throws {
        let criteria = try Self.transcode(
            "VideoCodec=h264&h264-rangetype=SDR,DOVIWithSDR&TranscodeReasons=VideoCodecNotSupported",
        )

        #expect(criteria.dynamicRange == .sdr)
        #expect(criteria.codec == kCMVideoCodecType_H264)
    }

    @Test func `a range the profile doesn't take in the codec is tone-mapped`() throws {
        let criteria = try Self
            .transcode("VideoCodec=hevc&hevc-rangetype=SDR&TranscodeReasons=VideoBitrateNotSupported")

        #expect(criteria.dynamicRange == .sdr)
        #expect(criteria.codec == kCMVideoCodecType_HEVC)
    }

    @Test func `wholphin's retry, which may not copy the video, encodes it`() throws {
        let criteria = try Self.transcode(
            "AllowVideoStreamCopy=false&VideoCodec=h264,hevc&hevc-rangetype=SDR,HDR10"
                + "&TranscodeReasons=ContainerNotSupported",
        )

        #expect(criteria.dynamicRange == .sdr)
        #expect(criteria.codec == kCMVideoCodecType_H264)
    }

    @Test func `the server's own transcoding URL for a remux reads as the video copied`() throws {
        // As the demo server sends it for an MKV, its token, IDs and some options left out.
        let video = MediaVersion.Video(codec: "h264", width: 1920, height: 1080, frameRate: 24, range: .sdr)
        let criteria = try Self.transcode(
            "VideoCodec=h264&AudioCodec=aac&AudioStreamIndex=1&VideoBitrate=99808000&MaxFramerate=24"
                + "&SegmentContainer=mp4&RequireAvc=false&SubtitleMethod=Hls&h264-level=31&h264-profile=high"
                + "&h264-rangetype=SDR,DOVIWithSDR&TranscodeReasons=ContainerNotSupported",
            of: video,
        )

        #expect(criteria == DisplayCriteria(
            frameRate: 24,
            dynamicRange: .sdr,
            codec: kCMVideoCodecType_H264,
            width: 1920,
            height: 1080,
        ))
    }

    @Test func `a transcode that doesn't say what it sends counts as SDR H.264`() throws {
        let criteria = try Self.transcode("TranscodeReasons=ContainerNotSupported")

        #expect(criteria.frameRate == 23.976)
        #expect(criteria.dynamicRange == .sdr)
        #expect(criteria.codec == kCMVideoCodecType_H264)
    }

    @Test func `without the video or its frame rate, the display is left alone`() {
        var video = Self.film
        video.frameRate = nil
        #expect(DisplayCriteria(stream: Self.stream(video), decoders: Self.appleTVHD) == nil)
        video.frameRate = 0
        #expect(DisplayCriteria(stream: Self.stream(video), decoders: Self.appleTVHD) == nil)
        #expect(DisplayCriteria(stream: Self.stream(nil), decoders: Self.appleTVHD) == nil)
    }

    @Test(arguments: [
        (DisplayCriteria.DynamicRange.sdr, kCMFormatDescriptionTransferFunction_ITU_R_709_2 as String),
        (.hdr10, kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String),
        (.dolbyVision, kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String),
        (.hlg, kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String),
    ])
    func `the format description carries the dynamic range`(
        range: DisplayCriteria.DynamicRange,
        transfer: String,
    ) throws {
        let criteria = DisplayCriteria(
            frameRate: 50,
            dynamicRange: range,
            codec: kCMVideoCodecType_HEVC,
            width: 1920,
            height: 1080,
        )

        let format = try #require(criteria.formatDescription())

        let extensions = try #require(CMFormatDescriptionGetExtensions(format) as? [String: Any])
        #expect(extensions[kCMFormatDescriptionExtension_TransferFunction as String] as? String == transfer)
        let primaries = extensions[kCMFormatDescriptionExtension_ColorPrimaries as String] as? String
        let expected = range == .sdr
            ? kCMFormatDescriptionColorPrimaries_ITU_R_709_2
            : kCMFormatDescriptionColorPrimaries_ITU_R_2020
        #expect(primaries == expected as String)
        #expect(CMVideoFormatDescriptionGetDimensions(format).width == 1920)
    }
}
