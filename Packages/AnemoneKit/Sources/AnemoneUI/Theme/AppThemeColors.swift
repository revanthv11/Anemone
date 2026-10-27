import AnemoneCore

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
    public var title: String {
        switch self {
        case .purple: "Purple"
        case .blue: "Blue"
        case .green: "Green"
        case .orange: "Orange"
        case .boldBlue: "Bold Blue"
        case .oledBlack: "Black"
        case .red: "Red"
        case .brown: "Brown"
        }
    }
}

public extension Preferences {
    /// Wholphin's "Application Theme" (`appThemeColors`), purple by default. A value this
    /// version doesn't know reads as purple, as Wholphin reads its `UNRECOGNIZED`.
    static let appThemeColors = Preference("appThemeColors", default: AppThemeColors.purple)
}
