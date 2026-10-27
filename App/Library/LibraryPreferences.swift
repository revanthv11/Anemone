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

extension Preferences {
    /// Wholphin's "Remember selected tab": each library opens on the tab last chosen there,
    /// instead of its first. Off unless changed, as in Wholphin.
    static let rememberSelectedTab = Preference("rememberSelectedTab", default: false)
}

/// A profile's per-library settings, remembered tabs and sidebar pins.
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

    /// - Parameter page: one of the library's other grids, such as its Collections tab or its
    ///   genres' pages, which keep settings of their own; `nil` for the library's own grid.
    func settings(for library: Library, page: String? = nil) -> LibraryDisplaySettings {
        Self.decode(LibraryDisplaySettings.self, from: defaults.data(forKey: key(for: library, page: page)))
            ?? LibraryDisplaySettings()
    }

    func save(_ settings: LibraryDisplaySettings, for library: Library, page: String? = nil) {
        defaults.set(try? JSONEncoder().encode(settings), forKey: key(for: library, page: page))
    }

    /// The tab last chosen in the library, as Wholphin's `RememberedTabService` keeps it.
    func rememberedSection(for library: Library) -> String? {
        defaults.string(forKey: "\(prefix).tab.\(library.id)")
    }

    func rememberSection(_ section: LibrarySection, for library: Library) {
        defaults.set(section.rawValue, forKey: "\(prefix).tab.\(library.id)")
    }

    func updatePins(_ change: (inout LibraryPins) -> Void) {
        change(&pins)
        defaults.set(try? JSONEncoder().encode(pins), forKey: "\(prefix).pins")
    }

    private func key(for library: Library, page: String?) -> String {
        let key = "\(prefix).display.\(library.id)"
        return page.map { "\(key).\($0)" } ?? key
    }

    /// `nil` for missing data, and for data saved by a version whose format no longer decodes.
    private static func decode<Value: Decodable>(_: Value.Type, from data: Data?) -> Value? {
        data.flatMap { try? JSONDecoder().decode(Value.self, from: $0) }
    }
}
