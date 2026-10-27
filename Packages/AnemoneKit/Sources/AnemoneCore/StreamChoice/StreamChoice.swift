import Foundation

/// Picks the audio and subtitles to play: what the user picked for the item, else what they
/// picked in another episode of the season or series, else their language and subtitle
/// settings. Ported from Wholphin's `StreamChoiceService`.
public enum StreamChoice {
    /// The audio track to play among `tracks`, an item's streams of every kind.
    ///
    /// - Parameter remembered: choices kept for the item's season and series, the season's first.
    public static func audio(
        in tracks: [MediaTrack],
        item: ItemTrackChoice?,
        remembered: [SeriesTrackChoice],
        preferences: TrackPreferences,
    ) -> TrackChoiceResult {
        let candidates = tracks.of(.audio)
        // Unlike Wholphin, an index the file no longer has falls through to the next rule.
        if let index = item?.audioIndex, let track = candidates.first(where: { $0.index == index }) {
            return TrackChoiceResult(track, .item)
        }
        if let choice = remembered.first {
            guard let scored = score(candidates, for: choice) else { return TrackChoiceResult(nil, choice.reason) }
            if let best = scored.first {
                return TrackChoiceResult(best, choice.reason)
            }
            // The choice fits none of these tracks: try the next one, then the settings.
            return audio(in: tracks, item: nil, remembered: Array(remembered.dropFirst()), preferences: preferences)
        }
        return TrackChoiceResult(preferredAudio(candidates, preferences), .preferences)
    }

    /// The subtitles to show among `tracks`, an item's streams of every kind, or `nil` for none.
    ///
    /// - Parameters:
    ///   - audioLanguage: the language of the audio that plays, which decides smart mode and
    ///     where forced subtitles are looked for.
    ///   - remembered: choices kept for the item's season and series, the season's first.
    public static func subtitle(
        in tracks: [MediaTrack],
        audioLanguage: String?,
        item: ItemTrackChoice?,
        remembered: [SeriesTrackChoice],
        preferences: TrackPreferences,
    ) -> TrackChoiceResult {
        let candidates = tracks.of(.subtitle)
        switch item?.subtitle {
        case .off:
            return TrackChoiceResult(nil, .item)
        case .onlyForced:
            let forced = forcedTrack(candidates, preferences.subtitleLanguage, audioLanguage)
            return TrackChoiceResult(forced, .item, isOnlyForced: true)
        case let .track(index):
            if let track = candidates.first(where: { $0.index == index }) {
                return TrackChoiceResult(track, .item)
            }
        case nil:
            break
        }
        return rememberedSubtitle(candidates, audioLanguage: audioLanguage, remembered[...], preferences)
            ?? TrackChoiceResult(preferredSubtitle(candidates, audioLanguage: audioLanguage, preferences), .preferences)
    }

    /// The forced subtitles that "Only forced" stands for with audio in `audioLanguage`:
    /// Wholphin's `resolveSubtitleIndex`.
    public static func onlyForced(
        in tracks: [MediaTrack],
        audioLanguage: String?,
        preferences: TrackPreferences,
    ) -> MediaTrack? {
        forcedTrack(tracks.of(.subtitle), preferences.subtitleLanguage, audioLanguage)
    }

    /// The first remembered choice that fits a track, or that turns subtitles off; `nil` when
    /// none applies.
    private static func rememberedSubtitle(
        _ candidates: [MediaTrack],
        audioLanguage: String?,
        _ remembered: ArraySlice<SeriesTrackChoice>,
        _ preferences: TrackPreferences,
    ) -> TrackChoiceResult? {
        for choice in remembered {
            switch choice.activation {
            case .disabled:
                return TrackChoiceResult(nil, choice.reason)
            case .onlyForced:
                if let forced = forcedTrack(candidates, preferences.subtitleLanguage, audioLanguage) {
                    return TrackChoiceResult(forced, choice.reason, isOnlyForced: true)
                }
            case .activated:
                if let best = score(candidates, for: choice)?.first {
                    return TrackChoiceResult(best, choice.reason)
                }
            }
        }
        return nil
    }

    /// Ranks the tracks that fit a remembered choice, best first: `nil` when the choice turned
    /// subtitles off, and empty when no track fits. Wholphin's `scoreStreams`.
    static func score(_ tracks: [MediaTrack], for choice: SeriesTrackChoice) -> [MediaTrack]? {
        guard choice.activation != .disabled else { return nil }
        let wantsForced = choice.activation == .onlyForced || choice.flags.contains(.forced)
        let fitting = tracks.filter { track in
            if wantsForced, !track.isForcedOrSigns {
                return false
            }
            if !LanguageCode.isUnknown(choice.language), !LanguageCode.same(choice.language, track.language) {
                return false
            }
            return track.kind == choice.kind
        }
        let scored = fitting.map { track in
            (track: track, score: score(track, relativeIndex: fitting.relativeIndex(of: track), for: choice))
        }
        // Equal scores keep the server's order.
        return scored.enumerated()
            .sorted { ($0.element.score, -$0.offset) > ($1.element.score, -$1.offset) }
            .map(\.element.track)
    }

