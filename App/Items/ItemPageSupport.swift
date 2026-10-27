import AnemoneJellyfin
import AnemoneUI
import SwiftUI

/// A change to the user's history with an item.
enum UserStateChange {
    case played(Bool)
    case favorite(Bool)
}

extension BrowseModel {
    /// Saves whether the user watched or likes an item, and returns the item's new state. When
    /// the server can't save it, reports why through `failed` and returns `nil`.
    ///
    /// The change shows at once on every card of the item, through `cardMarks`, whether a card's
    /// menu or a page's own button made it. So a card doesn't go on showing an earlier change
    /// after the item is changed back.
    ///
    /// - Parameter given: the marks of the card whose menu made the change; `nil` for the page's
    ///   own buttons, whose `details` are what the page shows.
    func save(
        _ change: UserStateChange,
        for details: ItemDetails,
        given: CardMarks? = nil,
        failed: (ItemAlert) -> Void,
    ) async -> ItemDetails.UserState? {
        do {
            let state = switch change {
            case let .played(isPlayed):
                try await session.setPlayed(isPlayed, itemID: details.id)
            case let .favorite(isFavorite):
                try await session.setFavorite(isFavorite, itemID: details.id)
            }
            let before = given ?? details.cardMarks
            cardMarks.record(CardMarks(state, replacing: before), for: details.id, replacing: before)
            return state
        } catch {
            if let message = problem(with: error, failure: "Couldn't update \(details.item.name).") {
                failed(.failed(message))
            }
            return nil
        }
    }

    func imageURL(_ image: ItemImage?, width: CGFloat) -> URL? {
        image.flatMap { session.imageURL(for: $0, maxWidth: Int(width)) }
    }

    /// What an item page says when a request fails: `failure`, a whole sentence such as
    /// "Couldn't load Sintel.", then what to check. `nil` when the page was left, which cancels
    /// its requests.
    func problem(with error: any Error, failure: LocalizedStringResource) -> String? {
        if error as? SessionError == .signedOut {
            noteSignedOut()
            return String(localized: "\(server.name) signed you out. Go back to sign in again.")
        }
        guard !Task.isCancelled else { return nil }
        return String(localized: "\(String(localized: failure)) Check that \(server.name) is running, then try again.")
    }

    /// The result of a request for part of an item page that it can do without, such as a
    /// row. Failures leave it out, as Wholphin does, though a revoked token still sends Home to
    /// sign-in.
    func optional<Value>(_ result: Result<Value, any Error>) -> Value? {
        switch result {
        case let .success(value):
            return value
        case let .failure(error):
            if error as? SessionError == .signedOut {
                noteSignedOut()
            }
            return nil
        }
    }
}

/// Runs a request and keeps its error, so several can run at once with `async let` and be
/// checked afterwards.
func attempt<Value: Sendable>(_ request: @Sendable () async throws -> Value) async -> Result<Value, any Error> {
    do {
        return try await .success(request())
    } catch {
        return .failure(error)
    }
}

extension ItemDetails {
    /// Like Wholphin's card titles: episodes are titled by their series.
    var cardTitle: String {
        item.kind == .episode ? item.episode?.seriesName ?? item.name : item.name
    }

    /// Like Wholphin's card subtitles: the episode, a series' years, or the year.
    var cardSubtitle: String? {
        switch item.kind {
        case .episode:
            item.subtitle
        case .series:
            seriesYears
        default:
            item.year.map(String.init)
        }
    }

    var badges: CardBadges {
        let hasCount = [.series, .season, .collection].contains(item.kind)
        return CardBadges(
            isFavorite: userState.isFavorite,
            isPlayed: userState.isPlayed,
            unplayedCount: hasCount ? userState.unplayedCount : nil,
        )
    }

    /// What an item page's card of it shows over its artwork.
    var cardMarks: CardMarks {
        CardMarks(badges: badges, progress: item.progress)
    }

    /// The card shape Wholphin's collection rows use for this kind of item.
    var rowShape: CardShape {
        switch item.kind {
        case .episode, .video, .musicVideo: .thumb
        case .musicAlbum, .audio, .playlist: .square
        default: .poster
        }
    }

    /// Episodes show their own still in 16:9 cards, not the series art home rows use.
    func cardImage(for shape: CardShape) -> ItemImage? {
        switch shape {
        case .poster: item.posterImage
        case .thumb: item.kind == .episode ? ownPrimaryImage ?? item.thumbImage : item.thumbImage
        case .square: item.squareImage
        }
    }

