import AnemoneJellyfin
import SwiftUI

/// Wholphin's tab row (`TabRow`) along the top of a library: selecting a tab shows it. Coming
/// into the row from below focuses the tab that's showing, as Wholphin's does.
struct LibraryTabRow: View {
    let sections: [LibrarySection]
    @Binding var selection: LibrarySection

    @FocusState private var focused: LibrarySection?

    var body: some View {
        HStack(spacing: 16) {
            ForEach(sections, id: \.self) { section in
                Button(section.title) {
                    selection = section
                }
                .buttonStyle(TabButtonStyle(isSelected: section == selection))
                .focused($focused, equals: section)
                .accessibilityIdentifier("library.tab.\(section.rawValue)")
                .accessibilityAddTraits(section == selection ? .isSelected : [])
            }
        }
        .focusSection()
        .defaultFocus($focused, selection, priority: .userInitiated)
    }
}

extension LibrarySection {
    /// Wholphin's names for its library tabs.
    var title: String {
        switch self {
        case .recommended: "Recommended"
        case .library: "Library"
        case .collections: "Collections"
        case .genres: "Genres"
        case .studios: "Studios"
        }
    }
}

/// A tab: dim until its row has focus or it's the tab showing, which is underlined, and lit up
/// when focused, like Wholphin's tab and its indicator.
private struct TabButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        TabLabel(configuration: configuration, isSelected: isSelected)
    }

    private struct TabLabel: View {
        let configuration: ButtonStyleConfiguration
        let isSelected: Bool

        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .font(.callout.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(foreground)
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .background {
                    Capsule()
                        .fill(isFocused ? AnyShapeStyle(.white) : AnyShapeStyle(.clear))
                }
                .overlay(alignment: .bottom) {
                    Capsule()
                        .fill(.primary)
                        .frame(width: 32, height: 3)
                        .opacity(isSelected && !isFocused ? 1 : 0)
                }
                .scaleEffect(isFocused ? (configuration.isPressed ? 1.02 : 1.08) : 1)
                .animation(.easeOut(duration: 0.15), value: isFocused)
        }

        private var foreground: AnyShapeStyle {
            if isFocused {
                AnyShapeStyle(.black)
            } else if isSelected {
                AnyShapeStyle(.primary)
            } else {
                AnyShapeStyle(.secondary)
            }
        }
    }
}
