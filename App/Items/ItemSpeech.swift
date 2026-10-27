import AnemoneJellyfin
import SwiftUI

/// What VoiceOver reads where the screen's short forms don't read well aloud: "1h 52m" is read
/// letter by letter, "42:10" as a time of day, and "S1:E3" or a star as symbols. These are for
/// the page's own labels, like the quick details and buttons; cards read themselves
/// (`MediaCard`, `PersonCard`). The spoken lengths and positions are the app's one way of saying
/// a time: the player, Now Playing and the song rows use them too.
extension Duration {
    /// "1 hour, 52 minutes", for `lengthText`'s "1h 52m".
    var spokenLength: String {
        formatted(.units(allowed: [.hours, .minutes], width: .wide))
    }

    /// "42 minutes, 10 seconds", for `clockText`'s "42:10": a position, a song's length, or how
    /// far a button skips.
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
        return String(localized: "Season \(season), episode \(number)")
    }
}

extension View {
    /// Reads `title` for the row as VoiceOver moves into it, with the row's cards inside.
    func accessibilityRow(_ title: String) -> some View {
        accessibilityElement(children: .contain)
            .accessibilityLabel(title)
    }
}
