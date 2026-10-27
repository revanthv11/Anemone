/// Light or dark. Wholphin defines both for every theme but always shows the dark one
/// (`MainActivity` passes `darkTheme = true`), and so does Anemone; the light ones are kept for
/// the iOS app.
public enum ThemeScheme: String, CaseIterable, Sendable {
    case light
    case dark
}

/// One theme's colours in one scheme, by the Material 3 roles Wholphin's `ui/theme/colors`
/// tables set, with Wholphin's values. Views use `Theme`'s roles, which say what each colour is
/// for; this is what they come from.
///
/// `border` is TV Material's role for focus borders: Wholphin sets it to `inversePrimary`, and
/// it's the colour that shows a theme most (focused cards, the seek bar, selected items).
public struct ThemePalette: Hashable, Sendable {
    public let primary: ThemeColor
    public let onPrimary: ThemeColor
    public let primaryContainer: ThemeColor
    public let onPrimaryContainer: ThemeColor
    public let secondary: ThemeColor
    public let onSecondary: ThemeColor
    public let secondaryContainer: ThemeColor
    public let onSecondaryContainer: ThemeColor
    public let tertiary: ThemeColor
    public let onTertiary: ThemeColor
    public let tertiaryContainer: ThemeColor
    public let onTertiaryContainer: ThemeColor
    public let error: ThemeColor
    public let onError: ThemeColor
    public let errorContainer: ThemeColor
    public let onErrorContainer: ThemeColor
    public let background: ThemeColor
    public let onBackground: ThemeColor
    public let surface: ThemeColor
    public let onSurface: ThemeColor
    public let surfaceVariant: ThemeColor
    public let onSurfaceVariant: ThemeColor
    public let scrim: ThemeColor
    public let inverseSurface: ThemeColor
    public let inverseOnSurface: ThemeColor
    public let inversePrimary: ThemeColor
    public let border: ThemeColor
}

public extension ThemePalette {
    /// Wholphin's palette for a theme and scheme.
    static func wholphin(_ colors: AppThemeColors, _ scheme: ThemeScheme) -> ThemePalette {
        let (light, dark): (ThemePalette, ThemePalette) =
            switch colors {
            case .purple: (.purpleLight, .purpleDark)
            case .blue: (.blueLight, .blueDark)
            case .green: (.greenLight, .greenDark)
            case .orange: (.orangeLight, .orangeDark)
            case .boldBlue: (.boldBlueLight, .boldBlueDark)
            case .oledBlack: (.oledBlackLight, .oledBlackDark)
            case .red: (.redLight, .redDark)
            case .brown: (.brownLight, .brownDark)
            }
        return scheme == .light ? light : dark
    }
}