    private static func score(_ track: MediaTrack, relativeIndex: Int?, for choice: SeriesTrackChoice) -> Int {
        let flags = choice.flags
        let channels = (track: track.channels ?? 0, choice: choice.channels)
        let points: [(applies: Bool, points: Int)] = [
            // An exact language beats an unknown one.
            (LanguageCode.same(choice.language, track.language), 10000),
            (track.isForced && flags.contains(.forced), 1000),
            (track.isSigns && flags.contains(.signs), 500),
            (track.isDefault && flags.contains(.isDefault), 500),
            (track.isHearingImpaired && flags.contains(.hearingImpaired), 500),
            // Someone who wants SDH would rather have regular subtitles than forced ones.
            (!track.isHearingImpaired && flags.contains(.hearingImpaired) && track.isForced, -10),
            (track.isExternal && flags.contains(.external), 100),
            (relativeIndex != nil && relativeIndex == choice.relativeIndex, 100),
            (track.title == choice.title, 10),
            (channels.choice.map { channels.track == $0 } ?? false, 100),
            (channels.choice.map { channels.track > $0 } ?? false, 50),
            // All else being equal, the default track.
            (track.isDefault, 1),
        ]
        return points.reduce(0) { $0 + ($1.applies ? $1.points : 0) }
    }

    private static func preferredAudio(_ candidates: [MediaTrack], _ preferences: TrackPreferences) -> MediaTrack? {
        guard let language = preferences.audioLanguage else {
            return candidates.first(where: \.isDefault) ?? candidates.first
        }
        // By language, then the most channels, as Wholphin sorts them.
        let sorted = candidates.enumerated().sorted { lhs, rhs in
            let left = lhs.element, right = rhs.element
            if left.language != right.language {
                return left.language == nil || (left.language ?? "") < (right.language ?? "")
            }
            if left.channels != right.channels {
                return (left.channels ?? -1) > (right.channels ?? -1)
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
        return sorted.first { LanguageCode.same($0.language, language) && $0.isDefault }
            ?? sorted.first { LanguageCode.same($0.language, language) }
            ?? sorted.first(where: \.isDefault)
            ?? sorted.first
    }

    /// Subtitles by the subtitle mode, when nothing was picked for the item or its series.
    private static func preferredSubtitle(
        _ candidates: [MediaTrack],
        audioLanguage: String?,
        _ preferences: TrackPreferences,
    ) -> MediaTrack? {
        let language = preferences.subtitleLanguage
        let sorted = sortedForPreferences(candidates, language: language)
        switch preferences.subtitleMode {
        case .always:
            return always(sorted, language: language)
        case .onlyForced:
            guard let language else { return sorted.first(where: \.isForced) }
            return sorted.first { LanguageCode.same($0.language, language) && $0.isForced }
                ?? sorted.first { LanguageCode.isUnknown($0.language) && $0.isForced }
        case .smart:
            return smart(sorted, language: language, audioLanguage: audioLanguage, preferences)
        case .default:
            let defaultOrForced = sorted.filter { $0.isDefault || $0.isForced }
            return defaultOrForced.first { LanguageCode.same($0.language, language) } ?? defaultOrForced.first
        case .none:
            return nil
        }
    }

    /// Regular subtitles before forced ones, in the preferred language or an unknown one.
    private static func always(_ sorted: [MediaTrack], language: String?) -> MediaTrack? {
        guard let language else {
            return sorted.first { !$0.isForced } ?? sorted.first
        }
        return sorted.first { !$0.isForced && LanguageCode.sameOrUnknown($0.language, language) }
            ?? sorted.first { LanguageCode.sameOrUnknown($0.language, language) }
    }

    /// Subtitles when the audio isn't in a language the user prefers, otherwise forced ones.
    private static func smart(
        _ sorted: [MediaTrack],
        language: String?,
        audioLanguage: String?,
        _ preferences: TrackPreferences,
    ) -> MediaTrack? {
        guard let language else { return sorted.first(where: \.isDefault) }
        // Wholphin reads the Jellyfin profile's audio language here even when the app sets
        // another; this uses the one that chose the audio.
        let understood = preferences.audioLanguage ?? language
        if !LanguageCode.same(understood, audioLanguage) {
            return sorted.first { LanguageCode.same($0.language, language) }
                ?? sorted.first { LanguageCode.isUnknown($0.language) }
        }
        return sorted.first { $0.isForced && LanguageCode.same($0.language, language) }
            ?? sorted.first { $0.isForced && LanguageCode.isUnknown($0.language) }
    }

    /// External first, then default, then the preferred language's regular and forced
    /// subtitles, then other forced ones, keeping the server's order otherwise.
    private static func sortedForPreferences(_ candidates: [MediaTrack], language: String?) -> [MediaTrack] {
        func rank(_ track: MediaTrack) -> [Bool] {
            let inLanguage = LanguageCode.same(track.language, language)
            return [
                track.isExternal,
                track.isDefault,
                !track.isForced && inLanguage,
                track.isForced && inLanguage,
                track.isForced && LanguageCode.isUnknown(track.language),
                track.isForced,
            ]
        }
        return candidates.enumerated().sorted { lhs, rhs in
            let left = rank(lhs.element), right = rank(rhs.element)
            if let difference = zip(left, right).first(where: { $0 != $1 }) {
                return difference.0
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// Forced or signs subtitles: in the preferred language, else the audio's, else an unknown
    /// one. Wholphin's `findForcedTrack`.
    private static func forcedTrack(
        _ candidates: [MediaTrack],
        _ subtitleLanguage: String?,
        _ audioLanguage: String?,
    ) -> MediaTrack? {
        let forced = candidates.filter(\.isForcedOrSigns)
        return forced.first { LanguageCode.same($0.language, subtitleLanguage) }
            ?? forced.first { LanguageCode.same($0.language, audioLanguage) }
            ?? forced.first { LanguageCode.isUnknown($0.language) }
    }
}

extension SeriesTrackChoice {
    var reason: TrackChoiceReason {
        switch parent {
        case .season: .season
        case .series: .series
        }
    }
}
