import AnemoneJellyfin
import Foundation

extension ItemMenuEntry {
    /// Wholphin's wording, as on the item pages' buttons.
    var title: String {
        switch self {
        case .goTo: String(localized: "Go to")
        case .play: String(localized: "Play")
        case .resume: String(localized: "Resume")
        case .restart: String(localized: "Restart")
        case .shuffle: String(localized: "Shuffle")
        case .addToPlaylist: String(localized: "Add to playlist")
        case .delete: String(localized: "Delete")
        case .removeFromContinueWatching: String(localized: "Remove from Continue Watching")
        case .removeFromNextUp: String(localized: "Remove from Next Up")
        case let .setPlayed(isPlayed):
            if isPlayed {
                String(localized: "Mark as watched")
            } else {
                String(localized: "Mark as unwatched")
            }
        case let .setFavorite(isFavorite):
            if isFavorite {
                String(localized: "Add to favorites")
            } else {
                String(localized: "Remove from favorites")
            }
        case .goToSeries: String(localized: "Go to series")
        }
    }

    var systemImage: String {
        switch self {
        case .goTo: "arrow.forward"
        case .play, .resume: "play.fill"
        case .restart: "arrow.counterclockwise"
        case .shuffle: "shuffle"
        case .addToPlaylist: "text.badge.plus"
        case .delete: "trash"
        case .removeFromContinueWatching: "eye"
        case .removeFromNextUp: "minus.circle"
        case let .setPlayed(isPlayed): isPlayed ? "eye.slash" : "eye"
        case let .setFavorite(isFavorite): isFavorite ? "heart" : "heart.slash"
        case .goToSeries: "tv"
        }
    }

    /// For UI tests: `menu.<identifier>`.
    var identifier: String {
        switch self {
        case .goTo: "goTo"
        case .play: "play"
        case .resume: "resume"
        case .restart: "restart"
        case .shuffle: "shuffle"
        case .addToPlaylist: "addToPlaylist"
        case .delete: "delete"
        case .removeFromContinueWatching: "removeFromContinueWatching"
        case .removeFromNextUp: "removeFromNextUp"
        case let .setPlayed(isPlayed): isPlayed ? "markWatched" : "markUnwatched"
        case let .setFavorite(isFavorite): isFavorite ? "addFavorite" : "removeFavorite"
        case .goToSeries: "goToSeries"
        }
    }
}
