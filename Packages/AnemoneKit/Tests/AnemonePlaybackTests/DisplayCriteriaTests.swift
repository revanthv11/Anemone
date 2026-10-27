import AnemoneJellyfin
@testable import AnemonePlayback
import CoreMedia
import JellyfinAPI
import Synchronization
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

    @Test func `a film asks for its frame rate and HDR`() throws {
        let criteria = try #require(DisplayCriteria(video: Self.film, method: .directPlay, decoders: Self.appleTV4K))

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
        let criteria = try #require(DisplayCriteria(video: video, method: .directStream, decoders: Self.appleTV4K))

        #expect(criteria.codec == kCMVideoCodecType_DolbyVisionHEVC)
    }

    @Test func `a transcode keeps the frame rate but counts as SDR`() throws {
        let criteria = try #require(DisplayCriteria(video: Self.film, method: .transcode, decoders: Self.appleTV4K))

        #expect(criteria.frameRate == 23.976)
        #expect(criteria.dynamicRange == .sdr)
        #expect(criteria.codec == kCMVideoCodecType_H264)
    }

    @Test func `without a frame rate, the display is left alone`() {
        var video = Self.film
        video.frameRate = nil
        #expect(DisplayCriteria(video: video, method: .directPlay, decoders: Self.appleTVHD) == nil)
        video.frameRate = 0
        #expect(DisplayCriteria(video: video, method: .directPlay, decoders: Self.appleTVHD) == nil)
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

/// The feature asking the display for a mode while a fake engine plays.
@MainActor
struct DisplayCriteriaMatchingTests {
    private let engine = FakeEngine()
    private let display = FakeDisplay()
    private let asked = VideoRequests()

    private func controller(
        _ entries: [PlaybackQueue.Entry] = [.item("m1")],
        usesSystemPlayer: Bool? = nil,
        video: MediaVersion.Video? = DisplayCriteriaTests.film,
    ) throws -> (PlaybackController, DisplayCriteriaMatching) {
        let display = display
        let asked = asked
        let matching = DisplayCriteriaMatching(
            loadVideo: { itemID, versionID in
                asked.append("\(itemID)/\(versionID ?? "-")")
                return video
            },
            apply: { display.requests.append($0) },
            decoders: VideoDecoders(hevc: true, av1: false, dolbyVision: true),
            resetDelay: .milliseconds(100),
        )
        matching.usesSystemPlayer = usesSystemPlayer
        let playback = try PlaybackController(
            request: PlaybackRequest(queue: #require(PlaybackQueue(entries: entries))),
            engine: engine,
            features: [matching],
            loadStream: FakeStreams().load,
        )
        return (playback, matching)
    }

    @Test func `asks for the playing version's mode, then the usual one after closing`() async throws {
        let (playback, matching) = try controller()

        await playback.start()

        #expect(await eventually { display.requests.count == 1 })
        #expect(asked.all == ["m1/src-m1"])
        #expect(display.requests.first??.frameRate == 23.976)
        #expect(display.requests.first??.dynamicRange == .hdr10)
        #expect(matching.applied != nil)

        await playback.stop()

        #expect(await eventually { display.requests.count == 2 })
        #expect(display.requests.last == .some(nil))
    }

    @Test func `the next entry in a queue doesn't switch the display back in between`() async throws {
        let (playback, _) = try controller([.item("e1"), .item("e2")])
        await playback.start()
        #expect(await eventually { display.requests.count == 1 })

        playback.playNext()

        #expect(await eventually { asked.all == ["e1/src-e1", "e2/src-e2"] })
        try await Task.sleep(for: .milliseconds(300))
        // The same mode, so nothing more to ask.
        #expect(display.requests.count == 1)
        await playback.stop()
        #expect(await eventually { display.requests.last == .some(nil) })
    }

    @Test func `the system player matches the display itself`() async throws {
        let (playback, matching) = try controller(usesSystemPlayer: true)

        await playback.start()
        try await Task.sleep(for: .milliseconds(100))
        await playback.stop()
        try await Task.sleep(for: .milliseconds(200))

        #expect(asked.all.isEmpty)
        #expect(display.requests.isEmpty)
        #expect(matching.applied == nil)
    }

    @Test func `without the video's details, the display is left alone`() async throws {
        let (playback, _) = try controller(video: nil)

        await playback.start()
        #expect(await eventually { asked.all.count == 1 })
        await playback.stop()
        try await Task.sleep(for: .milliseconds(200))

        #expect(display.requests.isEmpty)
    }
}

/// What the display was asked for.
@MainActor
final class FakeDisplay {
    var requests: [DisplayCriteria?] = []
}

/// The videos the feature asked the server about.
final class VideoRequests: Sendable {
    private let requests = Mutex<[String]>([])

    var all: [String] {
        requests.withLock(\.self)
    }

    func append(_ request: String) {
        requests.withLock { $0.append(request) }
    }
}
