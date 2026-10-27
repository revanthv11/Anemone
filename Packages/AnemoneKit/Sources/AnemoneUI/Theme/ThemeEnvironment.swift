import AnemoneCore
import SwiftUI

public extension EnvironmentValues {
    /// The colour theme, which `appTheme()` sets from Settings › Appearance.
    ///
    /// Without `appTheme()` above it, this is `Theme.standard`, purple, whatever the user chose.
    /// That's the case in any view hosted on its own, like a `UIHostingController`'s root, which
    /// doesn't inherit the app's environment: give such a root `.appTheme()`.
    @Entry var theme = Theme.standard
}

public extension View {
    /// Shows this view in the theme chosen in Settings › Appearance, changing as soon as the
    /// choice does: puts the theme in the environment and, as Wholphin does, always uses the
    /// dark scheme. It leaves the tint alone, so system controls keep tvOS's own focus look;
    /// the theme colours Anemone's own components.
    ///
    /// The app's root has it. So must the root of any view hosted on its own, like a
    /// `UIHostingController`'s (the player overlay, the screensaver), or it shows purple.
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
        content
            .environment(\.theme, Theme(colors))
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
