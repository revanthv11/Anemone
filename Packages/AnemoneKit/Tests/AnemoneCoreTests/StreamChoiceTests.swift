import AnemoneCore
import Testing

/// Remembered season and series choices, ported from Wholphin's `TestSeriesTrackChoice`.
struct StreamChoiceSeriesTests {
    private let preferences = TrackPreferences(audioLanguage: "eng", subtitleLanguage: "eng", subtitleMode: .default)

    private func subtitle(
        _ tracks: [MediaTrack],
        item: ItemTrackChoice? = nil,
        _ remembered: [SeriesTrackChoice],
        preferences: TrackPreferences? = nil,
    ) -> TrackChoiceResult {
        StreamChoice.subtitle(
            in: tracks,
            audioLanguage: "eng",
            item: item,
            remembered: remembered,
            preferences: preferences ?? self.preferences,
        )
    }

    @Test func `subtitles turned off for the series stay off`() {
        let result = subtitle([sub(0, "eng", d: true), sub(1, "spa")], [remembered(.disabled)])
        #expect(result == TrackChoiceResult(nil, .series))
    }

    @Test func `only forced for the series finds the forced track`() {
        let result = subtitle(
            [sub(0, "eng", f: true), sub(1, "eng")],
            [remembered(.onlyForced)],
            preferences: TrackPreferences(audioLanguage: "eng", subtitleLanguage: "eng", subtitleMode: .none),
        )
        #expect(result.track?.index == 0)
        #expect(result.reason == .series)
    }

    @Test func `the first remembered choice wins`() {
        let result = subtitle(
            [sub(0, "eng", d: true), sub(1, "spa")],
            [remembered(.disabled), remembered(.disabled, parent: .season)],
        )
        #expect(result == TrackChoiceResult(nil, .series))
    }

    @Test func `the item's own choice wins over the series'`() {
        let subtitles = subtitle(
            [sub(0, "eng", d: true), sub(1, "spa")],
            item: ItemTrackChoice(itemID: "i1", mediaSourceID: nil, subtitle: .track(index: 1)),
            [remembered(.disabled), remembered(.disabled, parent: .season)],
        )
        #expect(subtitles.track?.index == 1)
        #expect(subtitles.reason == .item)

        let audio = StreamChoice.audio(
            in: [audioTrack(0, "eng", d: true), audioTrack(1, "spa")],
            item: ItemTrackChoice(itemID: "i1", mediaSourceID: nil, audioIndex: 1),
            remembered: [remembered(audio: "eng"), remembered(audio: "eng", parent: .season)],
            preferences: preferences,
        )
        #expect(audio == TrackChoiceResult(audioTrack(1, "spa"), .item))
    }

    @Test func `a season choice that fits nothing falls back to the series'`() {
        let subtitles = subtitle(
            [sub(0, "eng", d: true), sub(1, "spa")],
            item: ItemTrackChoice(itemID: "i1", mediaSourceID: nil, audioIndex: 1),
            [remembered(.onlyForced, parent: .season), remembered(subtitle: "spa")],
        )
        #expect(subtitles == TrackChoiceResult(sub(1, "spa"), .series))

        let audio = StreamChoice.audio(
            in: [audioTrack(0, "eng", d: true), audioTrack(1, "spa")],
            item: nil,
            remembered: [
                SeriesTrackChoice(parentID: "season", parent: .season, kind: .audio, activation: .onlyForced),
                remembered(audio: "spa"),
            ],
            preferences: preferences,
        )
        #expect(audio == TrackChoiceResult(audioTrack(1, "spa"), .series))
    }

