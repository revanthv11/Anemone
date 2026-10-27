import AnemoneCore
import AnemoneJellyfin
import Foundation
import Observation

extension Preferences {
    /// Wholphin's "Combined search results": one grid of everything found, instead of a row for
    /// each kind of item.
    static let combinedSearchResults = Preference("combinedSearchResults", default: false)
}

/// A profile's search settings: the kinds of item left out of Search, which Wholphin keeps per
/// user, and recent searches.
///
/// Kept on this device in UserDefaults, which tvOS may clear when storage runs low; neither is
/// worth syncing to the server.
@Observable
final class SearchPreferences {
    private(set) var excludedKinds: Set<SearchKind>
    private(set) var recent: RecentSearches
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let prefix: String

    init(serverID: String, userID: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        prefix = "search.\(serverID).\(userID)"
        excludedKinds = Self.decode(Set<SearchKind>.self, from: defaults.data(forKey: "\(prefix).excludedKinds")) ?? []
        recent = Self.decode(RecentSearches.self, from: defaults.data(forKey: "\(prefix).recent")) ?? RecentSearches()
    }

    func setIncluded(_ isIncluded: Bool, _ kind: SearchKind) {
        if isIncluded {
            excludedKinds.remove(kind)
        } else {
            excludedKinds.insert(kind)
        }
        defaults.set(try? JSONEncoder().encode(excludedKinds), forKey: "\(prefix).excludedKinds")
    }

    func updateRecent(_ change: (inout RecentSearches) -> Void) {
        change(&recent)
        defaults.set(try? JSONEncoder().encode(recent), forKey: "\(prefix).recent")
    }

    /// `nil` for missing data, and for data saved by a version whose format no longer decodes.
    private static func decode<Value: Decodable>(_: Value.Type, from data: Data?) -> Value? {
        data.flatMap { try? JSONDecoder().decode(Value.self, from: $0) }
    }
}
