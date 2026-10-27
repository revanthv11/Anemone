import AnemoneCore
@testable import AnemonePlayback
import Foundation
import JellyfinAPI
import Testing

/// The subtitle style as libmpv takes it, how it's kept, and the MPV device profile.
struct MPVSettingsTests {
    @Test func `the default style is libmpv's own size with Wholphin's outline and margin`() {
        let properties = Dictionary(uniqueKeysWithValues: SubtitleStyle().mpvProperties)

        #expect(properties == [
            "sub-font-size": "38",
            "sub-color": "#FFFFFFFF",
            "sub-bold": "no",
            "sub-italic": "no",
            "sub-margin-y": "69",
            "sub-back-color": "#80000000",
            "sub-outline-size": "3.20",
            "sub-outline-color": "#FF000000",
            "sub-shadow-offset": "0",
            "sub-border-style": "outline-and-shadow",
        ])
    }

    @Test func `no edge means no outline, and a shadow takes the edge colour`() {
        var style = SubtitleStyle()
        style.edge = .none
        let plain = Dictionary(uniqueKeysWithValues: style.mpvProperties)
        style.edge = .shadow
        style.edgeColor = .darkGray
        style.fontOpacity = 50
        let shadowed = Dictionary(uniqueKeysWithValues: style.mpvProperties)

        #expect(plain["sub-outline-size"] == "0")
        #expect(plain["sub-shadow-offset"] == "0")
        #expect(shadowed["sub-outline-size"] == "0")
        #expect(shadowed["sub-shadow-offset"] == "4")
        #expect(shadowed["sub-shadow-color"] == "#80444444")
        #expect(shadowed["sub-color"] == "#80FFFFFF")
    }

    @Test func `backgrounds box each line or the whole cue`() {
        var style = SubtitleStyle()
        style.background = .wrap
        style.backgroundColor = .blue
        style.backgroundOpacity = 100
        let wrapped = Dictionary(uniqueKeysWithValues: style.mpvProperties)
        style.background = .boxed

        #expect(wrapped["sub-border-style"] == "opaque-box")
        #expect(wrapped["sub-back-color"] == "#FF0000FF")
        #expect(Dictionary(uniqueKeysWithValues: style.mpvProperties)["sub-border-style"] == "background-box")
    }

    @Test func `a style survives being saved, and fields it lacks keep their defaults`() throws {
        let defaults = try #require(UserDefaults(suiteName: "subtitle-style-\(UUID())"))
        var style = SubtitleStyle()
        style.fontSize = 40
        style.fontColor = .yellow
        style.isBold = true

        Preferences.subtitleStyle.set(style, in: defaults)
        defaults.set(#"{"fontSize":30}"#, forKey: Preferences.hdrSubtitleStyle.key)

        #expect(Preferences.subtitleStyle.value(in: defaults) == style)
        #expect(Preferences.hdrSubtitleStyle.value(in: defaults).fontSize == 30)
        #expect(Preferences.hdrSubtitleStyle.value(in: defaults).fontColor == .white)
        defaults.set("not JSON", forKey: Preferences.subtitleStyle.key)
        #expect(Preferences.subtitleStyle.value(in: defaults) == SubtitleStyle())
    }

    @Test func `HDR video gets the HDR style only when there is one`() {
        var hdr = SubtitleStyle()
        hdr.fontColor = .lightGray

        #expect(SubtitleStyles(standard: SubtitleStyle()).style(forHDR: true) == SubtitleStyle())
        #expect(SubtitleStyles(standard: SubtitleStyle(), hdr: hdr).style(forHDR: true) == hdr)
        #expect(SubtitleStyles(standard: SubtitleStyle(), hdr: hdr).style(forHDR: false) == SubtitleStyle())
    }

    @Test func `MPV direct-plays MKV with DTS and TrueHD, and ASS and PGS inside the file`() throws {
        let profile = MPVProfile.deviceProfile(maxBitrate: 20_000_000)
        let direct = try #require(profile.directPlayProfiles?.first)
        let subtitles = Set((profile.subtitleProfiles ?? []).map { "\($0.format ?? "") \($0.method?.rawValue ?? "")" })

        #expect(direct.container?.split(separator: ",").contains("mkv") == true)
        #expect(direct.audioCodec?.split(separator: ",").contains("dts") == true)
        #expect(direct.audioCodec?.split(separator: ",").contains("truehd") == true)
        #expect(direct.videoCodec?.split(separator: ",").contains("hevc") == true)
        #expect(subtitles.isSuperset(of: [
            "ass Embed",
            "ass External",
            "pgssub Embed",
            "pgssub Encode",
            "srt External",
        ]))
        #expect(profile.maxStreamingBitrate == 20_000_000)
        #expect(profile.transcodingProfiles?.first?.container == "ts")
    }

    @Test func `libmpv draws with Vulkan on MoltenVK and keeps the last frame at the end`() {
        let options = Dictionary(
            uniqueKeysWithValues: MPVOptions(hardwareDecoding: false, gpuNext: true).libmpvOptions,
        )

        #expect(options["vo"] == "gpu-next")
        #expect(options["gpu-context"] == "moltenvk")
        #expect(options["hwdec"] == "no")
        #expect(options["keep-open"] == "yes")
        #expect(MPVOptions(hardwareDecoding: true, gpuNext: false).libmpvOptions.first { $0.0 == "vo" }?.1 == "gpu")
    }
}