    @Test func `a forced choice needs a forced track`() {
        let choice = SeriesTrackChoice(parentID: "season", parent: .season, kind: .subtitle, flags: .forced)

        #expect(subtitle([sub(0, "eng", d: true, f: true), sub(1, "spa")], [choice]) == .init(
            sub(0, "eng", d: true, f: true),
            .season,
        ))
        #expect(subtitle([sub(0, "eng"), sub(1, "spa")], [choice]).track == nil)
    }

    @Test func `an SDH choice prefers SDH, then regular subtitles over forced ones`() {
        let choice = SeriesTrackChoice(parentID: "season", parent: .season, kind: .subtitle, flags: .hearingImpaired)

        let withSDH = subtitle([sub(0, "eng", d: true, f: true), sub(1, "eng"), sub(2, "eng", sdh: true)], [choice])
        #expect(withSDH.track?.index == 2)
        #expect(withSDH.reason == .season)
        #expect(subtitle([sub(0, "eng", d: true, f: true), sub(1, "eng")], [choice]).track?.index == 1)
    }

    @Test func `with no flags the default track wins, wherever it is`() {
        let choice = SeriesTrackChoice(parentID: "season", parent: .season, kind: .subtitle)

        #expect(subtitle([sub(0, "eng", d: true), sub(1, "eng")], [choice]).track?.index == 0)
        #expect(subtitle([sub(0, "eng"), sub(1, "eng", d: true)], [choice]).track?.index == 1)
    }

    @Test func `a remembered audio choice finds the same language and channels in the next episode`() {
        let picked = audioTrack(2, "fre", channels: 6)
        let episodeOne = [audioTrack(1, "eng", d: true, channels: 2), picked]
        let choice = SeriesTrackChoice(
            parentID: "series",
            parent: .series,
            itemID: "e1",
            track: picked,
            among: episodeOne,
        )
        #expect(choice.language == "fre")
        #expect(choice.relativeIndex == 1)
        #expect(choice.channels == 6)

        // The next episode has a stereo French track too, and its streams are numbered apart.
        let episodeTwo = [
            audioTrack(3, "eng", d: true, channels: 2),
            audioTrack(4, "fra", channels: 2),
            audioTrack(5, "fre", channels: 6),
        ]
        let result = StreamChoice.audio(in: episodeTwo, item: nil, remembered: [choice], preferences: preferences)
        #expect(result == TrackChoiceResult(audioTrack(5, "fre", channels: 6), .series))
    }
}

/// Picking audio by the language settings.
struct StreamChoiceAudioTests {
    private let tracks = [
        audioTrack(1, "eng", d: true, channels: 2),
        audioTrack(2, "fre", channels: 2),
        audioTrack(3, "fre", channels: 6),
        audioTrack(4, "jpn", channels: 2),
    ]

    private func audio(_ language: String?) -> MediaTrack? {
        StreamChoice.audio(
            in: tracks,
            item: nil,
            remembered: [],
            preferences: TrackPreferences(audioLanguage: language),
        ).track
    }

    @Test func `without a preferred language the default track plays`() {
        #expect(audio(nil)?.index == 1)
    }

    @Test func `a preferred language picks its track with the most channels`() {
        #expect(audio("fre")?.index == 3)
        // However the language is spelled.
        #expect(audio("fra")?.index == 3)
        #expect(audio("fr")?.index == 3)
        #expect(audio("jpn")?.index == 4)
    }

    @Test func `a language the file doesn't have falls back to the default track`() {
        #expect(audio("ger")?.index == 1)
    }

    @Test func `a picked index the file no longer has falls through to the settings`() {
        let result = StreamChoice.audio(
            in: tracks,
            item: ItemTrackChoice(itemID: "i1", mediaSourceID: nil, audioIndex: 9),
            remembered: [],
            preferences: TrackPreferences(audioLanguage: "jpn"),
        )
        #expect(result == TrackChoiceResult(audioTrack(4, "jpn", channels: 2), .preferences))
    }
}

/// The language and subtitle settings, and how they fall back to the Jellyfin profile.
struct TrackPreferencesTests {
    private let profile = ProfileTrackSettings(audioLanguage: "jpn", subtitleLanguage: "eng", subtitleMode: .smart)