    /// Whether Wholphin offers Play for this kind of item.
    var isPlayable: Bool {
        [.movie, .episode, .video, .musicVideo, .audio].contains(item.kind)
    }

    /// The parts of Wholphin's quick-details line (`BaseItem.ui.quickDetails` and
    /// `QuickDetails`).
    ///
    /// - Parameter spoken: the parts as VoiceOver reads them, with lengths in words, the episode
    ///   and the ratings named, and no star.
    func quickDetails(now: Date, spoken: Bool = false) -> [Text] {
        var parts = basicDetails(spoken: spoken).compactMap(\.self).map { Text($0) }
        if let runtime = item.runtime?.roundedToMinutes, runtime > .zero {
            parts.append(Text(spoken ? runtime.spokenLength : runtime.lengthText))
        }
        if let left = timeRemaining?.roundedToMinutes {
            parts.append(Text("\(spoken ? left.spokenLength : left.lengthText) left"))
        }
        if let rating = item.officialRating {
            parts.append(spoken ? Text("Rated \(rating)") : Text(rating))
        }
        parts += scores(spoken: spoken)
        if let endsAt = endsAt(now: now) {
            parts.append(endsAt)
        }
        return parts
    }

    /// The start of the line, which depends on the type.
    private func basicDetails(spoken: Bool) -> [String?] {
        switch item.kind {
        case .episode:
            [spoken ? spokenEpisodeLabel : item.episodeLabel, premiereDate?.dayText]
        case .season:
            [childCount.map { String(localized: "\($0) episodes") }, item.year.map(String.init)]
        case .series:
            [seriesYears]
        case .collection:
            [item.year.map(String.init), childCount.map { String(localized: "\($0) items") }]
        default:
            [item.year.map(String.init)]
        }
    }

    /// The community rating out of 10 with a star, and the critics' percentage.
    private func scores(spoken: Bool) -> [Text] {
        var scores: [Text] = []
        if let communityRating {
            let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1))
            if spoken {
                scores.append(Text("Community rating \(communityRating, format: format) out of 10"))
            } else {
                let star = Text(Image(systemName: "star.fill")).foregroundStyle(Self.starColor)
                scores.append(Text("\(communityRating, format: format) \(star)"))
            }
        }
        if let criticRating {
            let percent = Int(criticRating.rounded())
            scores.append(spoken ? Text("Critic rating \(percent)%") : Text("\(percent)%"))
        }
        return scores
    }

    /// Wholphin's `FilledStarColor`, the same in every theme, as its favourite red is.
    private static let starColor = ThemeColor(0xFFFF_C700)

    /// When the item would end if started now. Wholphin shows this for things watched in one
    /// sitting.
    private func endsAt(now: Date) -> Text? {
        guard [.movie, .episode, .video, .musicVideo].contains(item.kind),
              let remaining = timeRemaining ?? item.runtime, remaining > .zero
        else { return nil }
        return remaining.endsAtText(from: now)
    }
}

extension CardMarks {
    /// What the server's answer to a change leaves on cards that showed `before`. The answer
    /// doesn't always have an unplayed count: cards that show one take it from here, and only
    /// those do.
    init(_ state: ItemDetails.UserState, replacing before: CardMarks) {
        var badges = CardBadges(isFavorite: state.isFavorite, isPlayed: state.isPlayed)
        badges.unplayedCount = state.unplayedCount ?? before.badges.unplayedCount.map { state.isPlayed ? 0 : $0 }
        self.init(badges: badges, progress: state.progress)
    }
}

extension Duration {
    /// Rounded to the nearest minute, as Wholphin shows lengths.
    var roundedToMinutes: Duration {
        .seconds((Double(components.seconds) / 60).rounded() * 60)
    }

    /// "1h 52m".
    var lengthText: String {
        formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }

    /// "42:10", or "1:02:03" past an hour.
    var clockText: String {
        formatted(.time(pattern: self >= .seconds(3600) ? .hourMinuteSecond : .minuteSecond))
    }

    /// "Ends at 9:41 PM": when this much is over if it starts at `start`. The item page and the
    /// player both show it.
    func endsAtText(from start: Date) -> Text {
        let end = start.addingTimeInterval(TimeInterval(components.seconds))
        return Text("Ends at \(end.formatted(date: .omitted, time: .shortened))")
    }
}

extension Date {
    /// Jellyfin keeps release dates and birthdays at midnight UTC, so they're shown in UTC to
    /// keep the day from shifting with the time zone.
    var dayText: String {
        formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: .gmt))
    }
}
