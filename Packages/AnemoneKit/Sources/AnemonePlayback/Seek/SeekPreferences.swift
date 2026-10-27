import AnemoneCore

/// How far the overlay's left and right presses and its skip buttons seek. Wholphin's names and
/// defaults; Now Playing's skip commands can use them too.
public extension Preferences {
    /// 30 s, from 5 s to 5 minutes in Wholphin.
    static let skipForwardMs = Preference("skipForwardMs", default: 30000)
    /// 10 s, from 5 s to 5 minutes in Wholphin.
    static let skipBackMs = Preference("skipBackMs", default: 10000)
}