    @Test func `the app's settings default to the Jellyfin profile's`() {
        let preferences = TrackPreferences(
            audio: .serverProfile,
            subtitle: .serverProfile,
            mode: .serverProfile,
            profile: profile,
        )
        #expect(preferences == TrackPreferences(audioLanguage: "jpn", subtitleLanguage: "eng", subtitleMode: .smart))
    }

    @Test func `the app's settings win, and any language means none`() {
        let preferences = TrackPreferences(
            audio: .language("fre"),
            subtitle: .anyLanguage,
            mode: .always,
            profile: profile,
        )
        #expect(preferences == TrackPreferences(audioLanguage: "fre", subtitleLanguage: nil, subtitleMode: .always))
    }

    @Test func `a profile without settings means any language and Jellyfin's default mode`() {
        let preferences = TrackPreferences(
            audio: .serverProfile,
            subtitle: .serverProfile,
            mode: .serverProfile,
            profile: ProfileTrackSettings(audioLanguage: "", subtitleLanguage: nil),
        )
        #expect(preferences == TrackPreferences(audioLanguage: nil, subtitleLanguage: nil, subtitleMode: .default))
    }

    @Test func `language settings are stored with Wholphin's values`() {
        #expect(LanguageSetting.serverProfile.rawValue == "")
        #expect(LanguageSetting.anyLanguage.rawValue == "_any-language")
        #expect(LanguageSetting(rawValue: "fre") == .language("fre"))
        #expect(Preferences.preferredAudioLanguage.key == "preferredAudioLanguage")
        #expect(Preferences.subtitleMode.defaultValue == .serverProfile)
    }
}

/// Comparing language codes however they're spelled.
struct LanguageCodeTests {
    @Test func `the two ISO 639-2 forms and ISO 639-1 are the same language`() {
        #expect(LanguageCode.same("fre", "fra"))
        #expect(LanguageCode.same("FRE", "fr"))
        #expect(LanguageCode.same("ger", "de"))
        #expect(LanguageCode.same("eng", "en-US"))
        #expect(!LanguageCode.same("eng", "spa"))
    }

    @Test func `unknown languages never match`() {
        #expect(LanguageCode.isUnknown(nil))
        #expect(LanguageCode.isUnknown(" "))
        #expect(LanguageCode.isUnknown("und"))
        #expect(LanguageCode.isUnknown("zxx"))
        #expect(!LanguageCode.same("und", "und"))
        #expect(!LanguageCode.same(nil, nil))
        #expect(LanguageCode.sameOrUnknown("und", "eng"))
    }
}

// MARK: Test data

/// A subtitle track, like Wholphin's test helper.
func sub(
    _ index: Int,
    _ language: String?,
    d isDefault: Bool = false,
    f isForced: Bool = false,
    sdh: Bool = false,
    title: String? = nil,
) -> MediaTrack {
    MediaTrack(
        index: index,
        kind: .subtitle,
        language: language,
        title: title,
        isDefault: isDefault,
        isForced: isForced,
        isHearingImpaired: sdh,
    )
}

func audioTrack(_ index: Int, _ language: String?, d isDefault: Bool = false, channels: Int? = nil) -> MediaTrack {
    MediaTrack(index: index, kind: .audio, language: language, channels: channels, isDefault: isDefault)
}

/// A remembered subtitle choice, like Wholphin's `plc` helper.
func remembered(
    _ activation: SeriesTrackChoice.Activation,
    parent: SeriesTrackChoice.Parent = .series,
) -> SeriesTrackChoice {
    SeriesTrackChoice(parentID: "\(parent)", parent: parent, kind: .subtitle, activation: activation)
}

func remembered(subtitle language: String) -> SeriesTrackChoice {
    SeriesTrackChoice(parentID: "series", parent: .series, kind: .subtitle, language: language)
}

func remembered(audio language: String, parent: SeriesTrackChoice.Parent = .series) -> SeriesTrackChoice {
    SeriesTrackChoice(parentID: "\(parent)", parent: parent, kind: .audio, language: language)
}
