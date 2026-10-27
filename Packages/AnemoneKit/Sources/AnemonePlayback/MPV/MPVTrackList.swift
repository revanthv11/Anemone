import Foundation

/// Reading libmpv's `track-list` property into the engine's tracks, one sub-property at a time,
/// as Swiftfin's MPV player does.
enum MPVTrackList {
    @MainActor
    static func tracks(_ kind: PlayerTrack.Kind, from client: any MPVClient) -> [PlayerTrack] {
        let type = kind == .audio ? "audio" : "sub"
        let count = client.int("track-list/count") ?? 0
        return (0 ..< count).compactMap { index in
            let property = { (name: String) in "track-list/\(index)/\(name)" }
            guard client.string(property("type")) == type, let id = client.int(property("id")) else { return nil }
            let language = client.string(property("lang")).map(languageTag)
            return PlayerTrack(
                id: id,
                kind: kind,
                title: title(client.string(property("title")), language: language, id: id),
                language: language,
                isSelected: client.flag(property("selected")) ?? false,
                codec: client.string(property("codec")),
                isExternal: client.flag(property("external")),
            )
        }
    }

    /// Files name languages in ISO 639-2, such as `eng` or `fre`; tracks use BCP 47, as
    /// AVFoundation's do, so `en` and `fr`. Codes without a shorter form stay as they are.
    static func languageTag(_ code: String) -> String {
        let bibliographic = ["fre": "fra", "ger": "deu", "dut": "nld", "chi": "zho", "cze": "ces", "gre": "ell"]
        let code = bibliographic[code.lowercased()] ?? code
        return Locale.LanguageCode(code).identifier(.alpha2) ?? code
    }

    /// The file's name for the track, else its language's, else its number.
    static func title(_ title: String?, language: String?, id: Int) -> String {
        if let title, !title.isEmpty {
            return title
        }
        if let language, let name = Locale.current.localizedString(forLanguageCode: language) {
            return name
        }
        return "Track \(id)"
    }
}
