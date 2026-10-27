import AnemoneCore
import Testing

/// Picking subtitles by item, series and settings, ported case for case from Wholphin's
/// `StreamChoiceServiceTest`. Each case gives the subtitles, what the user's Jellyfin profile
/// says, and the index Wholphin expects.
struct StreamChoiceSubtitleTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let expected: Int?
        var mode: SubtitleMode?
        var profileAudio: String? = "eng"
        var profileSubtitle: String? = "eng"
        var audio: String? = "eng"
        let subtitles: [MediaTrack]
        var item: SubtitleChoice?
        var remembered: [SeriesTrackChoice] = []
        var appSubtitle = LanguageSetting.serverProfile

        var testDescription: String {
            let tracks = subtitles
                .map { "\($0.index):\($0.language ?? "-")\($0.isDefault ? "d" : "")\($0.isForced ? "f" : "")" }
            return "\(mode.map { "\($0)" } ?? "unset") \(tracks) -> \(expected.map(String.init) ?? "none")"
        }

        var preferences: TrackPreferences {
            TrackPreferences(
                audio: .serverProfile,
                subtitle: appSubtitle,
                mode: .serverProfile,
                profile: ProfileTrackSettings(
                    audioLanguage: profileAudio,
                    subtitleLanguage: profileSubtitle,
                    subtitleMode: mode ?? .default,
                ),
            )
        }
    }

    @Test(arguments: wholphinCases + defaultModeCases + smartCases)
    func `subtitles follow the item, the series and the subtitle mode`(_ test: Case) {
        check(test)
    }

    @Test(arguments: onlyForcedCases + severalChoiceCases + pickedOnlyForcedCases + appSettingCases)
    func `forced subtitles, several in one language, and the app's settings`(_ test: Case) {
        check(test)
    }

    private func check(_ test: Case) {
        let result = StreamChoice.subtitle(
            in: test.subtitles,
            audioLanguage: test.audio,
            item: test.item.map { ItemTrackChoice(itemID: "i1", mediaSourceID: nil, subtitle: $0) },
            remembered: test.remembered,
            preferences: test.preferences,
        )
        #expect(result.track?.index == test.expected)
    }
}

extension StreamChoiceSubtitleTests {
    static let wholphinCases: [Case] = [
        Case(expected: nil, mode: SubtitleMode.none, subtitles: [sub(0, "eng", d: true), sub(1, "spa")]),
        Case(
            expected: 1,
            mode: SubtitleMode.none,
            subtitles: [sub(0, "eng", d: true), sub(1, "spa")],
            remembered: [remembered(subtitle: "spa")],
        ),
        Case(expected: 0, mode: .always, subtitles: [sub(0, "eng", d: true), sub(1, "spa")]),
        Case(expected: 1, mode: .always, profileSubtitle: "spa", subtitles: [sub(0, "eng", d: true), sub(1, "spa")]),
        Case(
            expected: nil,
            mode: .always,
            subtitles: [sub(0, "eng", d: true), sub(1, "spa")],
            remembered: [remembered(.disabled)],
        ),
        Case(expected: nil, mode: .always, subtitles: [sub(0, "eng", d: true), sub(1, "spa")], item: .off),
        Case(expected: 1, mode: .always, subtitles: [sub(0, "eng", d: true, f: true), sub(1, "eng")]),
        Case(
            expected: 1,
            mode: .always,
            profileSubtitle: nil,
            subtitles: [sub(0, "eng", d: true, f: true), sub(1, "eng")],
        ),
        Case(expected: 0, mode: .smart, subtitles: [sub(0, "eng", d: true, f: true), sub(1, "eng")]),
        Case(expected: 0, mode: .onlyForced, subtitles: [sub(0, "eng", d: true, f: true), sub(1, "eng")]),
        Case(expected: nil, mode: SubtitleMode.none, subtitles: [sub(0, "eng", d: true, f: true), sub(1, "eng")]),
    ]

    static let defaultModeCases: [Case] = [
        Case(expected: 0, mode: .default, subtitles: [sub(0, "eng", d: true), sub(1, "spa")]),
        Case(expected: 0, mode: .default, profileSubtitle: nil, subtitles: [sub(0, "eng", d: true), sub(1, "spa")]),
        Case(
            expected: 0,
            mode: .default,
            profileSubtitle: nil,
            subtitles: [sub(0, "eng", d: true), sub(1, "spa", d: true)],
        ),
        Case(expected: 1, mode: .default, profileSubtitle: nil, subtitles: [sub(0, "eng"), sub(1, "spa", d: true)]),
        Case(expected: nil, mode: .default, subtitles: [sub(0, "eng"), sub(1, "spa")]),
        Case(expected: 0, mode: .default, subtitles: [sub(0, "eng", f: true), sub(1, "spa")]),
        Case(expected: 1, mode: .default, subtitles: [sub(0, "eng", d: true), sub(1, "spa")], item: .track(index: 1)),
        Case(
            expected: 1,
            mode: .default,
            subtitles: [sub(0, "eng", f: true), sub(1, "spa")],
            remembered: [remembered(subtitle: "spa")],
        ),
        Case(
            expected: 1,
            mode: .default,
            subtitles: [sub(0, "eng", d: true), sub(1, "spa")],
            remembered: [remembered(subtitle: "spa")],
        ),
        Case(
            expected: nil,
            mode: .default,
            subtitles: [sub(0, "eng", d: true), sub(1, "spa")],
            remembered: [remembered(.disabled)],
        ),
    ]

    static let smartCases: [Case] = [
        Case(expected: 0, mode: .smart, audio: nil, subtitles: [sub(0, "eng", d: true), sub(1, "spa")]),
        Case(expected: nil, mode: .smart, subtitles: [sub(0, "eng", d: true), sub(1, "spa")]),
        Case(expected: nil, mode: .smart, subtitles: [sub(0, "eng"), sub(1, "spa")]),
        Case(expected: 0, mode: .smart, audio: "spa", subtitles: [sub(0, "eng"), sub(1, "spa")]),
        Case(expected: 0, mode: .smart, subtitles: [sub(0, "eng", f: true), sub(1, "spa")]),
        Case(
            expected: 1,
            mode: .smart,
            audio: "spa",
            subtitles: [sub(0, "eng"), sub(1, "spa")],
            remembered: [remembered(subtitle: "spa")],
        ),
        Case(
            expected: nil,
            mode: .smart,
            audio: "spa",
            subtitles: [sub(0, "eng"), sub(1, "spa")],
            remembered: [remembered(.disabled)],
        ),
        Case(
            expected: 1,
            mode: .smart,
            profileAudio: "spa",
            profileSubtitle: "spa",
            subtitles: [sub(0, "eng", d: true), sub(1, "spa")],
        ),
        Case(expected: nil, mode: .smart, profileSubtitle: "spa", subtitles: [sub(0, "eng", d: true), sub(1, "spa")]),
        Case(
            expected: 1,
            mode: .smart,
            profileAudio: nil,
            profileSubtitle: "spa",
            subtitles: [sub(0, "eng"), sub(1, "spa")],
        ),
        Case(
            expected: nil,
            mode: .smart,
            profileAudio: nil,
            subtitles: [sub(0, "eng"), sub(1, "eng", d: true), sub(2, "spa")],
        ),
        Case(
            expected: nil,
            mode: .smart,
            profileAudio: nil,
            profileSubtitle: "spa",
            audio: "spa",
            subtitles: [sub(0, "eng"), sub(1, "spa")],
        ),
    ]
}
