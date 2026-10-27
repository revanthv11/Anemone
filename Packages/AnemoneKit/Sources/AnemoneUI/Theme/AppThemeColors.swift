import AnemoneCore
import Foundation

/// The colour themes Settings › Appearance offers: Wholphin's `AppThemeColors`, in its order and
/// with its names.
public enum AppThemeColors: String, CaseIterable, PreferenceValue, Sendable {
    case purple
    case blue
    case green
    case orange
    case boldBlue
    case oledBlack
    case red
    case brown

    /// Wholphin's names; its OLED theme is called "Black".
    public var title: LocalizedStringResource {
        switch self {
        case .purple: LocalizedStringResource("Purple", bundle: .anemoneUI)
        case .blue: LocalizedStringResource("Blue", bundle: .anemoneUI)
        case .green: LocalizedStringResource("Green", bundle: .anemoneUI)
        case .orange: LocalizedStringResource("Orange", bundle: .anemoneUI)
        case .boldBlue: LocalizedStringResource("Bold Blue", bundle: .anemoneUI)
        case .oledBlack: LocalizedStringResource("Black", bundle: .anemoneUI)
        case .red: LocalizedStringResource("Red", bundle: .anemoneUI)
        case .brown: LocalizedStringResource("Brown", bundle: .anemoneUI)
        }
    }
}

public extension Preferences {
    /// Wholphin's "Application Theme" (`appThemeColors`), purple by default. A value this
    /// version doesn't know reads as purple, as Wholphin reads its `UNRECOGNIZED`.
    static let appThemeColors = Preference("appThemeColors", default: AppThemeColors.purple)
}
