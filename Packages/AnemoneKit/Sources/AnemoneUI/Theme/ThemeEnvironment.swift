import AnemoneCore
import SwiftUI

public extension EnvironmentValues {
    /// The colour theme, which `appTheme()` sets from Settings › Appearance.
    @Entry var theme = Theme.standard
}

public extension View {
    /// Shows this view in the theme chosen in Settings › Appearance, changing as soon as the
    /// choice does: puts the theme in the environment, tints controls with its accent and, as
    /// Wholphin does, always uses the dark scheme. The app's root has it; so does any view
    /// hosted on its own, like a `UIHostingController`'s, which doesn't inherit the environment.
    func appTheme() -> some View {
        modifier(AppThemeModifier())
    }

    /// Fills the space behind this view, safe areas included, with the theme's background.
    /// Put it inside `appTheme()`, which provides the theme.
    func themeBackground() -> some View {
        modifier(ThemeBackgroundModifier())
    }
}

private struct AppThemeModifier: ViewModifier {
    @AppStorage(Preferences.appThemeColors) private var colors

    func body(content: Content) -> some View {
        let theme = Theme(colors)
        content
            .environment(\.theme, theme)
            .tint(theme.accent.color)
            .preferredColorScheme(.dark)
    }
}

private struct ThemeBackgroundModifier: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .background {
                theme.background.color
                    .ignoresSafeArea()
            }
    }
}
