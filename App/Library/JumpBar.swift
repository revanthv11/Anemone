import AnemoneJellyfin
import SwiftUI

/// Wholphin's alphabet bar: a column of letters down the right edge. Entering it focuses the
/// current letter.
struct JumpBar: View {
    let current: Character
    let onFocus: () -> Void
    /// Called as focus goes up past the top letter; `nil` when there's nowhere for it to go.
    let onLeaveTop: (() -> Void)?
    let onSelect: (Character) -> Void

    @FocusState private var focusedLetter: Character?

    /// Stands for the stop above the top letter.
    private static let exit: Character = "^"

    var body: some View {
        VStack(spacing: 2) {
            // An invisible stop above #, so Up from there comes here, and on to the page's tabs,
            // rather than to the sidebar's title, or nowhere while the tabs are tucked away.
            // Not quite clear: tvOS won't focus what it can't see.
            Color.white.opacity(0.02)
                .frame(width: GridLayout.letterSize, height: 2)
                .focusable(onLeaveTop != nil)
                .focusEffectDisabled()
                .focused($focusedLetter, equals: Self.exit)
                .accessibilityHidden(true)
            ForEach(LibraryJump.letters, id: \.self) { letter in
                Button {
                    onSelect(letter)
                } label: {
                    Text(String(letter))
                }
                .buttonStyle(LetterButtonStyle(isCurrent: letter == current))
                .focused($focusedLetter, equals: letter)
                .accessibilityIdentifier("grid.letter.\(letter)")
            }
        }
        .focusSection()
        .defaultFocus($focusedLetter, current, priority: .userInitiated)
        .onChange(of: focusedLetter) { _, letter in
            if letter != nil {
                onFocus()
            }
            if letter == Self.exit {
                onLeaveTop?()
            }
        }
    }
}

private struct LetterButtonStyle: ButtonStyle {
    let isCurrent: Bool

    func makeBody(configuration: Configuration) -> some View {
        LetterLabel(label: configuration.label, isCurrent: isCurrent, isPressed: configuration.isPressed)
    }
}

private struct LetterLabel: View {
    let label: ButtonStyleConfiguration.Label
    let isCurrent: Bool
    let isPressed: Bool

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        label
            .font(.system(size: 20, weight: isCurrent ? .bold : .medium))
            .foregroundStyle(foreground)
            // Shorter when the page has less room, as under the tabs, so the bar fits from # to Z
            // and its top stays below the tabs.
            .frame(
                minWidth: GridLayout.letterSize,
                maxWidth: GridLayout.letterSize,
                minHeight: GridLayout.minLetterHeight,
                maxHeight: GridLayout.letterSize,
            )
            .background {
                Circle()
                    .fill(isFocused ? AnyShapeStyle(.white) : AnyShapeStyle(.clear))
            }
            .scaleEffect(isFocused ? (isPressed ? 1.1 : 1.3) : 1)
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }

    private var foreground: AnyShapeStyle {
        if isFocused {
            AnyShapeStyle(.black)
        } else if isCurrent {
            AnyShapeStyle(.tint)
        } else {
            AnyShapeStyle(.secondary)
        }
    }
}
