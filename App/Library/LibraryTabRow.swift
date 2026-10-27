import AnemoneJellyfin
import AnemoneUI
import SwiftUI

/// Wholphin's tab row (`TabRow`) along the top of a library: selecting a tab shows it. Coming
/// into the row from below focuses the tab that's showing, as Wholphin's does.
struct LibraryTabRow: View {
    let sections: [LibrarySection]
    @Binding var selection: LibrarySection
    /// The page's, so it can send focus up to the tabs.
    let focus: FocusState<LibrarySection?>.Binding

    var body: some View {
        HStack(spacing: 16) {
            ForEach(sections, id: \.self) { section in
                Button(section.title) {
                    selection = section
                }
                .buttonStyle(TabButtonStyle(isSelected: section == selection))
                .focused(focus, equals: section)
                .accessibilityIdentifier("library.tab.\(section.rawValue)")
                .accessibilityAddTraits(section == selection ? .isSelected : [])
            }
        }
        // Across the page, so Up reaches the tabs from the header's buttons on the right too, not
        // only from those under the tabs.
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
        .defaultFocus(focus, selection, priority: .userInitiated)
    }
}

extension LibrarySection {
    /// Wholphin's names for its library tabs.
    var title: String {
        switch self {
        case .recommended: String(localized: "Recommended")
        case .library: String(localized: "Library")
        case .collections: String(localized: "Collections")
        case .genres: String(localized: "Genres")
        case .studios: String(localized: "Studios")
        }
    }
}

/// A tab: dim until its row has focus or it's the tab showing, which is underlined in the
/// theme's accent, and lit up when focused, like Wholphin's tab and its indicator.
private struct TabButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        TabLabel(configuration: configuration, isSelected: isSelected)
    }

    private struct TabLabel: View {
        let configuration: ButtonStyleConfiguration
        let isSelected: Bool

        @Environment(\.isFocused) private var isFocused
        @Environment(\.theme) private var theme

        var body: some View {
            configuration.label
                .font(.callout.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(foreground)
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .background {
                    Capsule()
                        .fill(isFocused ? theme.focusedPlatter : theme.focusedPlatter.withAlpha(0))
                }
                .overlay(alignment: .bottom) {
                    Capsule()
                        .fill(theme.accent)
                        .frame(width: 32, height: 3)
                        .opacity(isSelected && !isFocused ? 1 : 0)
                }
                .scaleEffect(isFocused ? (configuration.isPressed ? 1.02 : 1.08) : 1)
                .animation(.easeOut(duration: 0.15), value: isFocused)
        }

        private var foreground: ThemeColor {
            if isFocused {
                theme.onFocusedPlatter
            } else if isSelected {
                theme.onBackground
            } else {
                theme.secondaryText
            }
        }
    }
}
