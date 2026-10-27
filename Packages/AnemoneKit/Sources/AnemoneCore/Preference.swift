import Foundation

/// A setting kept in UserDefaults: its key and the value it has until the user changes it.
/// Settings pages bind to it with `@AppStorage(Preferences.someSetting)`; other code reads it
/// with `value()`. Both see the same stored value.
///
/// Each feature declares its settings in its own file, in an extension of `Preferences`, using
/// Wholphin's names and defaults where Wholphin has the setting:
///
/// ```swift
/// public extension Preferences {
///     static let autoPlayNext = Preference("autoPlayNext", default: true)
/// }
/// ```
public struct Preference<Value: PreferenceValue>: Sendable {
    public let key: String
    public let defaultValue: Value

    public init(_ key: String, default defaultValue: Value) {
        self.key = key
        self.defaultValue = defaultValue
    }

    public func value(in defaults: UserDefaults = .standard) -> Value {
        Value.read(key, from: defaults) ?? defaultValue
    }

    public func set(_ value: Value, in defaults: UserDefaults = .standard) {
        value.write(key, to: defaults)
    }

    /// Back to the default.
    public func reset(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}

/// Where features declare their settings.
public enum Preferences {}

/// A type a preference can hold: those `@AppStorage` stores, stored the way it stores them.
/// Enums with `String` or `Int` raw values only need to declare the conformance.
public protocol PreferenceValue: Sendable {
    static func read(_ key: String, from defaults: UserDefaults) -> Self?
    func write(_ key: String, to defaults: UserDefaults)
}

public extension PreferenceValue {
    static func read(_ key: String, from defaults: UserDefaults) -> Self? {
        defaults.object(forKey: key) as? Self
    }

    func write(_ key: String, to defaults: UserDefaults) {
        defaults.set(self, forKey: key)
    }
}

/// Numbers and switches also read from text: a launch argument such as `-controllerTimeoutMs 500`
/// reaches UserDefaults as the string "500", which `integer(forKey:)` reads but a cast to `Int`
/// doesn't. Text that isn't a number (or a yes or no) counts as not set.
extension Bool: PreferenceValue {
    public static func read(_ key: String, from defaults: UserDefaults) -> Bool? {
        switch defaults.object(forKey: key) {
        case let value as Bool:
            value
        case let text as String:
            switch text.trimmingCharacters(in: .whitespaces).lowercased() {
            case "yes", "true", "1": true
            case "no", "false", "0": false
            default: nil
            }
        default:
            nil
        }
    }
}

extension Int: PreferenceValue {
    public static func read(_ key: String, from defaults: UserDefaults) -> Int? {
        switch defaults.object(forKey: key) {
        case let value as Int:
            value
        case let text as String:
            Int(text.trimmingCharacters(in: .whitespaces))
        default:
            nil
        }
    }
}

extension Double: PreferenceValue {
    public static func read(_ key: String, from defaults: UserDefaults) -> Double? {
        switch defaults.object(forKey: key) {
        case let value as Double:
            value
        case let text as String:
            Double(text.trimmingCharacters(in: .whitespaces))
        default:
            nil
        }
    }
}

extension String: PreferenceValue {}

public extension PreferenceValue where Self: RawRepresentable, RawValue: PreferenceValue {
    static func read(_ key: String, from defaults: UserDefaults) -> Self? {
        RawValue.read(key, from: defaults).flatMap(Self.init(rawValue:))
    }

    func write(_ key: String, to defaults: UserDefaults) {
        rawValue.write(key, to: defaults)
    }
}
