import Foundation

/// What the app shares with its Top Shelf extension: the Keychain item holding the sign-ins, in
/// a Keychain access group both can read, and a few settings in the App Group's defaults.
///
/// Builds for a device need both registered for the team; simulator builds fill in the team
/// prefix themselves. A build without them keeps working on its own, with an empty Top Shelf.
public enum SharedStorage {
    /// The Keychain service of the sign-ins item (`AccountRepository`).
    public static let keychainService = "com.revanthv11.anemone"
    public static let appGroup = "group.com.revanthv11.anemone"
    /// The Info.plist key holding the shared access group, `$(AppIdentifierPrefix)` filled in by
    /// the build, since the team prefix isn't known in code.
    static let accessGroupInfoKey = "AnemoneKeychainAccessGroup"

    /// The shared Keychain access group, from the bundle's Info.plist, or `nil` when the build
    /// didn't fill in a team prefix.
    public static func keychainAccessGroup(in bundle: Bundle = .main) -> String? {
        accessGroup(fromInfoValue: bundle.object(forInfoDictionaryKey: accessGroupInfoKey) as? String)
    }

    static func accessGroup(fromInfoValue value: String?) -> String? {
        // Without a team the prefix is empty, leaving no team ID before the first dot.
        guard let value, !value.isEmpty, !value.hasPrefix("."), !value.contains("$(") else { return nil }
        return value
    }

    /// The app's store for the sign-ins. First moves the item saved by earlier versions, in the
    /// app's own access group, into the shared one, so they stay signed in; when that can't be
    /// done, the item stays where it is and is used there.
    public static func appKeychain(bundle: Bundle = .main) -> KeychainStore {
        guard let group = keychainAccessGroup(in: bundle) else {
            return KeychainStore(service: keychainService)
        }
        switch KeychainStore.moveItems(service: keychainService, into: group) {
        case .groupUnavailable:
            return KeychainStore(service: keychainService)
        case .moved, .nothingToMove:
            return KeychainStore(service: keychainService, accessGroup: group)
        }
    }

    /// The Top Shelf's view of the sign-ins: only what the app moved into the shared group.
    /// `nil` when the build has no shared group.
    public static func extensionKeychain(bundle: Bundle = .main) -> KeychainStore? {
        keychainAccessGroup(in: bundle).map { KeychainStore(service: keychainService, accessGroup: $0) }
    }

    /// The App Group's defaults, where the app leaves settings for the Top Shelf. Without the
    /// App Group entitlement this is the process's own suite, so the Top Shelf sees the defaults.
    public static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }
}
