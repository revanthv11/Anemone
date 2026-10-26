import AnemoneCore
import AnemoneJellyfin
import Foundation
import Observation

/// A library's sort, filter and view options, like Wholphin's `LibraryDisplayInfo`.
struct LibraryDisplaySettings: Codable, Hashable {
    var sort = LibrarySort.default
    var filter = LibraryFilter()
    /// `nil` until the user changes them, so the library type's defaults apply.
    var view: GridViewOptions?
}

extension LibraryDisplaySettings {
    /// Field by field, so one part that no longer decodes doesn't throw away the others.
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        sort = (try? values.decodeIfPresent(LibrarySort.self, forKey: .sort)) ?? .default
        filter = (try? values.decodeIfPresent(LibraryFilter.self, forKey: .filter)) ?? LibraryFilter()
        view = try? values.decodeIfPresent(GridViewOptions.self, forKey: .view)
    }
}

/// A profile's per-library settings and sidebar pins.
///
/// Kept in UserDefaults for now, which tvOS may clear when storage runs low. Syncing them to
/// the server through DisplayPreferences, as the plan describes, comes later.
@Observable
final class LibraryPreferences {
    private(set) var pins: LibraryPins
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let prefix: String

    init(serverID: String, userID: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        prefix = "libraries.\(serverID).\(userID)"
        pins = Self.decode(LibraryPins.self, from: defaults.data(forKey: "\(prefix).pins")) ?? LibraryPins()
    }

    func settings(for library: Library) -> LibraryDisplaySettings {
        Self.decode(LibraryDisplaySettings.self, from: defaults.data(forKey: key(for: library)))
            ?? LibraryDisplaySettings()
    }

    func save(_ settings: LibraryDisplaySettings, for library: Library) {
        defaults.set(try? JSONEncoder().encode(settings), forKey: key(for: library))
    }

    func updatePins(_ change: (inout LibraryPins) -> Void) {
        change(&pins)
        defaults.set(try? JSONEncoder().encode(pins), forKey: "\(prefix).pins")
    }

    private func key(for library: Library) -> String {
        "\(prefix).display.\(library.id)"
    }

    /// `nil` for missing data, and for data saved by a version whose format no longer decodes.
    private static func decode<Value: Decodable>(_: Value.Type, from data: Data?) -> Value? {
        data.flatMap { try? JSONDecoder().decode(Value.self, from: $0) }
    }
}
