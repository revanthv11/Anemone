@testable import AnemonePlayback
import JellyfinAPI
import Testing

/// What the AVPlayer profile offers the server on each kind of Apple TV.
struct AVPlayerProfileTests {
    private static let appleTVHD = VideoDecoders(hevc: false, av1: false, dolbyVision: false)
    private static let appleTV4K = VideoDecoders(hevc: true, av1: false, dolbyVision: true)

    @Test func `Apple TV HD is offered H.264 only`() {
        let profile = AVPlayerProfile.deviceProfile(decoders: Self.appleTVHD)

        #expect(profile.directPlayProfiles?.map(\.videoCodec) == ["h264,mpeg4", "h264,mpeg4,mjpeg"])
        #expect(profile.transcodingProfiles?.map(\.videoCodec) == ["h264"])
        #expect(profile.codecProfiles?.map(\.codec) == ["h264"])
        #expect(AVPlayerProfile.videoRanges(Self.appleTVHD) == [.sdr, .doviWithSDR])
    }

    @Test func `Apple TV 4K is offered HEVC, HDR and Dolby Vision`() {
        let profile = AVPlayerProfile.deviceProfile(decoders: Self.appleTV4K)

        #expect(profile.directPlayProfiles?.first?.videoCodec == "h264,mpeg4,hevc")
        #expect(profile.directPlayProfiles?.first?.container == "mp4,m4v")
        // The server encodes HEVC if it may, and H.264 otherwise.
        #expect(profile.transcodingProfiles?.first?.videoCodec == "hevc,h264")
        let ranges = AVPlayerProfile.videoRanges(Self.appleTV4K)
        #expect(ranges.contains(.hdr10))
        #expect(ranges.contains(.hlg))
        #expect(ranges.contains(.dovi))
    }

    @Test func `HEVC must be tagged hvc1 or dvh1 to play directly`() throws {
        let profile = AVPlayerProfile.deviceProfile(decoders: Self.appleTV4K)

        let hevc = try #require(profile.codecProfiles?.first { $0.codec == "hevc" })
        let tag = try #require(hevc.conditions?.first { $0.property == .videoCodecTag })
        #expect(tag.condition == .equalsAny)
        #expect(tag.value == "hvc1|dvh1")
        #expect(tag.isRequired == true)
    }

    @Test func `Dolby Vision without its own layer needs a Dolby Vision decoder`() {
        let hdrOnly = VideoDecoders(hevc: true, av1: false, dolbyVision: false)

        let ranges = AVPlayerProfile.videoRanges(hdrOnly)

        #expect(!ranges.contains(.dovi))
        #expect(ranges.contains(.doviWithHDR10))
    }

    @Test func `the transcode is HLS in fragmented MP4`() throws {
        let transcode = try #require(AVPlayerProfile.deviceProfile(decoders: Self.appleTVHD).transcodingProfiles?.first)

        #expect(transcode.protocol == .hls)
        #expect(transcode.container == "mp4")
        #expect(transcode.type == .video)
        #expect(transcode.context == .streaming)
    }

    @Test func `picture subtitles are burned in`() throws {
        let subtitles = try #require(AVPlayerProfile.deviceProfile(decoders: Self.appleTVHD).subtitleProfiles)

        #expect(subtitles.first { $0.format == "pgssub" }?.method == .encode)
        #expect(subtitles.first { $0.format == "vtt" }?.method == .hls)
    }

    @Test func `the bitrate limit applies to files and streams`() {
        let profile = AVPlayerProfile.deviceProfile(decoders: Self.appleTVHD, maxBitrate: 8_000_000)

        #expect(profile.maxStaticBitrate == 8_000_000)
        #expect(profile.maxStreamingBitrate == 8_000_000)
    }
}
