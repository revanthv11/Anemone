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
    func save(
        _ change: UserStateChange,
        for details: ItemDetails,
        failed: (ItemAlert) -> Void,
    ) async -> ItemDetails.UserState? {
        do {
            switch change {
            case let .played(isPlayed):
                return try await session.setPlayed(isPlayed, itemID: details.id)
            case let .favorite(isFavorite):
                return try await session.setFavorite(isFavorite, itemID: details.id)
            }
        } catch {
            if let message = problem(with: error, doing: "update \(details.item.name)") {
                failed(.failed(message))
            }
            return nil
        }
    }

    func imageURL(_ image: ItemImage?, width: CGFloat) -> URL? {
        image.flatMap { session.imageURL(for: $0, maxWidth: Int(width)) }
    }

    /// What an item page says when a request fails. `nil` when the page was left, which
    /// cancels its requests.
    func problem(with error: any Error, doing what: String) -> String? {
        if error as? SessionError == .signedOut {
            noteSignedOut()
            return "\(server.name) signed you out. Go back to sign in again."
        }
        guard !Task.isCancelled else { return nil }
        return "Couldn't \(what). Check that \(server.name) is running, then try again."
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
    func quickDetails(now: Date) -> [Text] {
        var parts = basicDetails.compactMap(\.self).map { Text($0) }
        if let runtime = item.runtime?.roundedToMinutes, runtime > .zero {
            parts.append(Text(runtime.lengthText))
        }
        if let left = timeRemaining?.roundedToMinutes {
            parts.append(Text("\(left.lengthText) left"))
        }
        if let rating = item.officialRating {
            parts.append(Text(rating))
        }
        parts += scores
        if let endsAt = endsAt(now: now) {
            parts.append(endsAt)
        }
        return parts
    }

    /// The start of the line, which depends on the type.
    private var basicDetails: [String?] {
        switch item.kind {
        case .episode:
            [item.episodeLabel, premiereDate?.dayText]
        case .season:
            [childCount.map { $0 == 1 ? "1 episode" : "\($0) episodes" }, item.year.map(String.init)]
        case .series:
            [seriesYears]
        case .collection:
            [item.year.map(String.init), childCount.map { $0 == 1 ? "1 item" : "\($0) items" }]
        default:
            [item.year.map(String.init)]
        }
    }

    /// The community rating out of 10 with a star, and the critics' percentage.
    private var scores: [Text] {
        var scores: [Text] = []
        if let communityRating {
            let star = Text(Image(systemName: "star.fill")).foregroundStyle(.yellow)
            scores.append(Text("\(communityRating, format: .number.precision(.fractionLength(1))) \(star)"))
        }
        if let criticRating {
            scores.append(Text("\(Int(criticRating.rounded()))%"))
        }
        return scores
    }

    /// When the item would end if started now. Wholphin shows this for things watched in one
    /// sitting.
    private func endsAt(now: Date) -> Text? {
        guard [.movie, .episode, .video, .musicVideo].contains(item.kind),
              let remaining = timeRemaining ?? item.runtime, remaining > .zero
        else { return nil }
        let end = now.addingTimeInterval(TimeInterval(remaining.components.seconds))
        return Text("Ends at \(end.formatted(date: .omitted, time: .shortened))")
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
}

extension Date {
    /// Jellyfin keeps release dates and birthdays at midnight UTC, so they're shown in UTC to
    /// keep the day from shifting with the time zone.
    var dayText: String {
        formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: .gmt))
    }
}
