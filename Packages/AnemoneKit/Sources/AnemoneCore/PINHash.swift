import CryptoKit
import Foundation

/// A salted hash of a profile PIN.
///
/// A 4-digit PIN is a convenience lock against other people in the household, not real
/// security, but unlike Wholphin the PIN itself is never stored.
public struct PINHash: Codable, Hashable, Sendable {
    public static let length = 4

    private let salt: Data
    private let digest: Data

    public init(pin: String) {
        salt = Data((0 ..< 16).map { _ in UInt8.random(in: .min ... .max) })
        digest = Self.digest(of: pin, salt: salt)
    }

    public func matches(_ pin: String) -> Bool {
        Self.digest(of: pin, salt: salt) == digest
    }

    /// Whether `pin` is an acceptable new PIN: exactly `length` digits.
    public static func isValid(_ pin: String) -> Bool {
        pin.count == length && pin.allSatisfy(\.isASCIIDigit)
    }

    private static func digest(of pin: String, salt: Data) -> Data {
        Data(SHA256.hash(data: salt + Data(pin.utf8)))
    }
}

private extension Character {
    var isASCIIDigit: Bool {
        isASCII && isNumber
    }
}
