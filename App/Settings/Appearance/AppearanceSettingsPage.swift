import AnemoneCore
import AnemoneUI
import SwiftUI

/// Settings › Appearance: Wholphin's "Application Theme", its eight colour themes in its order.
/// The themes are listed on the page itself, so picking one shows it at once: the app's root
/// reads the same setting (`appTheme()`), and everything changes as soon as it does.
struct AppearanceSettingsPage: View {
    @AppStorage(Preferences.appThemeColors) private var themeColors

    var body: some View {
        List {
            Section {
                ForEach(AppThemeColors.allCases, id: \.self) { colors in
                    Button {
                        themeColors = colors
                    } label: {
                        ThemeChoice(colors: colors, isChosen: colors == themeColors)
                    }
                    .accessibilityIdentifier("settings.appTheme.\(colors.rawValue)")
                    .accessibilityAddTraits(colors == themeColors ? .isSelected : [])
                }
            } header: {
                Text("Application Theme")
            } footer: {
                Text("The colours of backgrounds, focused cards, progress bars and badges.")
            }
        }
        .navigationTitle("Appearance")
    }
}

/// A theme's name with a swatch of its accent on its background, and a check when it's the one
/// chosen.
private struct ThemeChoice: View {
    let colors: AppThemeColors
    let isChosen: Bool

    var body: some View {
        let theme = Theme(colors)
        HStack(spacing: 24) {
            Circle()
                .fill(theme.background)
                .overlay {
                    Circle()
                        .fill(theme.accent)
                        .padding(8)
                }
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
            Text(colors.title)
            Spacer()
            if isChosen {
                Image(systemName: "checkmark")
                    .accessibilityHidden(true)
            }
        }
    }
}
