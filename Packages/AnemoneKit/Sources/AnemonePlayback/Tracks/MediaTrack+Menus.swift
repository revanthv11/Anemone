import AnemoneCore
import Foundation

extension MediaTrack {
    /// The server's label, such as "English (SRT) - Default - SUBRIP", else the language and codec.
    var menuTitle: String {
        if let displayTitle, !displayTitle.isEmpty {
            return displayTitle
        }
        let language = language.flatMap { Locale.current.localizedString(forLanguageCode: $0) }
        return [title ?? language ?? String(localized: "Unknown", bundle: .module), codec?.uppercased()]
            .compactMap(\.self).joined(separator: " - ")
    }
}

extension MediaTrack? {
    /// The Subtitles menu's choice for showing this track.
    var choice: SubtitleChoice {
        map { .track(index: $0.index) } ?? .off
    }
}

extension [MediaTrack] {
    func first(id: Int) -> MediaTrack? {
        first { $0.id == id }
    }
}
