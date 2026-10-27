import AnemoneUI
import SwiftUI

/// A season tab on the season page: highlighted when focused, and marked while its season is
/// shown, in the theme's platter colours: light with dark text when focused, a quiet fill when
/// chosen, and quieter text otherwise.
struct SeasonTabStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        TabBody(configuration: configuration, isSelected: isSelected)
    }

    private struct TabBody: View {
        let configuration: ButtonStyleConfiguration
        let isSelected: Bool
        @Environment(\.isFocused) private var isFocused
        @Environment(\.theme) private var theme

        var body: some View {
            configuration.label
                .font(.callout.weight(isSelected ? .bold : .regular))
                .foregroundStyle(text)
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .background(fill, in: .capsule)
                .scaleEffect(isFocused ? 1.08 : configuration.isPressed ? 0.98 : 1)
                .animation(.easeOut(duration: 0.15), value: isFocused)
        }

        private var text: ThemeColor {
            isFocused ? theme.onFocusedPlatter : isSelected ? theme.onPlatter : theme.secondaryText
        }

        private var fill: ThemeColor {
            isFocused ? theme.focusedPlatter : isSelected ? theme.platter : theme.platter.withAlpha(0)
        }
    }
}
