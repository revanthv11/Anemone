import Foundation

// The JSON is kotlinx.serialization's, as Wholphin writes it: each row is an object whose `type`
// names its kind, with the kind's fields and `viewOptions` beside it. Reading is lenient, as
// Wholphin's parser is: missing fields take their defaults, and unknown keys are ignored. Where
// Wholphin would reject a row for an unknown enum value, the value's default is used instead.

extension HomeRowConfig: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, viewOptions, parentId, kind, recursive, sort, name, filter
    }

    private enum TypeName: String {
        case continueWatching = "ContinueWatching"
        case nextUp = "NextUp"
        case continueWatchingCombined = "ContinueWatchingCombined"
        case recentlyAdded = "RecentlyAdded"
        case recentlyReleased = "RecentlyReleased"
        case genres = "Genres"
        case studios = "Studios"
        case favorite = "Favorite"
        case recordings = "Recordings"
        case tvPrograms = "TvPrograms"
        case tvChannels = "TvChannels"
        case suggestions = "Suggestions"
        case byParent = "ByParent"
        case getItems = "GetItems"
        case customEndpoint = "CustomEndpoint"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeName = try container.decode(String.self, forKey: .type)
        guard let type = TypeName(rawValue: typeName) else {
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown row type \(typeName)",
            )
        }
        let kind = try Self.kind(of: type, from: container, decoder: decoder)
        let viewOptions = try container.decodeIfPresent(HomeRowViewOptions.self, forKey: .viewOptions)
        self.init(kind, viewOptions: viewOptions)
    }

    private static func kind(
        of type: TypeName,
        from container: KeyedDecodingContainer<CodingKeys>,
        decoder: any Decoder,
    ) throws -> Kind {
        if let kind = plainKinds[type] {
            return kind
        }
        if let kind = parentKinds[type] {
            return try kind(JellyfinID.compact(container.decode(String.self, forKey: .parentId)))
        }
        switch type {
        case .favorite:
            return try .favorite(itemKind: container.decode(String.self, forKey: .kind))
        case .byParent:
            return try .byParent(
                parentID: JellyfinID.compact(container.decode(String.self, forKey: .parentId)),
                recursive: container.decodeIfPresent(Bool.self, forKey: .recursive) ?? false,
                sort: container.decodeIfPresent(HomeRowSort.self, forKey: .sort),
            )
        case .getItems:
            return try .getItems(
                name: container.decode(String.self, forKey: .name),
                filter: container.decode(HomeGetItemsFilter.self, forKey: .filter),
            )
        default:
            return try .customEndpoint(HomeCustomEndpoint(from: decoder))
        }
    }

    /// Kinds with no fields of their own.
    private static let plainKinds: [TypeName: Kind] = [
        .continueWatching: .continueWatching,
        .nextUp: .nextUp,
        .continueWatchingCombined: .continueWatchingCombined,
        .recordings: .recordings,
        .tvPrograms: .tvPrograms,
        .tvChannels: .tvChannels,
    ]

    /// Kinds whose only field is `parentId`.
    private static let parentKinds: [TypeName: @Sendable (String) -> Kind] = [
        .recentlyAdded: { .recentlyAdded(parentID: $0) },
        .recentlyReleased: { .recentlyReleased(parentID: $0) },
        .genres: { .genres(parentID: $0) },
        .studios: { .studios(parentID: $0) },
        .suggestions: { .suggestions(parentID: $0) },
    ]

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(typeName.rawValue, forKey: .type)
        switch kind {
        case let .recentlyAdded(id), let .recentlyReleased(id), let .genres(id), let .studios(id),
             let .suggestions(id):
            try container.encode(JellyfinID.dashed(id), forKey: .parentId)
        case let .favorite(itemKind):
            try container.encode(itemKind, forKey: .kind)
        case let .byParent(id, recursive, sort):
            try container.encode(JellyfinID.dashed(id), forKey: .parentId)
            try container.encode(recursive, forKey: .recursive)
            try container.encodeIfPresent(sort, forKey: .sort)
        case let .getItems(name, filter):
            try container.encode(name, forKey: .name)
            try container.encode(filter, forKey: .filter)
        case let .customEndpoint(endpoint):
            try endpoint.encode(to: encoder)
        case .continueWatching, .nextUp, .continueWatchingCombined, .recordings, .tvPrograms, .tvChannels:
            break
        }
        try container.encode(viewOptions, forKey: .viewOptions)
    }

    private var typeName: TypeName {
        switch kind {
        case .continueWatching: .continueWatching
        case .nextUp: .nextUp
        case .continueWatchingCombined: .continueWatchingCombined
        case .recentlyAdded: .recentlyAdded
        case .recentlyReleased: .recentlyReleased
        case .genres: .genres
        case .studios: .studios
        case .favorite: .favorite
        case .recordings: .recordings
        case .tvPrograms: .tvPrograms
        case .tvChannels: .tvChannels
        case .suggestions: .suggestions
        case .byParent: .byParent
        case .getItems: .getItems
        case .customEndpoint: .customEndpoint
        }
    }
}

