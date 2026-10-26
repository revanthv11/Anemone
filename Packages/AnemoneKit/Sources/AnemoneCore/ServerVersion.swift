/// A Jellyfin server version such as `12.3` or `12.0.1`.
public struct ServerVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    /// Anemone only supports Jellyfin 12 and later.
    public static let minimumSupported = ServerVersion(major: 12, minor: 0, patch: 0)

    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int = 0) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parses the `Version` string from `/System/Info/Public`.
    ///
    /// Accepts two or three numeric components (`12.3`, `10.11.2`); anything after the
    /// numbers, such as a pre-release suffix, is ignored.
    public init?(_ string: String) {
        let numbers = string
            .split(separator: ".", maxSplits: 2)
            .map { $0.prefix { $0.isNumber } }
        guard numbers.count >= 2, numbers.allSatisfy({ !$0.isEmpty }),
              let major = Int(numbers[0]), let minor = Int(numbers[1])
        else { return nil }
        let patch = numbers.count > 2 ? Int(numbers[2]) ?? 0 : 0
        self.init(major: major, minor: minor, patch: patch)
    }

    public var isSupported: Bool {
        self >= Self.minimumSupported
    }

    public var description: String {
        "\(major).\(minor).\(patch)"
    }

    public static func < (lhs: ServerVersion, rhs: ServerVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}
