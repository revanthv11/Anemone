import AnemoneCore

/// More of Wholphin's cases.
extension StreamChoiceSubtitleTests {
    static let onlyForcedCases: [Case] = [
        Case(expected: nil, mode: .onlyForced, subtitles: [sub(0, "eng"), sub(1, "spa")]),
        Case(expected: 1, mode: .onlyForced, subtitles: [sub(0, "eng"), sub(1, "spa")], item: .track(index: 1)),
        Case(
            expected: 0,
            mode: .onlyForced,
            subtitles: [sub(0, "eng"), sub(1, "spa")],
            remembered: [remembered(subtitle: "eng")],
        ),
        Case(
            expected: nil,
            mode: .onlyForced,
            subtitles: [sub(0, "eng"), sub(1, "spa")],
            remembered: [remembered(.disabled)],
        ),
        Case(expected: 0, mode: .onlyForced, subtitles: [sub(0, "eng", f: true), sub(1, "spa")]),
        Case(expected: nil, mode: .onlyForced, subtitles: [sub(0, "eng"), sub(1, "spa", f: true)]),
        Case(expected: 1, mode: .onlyForced, profileSubtitle: nil, subtitles: [sub(0, "eng"), sub(1, "spa", f: true)]),
        Case(
            expected: 0,
            mode: SubtitleMode.none,
            profileSubtitle: nil,
            subtitles: [sub(0, "eng", f: true), sub(1, "spa")],
            remembered: [remembered(.onlyForced)],
        ),
        Case(
            expected: 0,
            mode: .default,
            profileSubtitle: nil,
            subtitles: [sub(0, "eng", f: true), sub(1, "spa", f: true)],
            remembered: [remembered(.onlyForced)],
        ),
        Case(
            expected: 0,
            mode: .default,
            subtitles: [sub(0, "eng", f: true), sub(1, "spa")],
            remembered: [remembered(.onlyForced)],
        ),
        Case(
            expected: nil,
            mode: SubtitleMode.none,
            profileSubtitle: nil,
            subtitles: [sub(0, "eng"), sub(1, "spa")],
            remembered: [remembered(.onlyForced)],
        ),
    ]

    static let severalChoiceCases: [Case] = [
        Case(expected: 1, mode: .always, subtitles: [sub(0, "eng", d: true, f: true), sub(1, "eng"), sub(2, "eng")]),
        Case(expected: 2, mode: .always, subtitles: [sub(0, "eng", f: true), sub(1, "eng"), sub(2, "eng", d: true)]),
        Case(
            expected: 0,
            mode: .smart,
            profileAudio: nil,
            subtitles: [sub(0, "eng", f: true), sub(1, "eng"), sub(2, "eng", d: true)],
        ),
        Case(
            expected: 2,
            mode: .smart,
            profileAudio: nil,
            profileSubtitle: nil,
            subtitles: [sub(0, "eng", f: true), sub(1, "eng"), sub(2, "eng", d: true)],
        ),
        Case(
            expected: nil,
            mode: .smart,
            profileAudio: nil,
            profileSubtitle: "spa",
            subtitles: [sub(0, "eng", f: true), sub(1, "eng"), sub(2, "eng", d: true)],
        ),
        Case(
            expected: 2,
            mode: .smart,
            profileAudio: nil,
            audio: "spa",
            subtitles: [sub(0, "eng", d: true, f: true), sub(1, "eng"), sub(2, "eng", d: true)],
        ),
        Case(
            expected: 0,
            mode: .smart,
            subtitles: [sub(0, "eng", d: true, f: true), sub(1, "eng"), sub(2, "eng", d: true)],
        ),
        Case(
            expected: nil,
            mode: .smart,
            profileSubtitle: "spa",
            audio: "spa",
            subtitles: [sub(0, "eng", f: true), sub(1, "eng"), sub(2, "eng", d: true)],
        ),
        Case(
            expected: 0,
            mode: .smart,
            profileSubtitle: "spa",
            subtitles: [sub(0, "spa", f: true), sub(1, "spa"), sub(2, "spa", d: true)],
        ),
        Case(
            expected: 2,
            mode: .smart,
            profileAudio: "",
            profileSubtitle: "spa",
            subtitles: [sub(0, "spa", f: true), sub(1, "spa"), sub(2, "spa", d: true)],
        ),
        Case(
            expected: 2,
            mode: .default,
            profileAudio: nil,
            profileSubtitle: nil,
            subtitles: [sub(0, "eng", f: true), sub(1, "eng"), sub(2, "eng", d: true)],
        ),
    ]

    /// "Only forced" picked in the player: Wholphin's `findForcedTrack`.
    static let pickedOnlyForcedCases: [Case] = [
        Case(
            expected: 1,
            profileSubtitle: "spa",
            subtitles: [sub(0, "eng", f: true), sub(1, "spa", f: true)],
            item: .onlyForced,
        ),
        Case(
            expected: 0,
            audio: "jpn",
            subtitles: [sub(0, "eng", title: "Signs & Songs"), sub(1, "spa", f: true)],
            item: .onlyForced,
        ),
        Case(
            expected: 0,
            profileSubtitle: "spa",
            subtitles: [sub(0, "eng", f: true), sub(1, "und", f: true)],
            item: .onlyForced,
        ),
        Case(
            expected: 0,
            profileSubtitle: "fre",
            subtitles: [sub(0, "eng", title: "Signs & Songs"), sub(1, "spa", f: true)],
            item: .onlyForced,
        ),
        Case(
            expected: 0,
            profileSubtitle: nil,
            subtitles: [sub(0, "eng", title: "Signs & Songs"), sub(1, "spa", f: true)],
            item: .onlyForced,
        ),
        Case(expected: 0, profileSubtitle: nil, subtitles: [sub(0, nil, f: true), sub(1, "spa")], item: .onlyForced),
        Case(expected: 0, profileSubtitle: nil, subtitles: [sub(0, "und", f: true), sub(1, "spa")], item: .onlyForced),
        // No forced track in a language that fits: none, rather than one in the wrong language.
        Case(expected: nil, subtitles: [sub(0, "chi", f: true), sub(1, "spa", f: true)], item: .onlyForced),
    ]

    /// The app's language setting over the profile's.
    static let appSettingCases: [Case] = [
        Case(expected: 1, mode: .always, profileSubtitle: "spa", subtitles: [sub(0, "eng", d: true), sub(1, "spa")]),
        Case(
            expected: 0,
            mode: .always,
            profileSubtitle: "spa",
            subtitles: [sub(0, "eng", d: true), sub(1, "spa")],
            appSubtitle: .language("eng"),
        ),
        Case(
            expected: 1,
            mode: .always,
            profileSubtitle: "spa",
            subtitles: [sub(0, "eng", d: true), sub(1, "spa")],
            appSubtitle: .language("spa"),
        ),
        Case(
            expected: 1,
            mode: .always,
            profileSubtitle: "spa",
            subtitles: [sub(0, "eng", d: true), sub(1, "spa")],
            item: .track(index: 1),
            appSubtitle: .language("spa"),
        ),
    ]
}