extension HomeRowViewOptions: Codable {
    private enum CodingKeys: String, CodingKey {
        case heightDp, spacing, contentScale, aspectRatio, imageType, showTitles, useSeries
        case episodeContentScale, episodeAspectRatio, episodeImageType
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = HomeRowViewOptions()
        func value<Value: RawRepresentable<String>>(_ key: CodingKeys, _ fallback: Value) throws -> Value {
            try container.decodeIfPresent(String.self, forKey: key).flatMap(Value.init(rawValue:)) ?? fallback
        }
        self.init()
        heightDp = try container.decodeIfPresent(Int.self, forKey: .heightDp) ?? defaults.heightDp
        spacing = try container.decodeIfPresent(Int.self, forKey: .spacing) ?? defaults.spacing
        contentScale = try value(.contentScale, defaults.contentScale)
        aspectRatio = try value(.aspectRatio, defaults.aspectRatio)
        imageType = try value(.imageType, defaults.imageType)
        showTitles = try container.decodeIfPresent(Bool.self, forKey: .showTitles) ?? defaults.showTitles
        useSeries = try container.decodeIfPresent(Bool.self, forKey: .useSeries) ?? defaults.useSeries
        episodeContentScale = try value(.episodeContentScale, defaults.episodeContentScale)
        episodeAspectRatio = try value(.episodeAspectRatio, defaults.episodeAspectRatio)
        episodeImageType = try value(.episodeImageType, defaults.episodeImageType)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(heightDp, forKey: .heightDp)
        try container.encode(spacing, forKey: .spacing)
        try container.encode(contentScale.rawValue, forKey: .contentScale)
        try container.encode(aspectRatio.rawValue, forKey: .aspectRatio)
        try container.encode(imageType.rawValue, forKey: .imageType)
        try container.encode(showTitles, forKey: .showTitles)
        try container.encode(useSeries, forKey: .useSeries)
        try container.encode(episodeContentScale.rawValue, forKey: .episodeContentScale)
        try container.encode(episodeAspectRatio.rawValue, forKey: .episodeAspectRatio)
        try container.encode(episodeImageType.rawValue, forKey: .episodeImageType)
    }
}

extension HomePageSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case rows, version
    }

    /// Skips rows it can't read, such as kinds added by a newer Wholphin, as Wholphin's
    /// `HomeSettingsService.decode` does.
    ///
    /// - Throws: `HomeSettingsError.unsupportedVersion` when the version is missing or newer
    ///   than `supportedVersion`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try? container.decodeIfPresent(Int.self, forKey: .version)
        guard let version, version <= Self.supportedVersion else {
            throw HomeSettingsError.unsupportedVersion(version)
        }
        let rows = try container.decodeIfPresent([Lenient<HomeRowConfig>].self, forKey: .rows) ?? []
        self.init(rows: rows.compactMap(\.value), version: version)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rows, forKey: .rows)
        try container.encode(version, forKey: .version)
    }

    /// Reads settings from the JSON string Wholphin stores in DisplayPreferences, allowing the
    /// trailing commas and other slack Wholphin's parser allows.
    public init(json: String) throws {
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        self = try decoder.decode(Self.self, from: Data(json.utf8))
    }

    /// The JSON string to store.
    public func json() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try String(bytes: encoder.encode(self), encoding: .utf8) ?? ""
    }
}

/// Decodes a value, or `nil` when it can't, without failing the whole array.
private struct Lenient<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}
