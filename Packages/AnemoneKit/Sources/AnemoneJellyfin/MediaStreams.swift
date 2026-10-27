import AnemoneCore
import Foundation
import JellyfinAPI

/// An item's audio and subtitle tracks in each version, and where it sits in a series: what
/// choosing tracks needs before asking the server how to play it.
public struct ItemTracks: Hashable, Sendable {
    public struct Source: Hashable, Sendable {
        public let id: String?
        public let tracks: [MediaTrack]

        public init(id: String?, tracks: [MediaTrack]) {
            self.id = id
            self.tracks = tracks
        }
    }

    public let itemID: MediaItem.ID
    /// Set for episodes, whose choices are remembered for their season and series.
    public let seriesID: String?
    public let seasonID: String?
    /// In the server's order.
    public let sources: [Source]

    public init(itemID: MediaItem.ID, seriesID: String? = nil, seasonID: String? = nil, sources: [Source]) {
        self.itemID = itemID
        self.seriesID = seriesID
        self.seasonID = seasonID
        self.sources = sources
    }

    /// The version that plays: the one asked for, else the server's first, as PlaybackInfo
    /// picks it. IDs match whatever their case, as `MediaVersions` matches a picked version.
    public func source(_ id: String?) -> Source? {
        guard let id else { return sources.first { $0.id == nil } ?? sources.first }
        return sources.first { $0.id?.caseInsensitiveCompare(id) == .orderedSame }
    }
}

/// A language the server knows, for settings.
public struct ServerLanguage: Hashable, Sendable, Identifiable {
    /// The ISO 639-2 code the server tags streams with, such as `fre`.
    public let code: String
    public let name: String

    public var id: String {
        code
    }

    public init(code: String, name: String) {
        self.code = code
        self.name = name
    }
}

public extension JellyfinSession {
    /// The item's tracks in each version.
    func itemTracks(for itemID: MediaItem.ID) async throws -> ItemTracks {
        let dto = try await send(Paths.getItem(itemID: itemID, userID: userID))
        let isEpisode = dto.type == .episode
        return ItemTracks(
            itemID: itemID,
            seriesID: isEpisode ? dto.seriesID : nil,
            seasonID: isEpisode ? dto.seasonID ?? dto.parentID : nil,
            sources: (dto.mediaSources ?? []).map { source in
                ItemTracks.Source(id: source.id, tracks: (source.mediaStreams ?? []).compactMap(MediaTrack.init))
            },
        )
    }

    /// What the user's Jellyfin profile says about audio and subtitles, which the app's
    /// settings fall back to.
    func profileTrackSettings() async throws -> ProfileTrackSettings {
        let configuration = try await send(Paths.getCurrentUser).configuration
        return ProfileTrackSettings(
            audioLanguage: configuration?.audioLanguagePreference,
            subtitleLanguage: configuration?.subtitleLanguagePreference,
            subtitleMode: configuration?.subtitleMode.map(SubtitleMode.init),
        )
    }

    /// The languages the server knows, by name, as Wholphin lists them in its settings.
    func languages() async throws -> [ServerLanguage] {
        let cultures = try await send(Paths.getCultures)
        let languages = cultures.compactMap { culture -> ServerLanguage? in
            guard let code = culture.threeLetterISOLanguageName, !code.isEmpty else { return nil }
            return ServerLanguage(code: code, name: culture.displayName ?? culture.name ?? code)
        }
        var seen = Set<String>()
        return languages
            .filter { seen.insert($0.code).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

extension MediaTrack {
    /// Audio and subtitle streams; video and the rest are left out.
    init?(_ stream: MediaStream) {
        guard let index = stream.index else { return nil }
        let kind: Kind
        switch stream.type {
        case .audio: kind = .audio
        case .subtitle: kind = .subtitle
        default: return nil
        }
        self.init(
            index: index,
            kind: kind,
            language: stream.language,
            title: stream.title,
            displayTitle: stream.displayTitle,
            codec: stream.codec,
            channels: stream.channels,
            isDefault: stream.isDefault ?? false,
            isForced: stream.isForced ?? false,
            isHearingImpaired: stream.isHearingImpaired ?? false,
            isExternal: stream.isExternal ?? false,
            isText: stream.isTextSubtitleStream ?? (kind == .subtitle),
            delivery: stream.deliveryMethod.map(Delivery.init),
        )
    }
}

private extension MediaTrack.Delivery {
    init(_ method: SubtitleDeliveryMethod) {
        self = switch method {
        case .embed: .embedded
        case .hls: .hls
        case .external: .external
        case .encode: .burnedIn
        case .drop: .dropped
        }
    }
}

private extension SubtitleMode {
    init(_ mode: SubtitlePlaybackMode) {
        self = switch mode {
        case .default: .default
        case .smart: .smart
        case .onlyForced: .onlyForced
        case .always: .always
        case .none: .none
        }
    }
}
