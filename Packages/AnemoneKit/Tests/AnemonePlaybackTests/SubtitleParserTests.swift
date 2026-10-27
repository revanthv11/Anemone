@testable import AnemonePlayback
import Testing

/// Reading SRT and WebVTT files and their markup.
struct SubtitleParserTests {
    private func line(_ spans: SubtitleSpan...) -> SubtitleLine {
        SubtitleLine(spans)
    }

    @Test func `an SRT file's cues have their times and lines`() throws {
        let cues = SubRip.cues(in: """
        1
        00:00:02,000 --> 00:00:06,500
        English SRT · cue 1
        Second line

        2
        01:02:03,045 --> 01:02:04,100
        Later
        """)

        #expect(cues.count == 2)
        let first = try #require(cues.first)
        #expect(first.start == .seconds(2))
        #expect(first.end == .milliseconds(6500))
        #expect(first.text == "English SRT · cue 1\nSecond line")
        #expect(first.placement == .bottom)
        #expect(cues[1].start == .seconds(3723) + .milliseconds(45))
        #expect(cues[1].end == .seconds(3724) + .milliseconds(100))
    }

    @Test func `an SRT file may have Windows line endings, a byte-order mark, full stops and no blank lines`() {
        let text = "\u{FEFF}1\r\n00:00:01.5 --> 00:00:02.25\r\nOne\r\n2\r\n"
            + "00:00:03,000 --> 00:00:04,000 X1:10 X2:20\r\nTwo\r\n00:00:05,000 --> 00:00:06,000\r\n"
            + "Three\r\n42\r\n\r\n\r\n4\r\n00:07,000 --> 00:08,000\r\nFour"
        let cues = SubRip.cues(in: text)

        #expect(cues.map(\.text) == ["One", "Two", "Three\n42", "Four"])
        #expect(cues.first?.start == .milliseconds(1500))
        #expect(cues.first?.end == .milliseconds(2250))
        #expect(cues.last?.start == .seconds(7))
    }

    @Test func `cues with bad times or nothing to show are left out`() {
        let cues = SubRip.cues(in: """
        1
        00:00:05,000 --> 00:00:04,000
        Ends before it starts

        2
        00:00:06,000 --> 00:00:07,000
        {\\an8}

        3
        00:0x:08,000 --> 00:00:09,000
        Not a time

        4
        00:00:10,000 --> 00:00:11,000
        Kept
        """)

        #expect(cues.map(\.text) == ["Kept"])
    }

    @Test func `bold and italic tags become styled spans, and other tags are left out`() {
        let parsed = SubtitleMarkup.parse(
            "<i>Whispered <b>loud</b></i> <font color=\"#ff0\">yellow</font>\n<u>under</u> <I>Caps</I>",
        )

        #expect(parsed.lines == [
            line(
                SubtitleSpan("Whispered ", isItalic: true),
                SubtitleSpan("loud", isBold: true, isItalic: true),
                SubtitleSpan(" yellow"),
            ),
            line(SubtitleSpan("under "), SubtitleSpan("Caps", isItalic: true)),
        ])
    }

    @Test func `italic carries across the lines of a cue`() {
        let parsed = SubtitleMarkup.parse("<i>One\nTwo</i>\nThree")

        #expect(parsed.lines == [
            line(SubtitleSpan("One", isItalic: true)),
            line(SubtitleSpan("Two", isItalic: true)),
            line(SubtitleSpan("Three")),
        ])
    }

    @Test func `overrides from ASS set bold, italic and the top of the screen, and break lines`() {
        let parsed = SubtitleMarkup.parse("{\\an8}{\\i1}Sign{\\i0} text\\Nnext{\\b700} bold{\\b0}\\hend")

        #expect(parsed.placement == .top)
        #expect(parsed.lines == [
            line(SubtitleSpan("Sign", isItalic: true), SubtitleSpan(" text")),
            line(SubtitleSpan("next"), SubtitleSpan(" bold", isBold: true), SubtitleSpan("\u{00A0}end")),
        ])
        #expect(SubtitleMarkup.parse("{\\an2}Bottom").placement == .bottom)
    }

    @Test func `text that only looks like markup stays`() {
        let parsed = SubtitleMarkup.parse("1 < 2 and 3 > 2 {not a tag} & so on \\ back")

        #expect(parsed.lines.map(\.text) == ["1 < 2 and 3 > 2 {not a tag} & so on \\ back"])
    }

    @Test func `entities are decoded`() {
        let parsed = SubtitleMarkup.parse("Tom &amp; Jerry &lt;3 &#233;t&#xE9; &nbsp;&bogus;")

        #expect(parsed.lines.map(\.text) == ["Tom & Jerry <3 été \u{00A0}&bogus;"])
    }

    @Test func `spaces around lines and empty lines are trimmed`() {
        let parsed = SubtitleMarkup.parse("  <i> padded </i>  \n\n   \n<b></b>\nlast ")

        #expect(parsed.lines == [line(SubtitleSpan("padded", isItalic: true)), line(SubtitleSpan("last"))])
    }

    @Test func `a WebVTT file skips its header, notes and styles, and reads identifiers and settings`() throws {
        let cues = WebVTT.cues(in: """
        WEBVTT - Fixture
        Kind: captions

        STYLE
        ::cue { color: yellow }

        NOTE This is a comment
        spanning lines

        intro
        00:01.000 --> 00:04.000 align:center
        <v Roger>Hello <c.loud>there</c></v>

        00:00:05.250 --> 00:00:07.000 line:0 position:50%
        <i>Sign</i> &amp; song

        00:08.000 --> 00:09.000 line:85%
        Bottom <00:08.500>karaoke<ruby>漢<rt>kan</rt></ruby>

        00:10.000 --> 00:11.000 line:-1
        Last line
        """)

        #expect(cues.map(\.text) == ["Hello there", "Sign & song", "Bottom karaoke漢", "Last line"])
        #expect(cues.map(\.placement) == [.bottom, .top, .bottom, .bottom])
        let first = try #require(cues.first)
        #expect(first.start == .seconds(1))
        #expect(first.end == .seconds(4))
        #expect(cues[1].start == .milliseconds(5250))
        #expect(cues[1].lines == [line(SubtitleSpan("Sign", isItalic: true), SubtitleSpan(" & song"))])
        #expect(WebVTT.cues(in: "WEBVTT\n\n00:01.000 --> 00:02.000 line:10%\nTop").first?.placement == .top)
    }

    @Test func `a file is read as WebVTT when it says so or starts like one`() {
        let vtt = "WEBVTT\n\n00:01.000 --> 00:02.000\nOne"
        let srt = "1\n00:00:01,000 --> 00:00:02,000\nOne"

        #expect(SubtitleTimeline(parsing: vtt, format: .srt).cues.map(\.text) == ["One"])
        #expect(SubtitleTimeline(parsing: vtt, format: .vtt).cues.map(\.text) == ["One"])
        #expect(SubtitleTimeline(parsing: srt, format: .srt).cues.map(\.text) == ["One"])
        #expect(SubtitleText.timestamp("1:02:03.4") == .seconds(3723) + .milliseconds(400))
        #expect(SubtitleText.timestamp("02:03") == .seconds(123))
        #expect(SubtitleText.timestamp("-1:00.000") == nil)
        #expect(SubtitleText.timestamp("1:2:3:4") == nil)
    }
}
