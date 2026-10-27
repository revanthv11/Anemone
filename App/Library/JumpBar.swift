import AnemoneJellyfin
import AnemoneUI
import SwiftUI

/// Wholphin's alphabet bar: a column of letters down the right edge. Entering it focuses the
/// current letter. VoiceOver spells each one as a letter, and calls the current one selected.
///
/// It takes the height beside the grid and no more, its letters shrinking to fit when they must
/// (`JumpBarSizing`): a bar as tall as its full-size letters made the page taller than the screen.
/// They're fitted to the least room the bar has had, so they keep their size while the page
/// tucks its tabs away and brings them back.
struct JumpBar: View {
    let current: Character
    let onFocus: () -> Void
    /// Called as focus goes up past the top letter; `nil` when there's nowhere for it to go.
    let onLeaveTop: (() -> Void)?
    let onSelect: (Character) -> Void

    @FocusState private var focusedLetter: Character?
    /// The least height the bar has had beside the grid, once it's known.
    @State private var leastRoom: CGFloat?
    @Environment(\.theme) private var theme

    /// Stands for the stop above the top letter.
    private static let exit: Character = "^"
    private static let exitHeight: CGFloat = 2
    private static let sizing = JumpBarSizing(
        fullLetterSize: GridLayout.letterSize,
        minimumLetterSize: 16,
        spacing: 2,
        fixedHeight: exitHeight,
        fullFontSize: 20,
    )

    var body: some View {
        // As tall as the room beside the grid whatever the letters ask for, so they never push
        // the page, and sized to fit it in the same layout pass, so the first frame fits too.
        GeometryReader { proxy in
            let room = proxy.size.height
            let count = LibraryJump.letters.count
            let letterSize = Self.sizing.letterSize(
                count: count,
                fitting: Self.sizing.roomToFit(now: room, least: leastRoom),
            )
            let overflows = Self.sizing.overflows(count: count, letterSize: letterSize, height: room)
            letters(size: letterSize)
                // Centred, as Wholphin centres its bar; but from the top when even the smallest
                // letters don't fit, so they run off the bottom rather than up over the tabs or
                // the details header.
                .frame(width: proxy.size.width, height: room, alignment: overflows ? .top : .center)
        }
        .frame(width: GridLayout.letterSize)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            leastRoom = Self.sizing.leastRoom(leastRoom, measuring: height)
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

    private func letters(size letterSize: CGFloat) -> some View {
        VStack(spacing: Self.sizing.spacing) {
            // An invisible stop above #, so Up from there comes here, and on to the page's tabs,
            // rather than to the sidebar's title, or nowhere while the tabs are tucked away.
            // Not quite clear: tvOS won't focus what it can't see.
            theme.onBackground.withAlpha(0.02).color
                .frame(width: GridLayout.letterSize, height: Self.exitHeight)
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
                .buttonStyle(
                    LetterButtonStyle(
                        isCurrent: letter == current,
                        size: letterSize,
                        fontSize: Self.sizing.fontSize(letterSize: letterSize),
                    ),
                )
                .focused($focusedLetter, equals: letter)
                .accessibilityLabel(Text(verbatim: String(letter)).speechSpellsOutCharacters())
                .accessibilityAddTraits(letter == current ? .isSelected : [])
                .accessibilityIdentifier("grid.letter.\(letter)")
            }
        }
    }
}

private struct LetterButtonStyle: ButtonStyle {
    let isCurrent: Bool
    let size: CGFloat
    let fontSize: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        LetterLabel(
            label: configuration.label,
            isCurrent: isCurrent,
            isPressed: configuration.isPressed,
            size: size,
            fontSize: fontSize,
        )
    }
}

/// A letter as Wholphin draws it: lit up when focused, in the theme's highlight when it's the
/// current one, quiet otherwise.
private struct LetterLabel: View {
    let label: ButtonStyleConfiguration.Label
    let isCurrent: Bool
    let isPressed: Bool
    /// Its height, and its circle's size; the column keeps its full width.
    let size: CGFloat
    let fontSize: CGFloat

    @Environment(\.isFocused) private var isFocused
    @Environment(\.theme) private var theme

    var body: some View {
        label
            .font(.system(size: fontSize, weight: isCurrent ? .bold : .medium))
            .foregroundStyle(foreground)
            .frame(width: GridLayout.letterSize, height: size)
            .background {
                Circle()
                    .fill(isFocused ? theme.focusedPlatter : theme.focusedPlatter.withAlpha(0))
            }
            .scaleEffect(isFocused ? (isPressed ? 1.1 : 1.3) : 1)
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }

    private var foreground: ThemeColor {
        if isFocused {
            theme.onFocusedPlatter
        } else if isCurrent {
            theme.highlight
        } else {
            theme.secondaryText
        }
    }
}
