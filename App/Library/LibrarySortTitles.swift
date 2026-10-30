import AnemoneJellyfin
import SwiftUI

// How the sort menus name their choices and read them to VoiceOver, shared by the library
// grid, the music lists and the photo folders.

extension LibrarySort.Field {
    /// Wholphin's names for its sort options.
    var title: String {
        switch self {
        case .default: String(localized: "Default")
        case .name: String(localized: "Name")
        case .premiereDate: String(localized: "Date Released")
        case .dateCreated: String(localized: "Date Added")
        case .dateLastContentAdded: String(localized: "Date Episode Added")
        case .datePlayed, .seriesDatePlayed: String(localized: "Date Played")
        case .communityRating: String(localized: "Community Rating")
        case .criticRating: String(localized: "Critic Rating")
        case .officialRating: String(localized: "Parental Rating")
        case .runtime: String(localized: "Runtime")
        case .playCount: String(localized: "Play Count")
        case .albumArtist: String(localized: "Album Artist")
        case .random: String(localized: "Random")
        }
    }
}

extension LibrarySort.Direction {
    var systemImage: String {
        switch self {
        case .ascending: "arrow.up"
        case .descending: "arrow.down"
        }
    }

    /// What VoiceOver reads on a sort menu showing `field`, as the library grid's sort button is
    /// read: "Sort by Name, ascending".
    func spokenSort(_ field: String) -> Text {
        switch self {
        case .ascending: Text("Sort by \(field), ascending")
        case .descending: Text("Sort by \(field), descending")
        }
    }
}
