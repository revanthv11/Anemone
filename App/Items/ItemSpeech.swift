import AnemoneJellyfin
import AnemoneUI
import SwiftUI

/// What VoiceOver reads where the screen's short forms don't read well aloud: "1h 52m" is read
/// letter by letter, "42:10" as a time of day, and "S1:E3" or a star as symbols.
extension Duration {
    /// "1 hour, 52 minutes", for `lengthText`'s "1h 52m".
    var spokenLength: String {
        formatted(.units(allowed: [.hours, .minutes], width: .wide))
    }

    /// "42 minutes, 10 seconds", for `clockText`'s "42:10".
    var spokenPosition: String {
        formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }
}

extension [Text] {
    /// The parts one after another, with a pause between them, for an accessibility label; `nil`
    /// when there are none.
    var spokenList: Text? {
        guard let first else { return nil }
        return dropFirst().reduce(first) { line, part in Text("\(line), \(part)") }
    }
}

extension ItemDetails {
    /// "Season 1, episode 3", for `episodeLabel`'s "S1:E3".
    var spokenEpisodeLabel: String? {
        guard let season = item.episode?.seasonNumber, let number = item.episode?.episodeNumber else { return nil }
        return "Season \(season), episode \(number)"
    }

    /// `cardSubtitle` as VoiceOver reads it: "Season 1, episode 3, Pilot" for an episode's
    /// "S1:E3 · Pilot".
    var spokenCardSubtitle: String? {
        guard item.kind == .episode else { return cardSubtitle }
        return [spokenEpisodeLabel, item.name].compactMap(\.self).joined(separator: ", ")
    }

    /// What VoiceOver reads for a card of the item: its title and subtitle, as the card's caption
    /// shows them, then its marks.
    func cardLabel(title: String? = nil, subtitle: String? = nil, marks: CardMarks) -> Text {
        var parts = [Text(title ?? cardTitle)]
        if let subtitle = subtitle ?? spokenCardSubtitle {
            parts.append(Text(subtitle))
        }
        return (parts + marks.spokenParts).spokenList ?? Text(title ?? cardTitle)
    }

    /// What VoiceOver reads for an episode's card on the season page, in place of the card's
    /// "E3": the episode's number and title, then whether it's watched, partly watched or a
    /// favourite, as the card shows it.
    func episodeCardLabel(marks: CardMarks) -> Text {
        var parts: [Text] = []
        if let number = item.episode?.episodeNumber {
            parts.append(Text("Episode \(number)"))
        } else if let day = premiereDate?.dayText {
            parts.append(Text(day))
        }
        parts.append(Text(item.name))
        parts += marks.spokenParts
        return parts.spokenList ?? Text(item.name)
    }
}

extension CardMarks {
    /// How much of the item is watched, how many of its episodes aren't, and whether it's a
    /// favourite, as a card's marks show it.
    var spokenParts: [Text] {
        var parts: [Text] = []
        if let progress, progress > 0 {
            parts.append(Text("\(Int((progress * 100).rounded()))% watched"))
        } else if badges.isPlayed {
            parts.append(Text("Watched"))
        }
        if let count = badges.unplayedCount, count > 0 {
            parts.append(Text("\(count) unwatched"))
        }
        if badges.isFavorite {
            parts.append(Text("Favorite"))
        }
        return parts
    }
}

extension View {
    /// Reads `title` for the row as VoiceOver moves into it, with the row's cards inside.
    func accessibilityRow(_ title: String) -> some View {
        accessibilityElement(children: .contain)
            .accessibilityLabel(title)
    }
}
