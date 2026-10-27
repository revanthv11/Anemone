import AnemoneCore
import SwiftUI

/// `@AppStorage(Preferences.someSetting)` in settings pages, with the preference's key and
/// default.
public extension AppStorage {
    init(_ preference: Preference<Value>, store: UserDefaults? = nil) where Value == Bool {
        self.init(wrappedValue: preference.defaultValue, preference.key, store: store)
    }

    init(_ preference: Preference<Value>, store: UserDefaults? = nil) where Value == Int {
        self.init(wrappedValue: preference.defaultValue, preference.key, store: store)
    }

    init(_ preference: Preference<Value>, store: UserDefaults? = nil) where Value == Double {
        self.init(wrappedValue: preference.defaultValue, preference.key, store: store)
    }

    init(_ preference: Preference<Value>, store: UserDefaults? = nil) where Value == String {
        self.init(wrappedValue: preference.defaultValue, preference.key, store: store)
    }

    init(
        _ preference: Preference<Value>,
        store: UserDefaults? = nil,
    ) where Value: PreferenceValue & RawRepresentable, Value.RawValue == String {
        self.init(wrappedValue: preference.defaultValue, preference.key, store: store)
    }

    init(
        _ preference: Preference<Value>,
        store: UserDefaults? = nil,
    ) where Value: PreferenceValue & RawRepresentable, Value.RawValue == Int {
        self.init(wrappedValue: preference.defaultValue, preference.key, store: store)
    }
}
