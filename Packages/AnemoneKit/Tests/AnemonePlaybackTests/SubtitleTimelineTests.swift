@testable import AnemonePlayback
import Testing

/// Finding what shows at a moment, during playback and after seeks.
struct SubtitleTimelineTests {
    private func cue(_ text: String, _ start: Double, _ end: Double) -> SubtitleCue {
        SubtitleCue(
            start: .milliseconds(Int(start * 1000)),
            end: .milliseconds(Int(end * 1000)),
            lines: [SubtitleLine([SubtitleSpan(text)])],
        )
    }

    private func texts(_ timeline: SubtitleTimeline, at seconds: Double) -> [String] {
        timeline.cues(at: .milliseconds(Int(seconds * 1000))).map(\.text)
    }

    @Test func `a cue shows from its start until just before its end`() {
        let timeline = SubtitleTimeline([cue("one", 2, 4), cue("two", 4, 6)])

        #expect(texts(timeline, at: 1.999).isEmpty)
        #expect(texts(timeline, at: 2) == ["one"])
        #expect(texts(timeline, at: 3.999) == ["one"])
        #expect(texts(timeline, at: 4) == ["two"])
        #expect(texts(timeline, at: 6).isEmpty)
        #expect(texts(timeline, at: 0).isEmpty)
    }

    @Test func `overlapping cues all show, oldest first, however the file orders them`() {
        let timeline = SubtitleTimeline([
            cue("long sign", 1, 20),
            cue("late", 10, 12),
            cue("dialogue", 5, 7),
            cue("also at five", 5, 6),
        ])

        #expect(texts(timeline, at: 5.5) == ["long sign", "dialogue", "also at five"])
        #expect(texts(timeline, at: 8) == ["long sign"])
        #expect(texts(timeline, at: 11) == ["long sign", "late"])
        #expect(timeline.cues.map(\.text) == ["long sign", "dialogue", "also at five", "late"])
    }

    @Test func `seeking anywhere finds what shows there, in a long file`() {
        let cues = (0 ..< 5000).map { cue("\($0)", Double($0) * 2, Double($0) * 2 + 1.5) }
        let timeline = SubtitleTimeline(cues.reversed())

        #expect(texts(timeline, at: 7000.2) == ["3500"])
        #expect(texts(timeline, at: 7001.7).isEmpty)
        #expect(texts(timeline, at: 3.4) == ["1"])
        #expect(texts(timeline, at: 9999) == ["4999"])
        #expect(texts(timeline, at: 20000).isEmpty)
    }

    @Test func `the next change is the next start or the first end of what shows`() {
        let timeline = SubtitleTimeline([cue("sign", 1, 20), cue("dialogue", 5, 7), cue("late", 10, 12)])

        #expect(timeline.nextChange(after: .zero) == .seconds(1))
        #expect(timeline.nextChange(after: .seconds(2)) == .seconds(5))
        #expect(timeline.nextChange(after: .seconds(5)) == .seconds(7))
        #expect(timeline.nextChange(after: .seconds(8)) == .seconds(10))
        #expect(timeline.nextChange(after: .seconds(15)) == .seconds(20))
        #expect(timeline.nextChange(after: .seconds(20)) == nil)
    }

    @Test func `cues that end before they start or have no text are left out`() {
        let empty = SubtitleCue(start: .seconds(1), end: .seconds(2), lines: [])
        let timeline = SubtitleTimeline([cue("backwards", 5, 4), empty, cue("zero", 3, 3), cue("kept", 1, 2)])

        #expect(timeline.cues.map(\.text) == ["kept"])
        #expect(!timeline.isEmpty)
        #expect(SubtitleTimeline([]).isEmpty)
        #expect(SubtitleTimeline([]).cues(at: .seconds(1)).isEmpty)
        #expect(SubtitleTimeline([]).nextChange(after: .zero) == nil)
    }
}
