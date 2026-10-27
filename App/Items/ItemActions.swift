import AnemoneUI
import SwiftUI

/// An icon button that shows its title while focused, like Wholphin's expandable buttons.
struct ActionButton: View {
    let title: String
    let systemImage: String
    var tint: Color?
    /// What VoiceOver reads in place of the title, where the title reads badly aloud, as a time.
    var spokenTitle: Text?
    /// For a button that turns something on or off, whether it's on: VoiceOver reads the title,
    /// then "On" or "Off".
    var isOn: Bool?
    let action: () -> Void

    var body: some View {
        let button = Button(action: action) {
            ActionLabel(title: title, systemImage: systemImage, tint: tint)
        }
        .accessibilityLabel(spokenTitle ?? Text(title))
        if let isOn {
            button
                .accessibilityValue(isOn ? Text("On") : Text("Off"))
                .accessibilityAddTraits(.isToggle)
        } else {
            button
        }
    }
}

private struct ActionLabel: View {
    let title: String
    let systemImage: String
    let tint: Color?
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.primary))
            if isFocused {
                Text(title)
                    .fixedSize()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: isFocused)
    }
}

/// Play, or Resume and Restart, for a playable item.
struct PlaybackButtons: View {
    let resumePosition: Duration?
    let focus: FocusState<ItemFocus?>.Binding
    /// Plays from a position, or from the beginning when `nil`.
    let play: (Duration?) -> Void

    var body: some View {
        if let resumePosition {
            ActionButton(
                title: String(localized: "Resume from \(resumePosition.clockText)"),
                systemImage: "play.fill",
                spokenTitle: Text("Resume from \(resumePosition.spokenPosition)"),
            ) {
                play(resumePosition)
            }
            .focused(focus, equals: .action(.play))
            .accessibilityIdentifier("action.resume")
            ActionButton(title: String(localized: "Restart"), systemImage: "arrow.counterclockwise") {
                play(nil)
            }
            .focused(focus, equals: .action(.restart))
            .accessibilityIdentifier("action.restart")
        } else {
            ActionButton(title: String(localized: "Play"), systemImage: "play.fill") {
                play(nil)
            }
            .focused(focus, equals: .action(.play))
            .accessibilityIdentifier("action.play")
        }
    }
}

/// Mark watched or unwatched. VoiceOver reads it as a switch, "Watched, on", since the title
/// says what pressing it does rather than how the item stands.
struct PlayedButton: View {
    let isPlayed: Bool
    let action: () -> Void

    var body: some View {
        ActionButton(
            title: isPlayed ? String(localized: "Mark as unwatched") : String(localized: "Mark as watched"),
            systemImage: isPlayed ? "eye" : "eye.slash",
            spokenTitle: Text("Watched"),
            isOn: isPlayed,
            action: action,
        )
        .accessibilityIdentifier("action.played")
    }
}

/// Add to or remove from favourites, with the theme's heart. VoiceOver reads it as a switch,
/// "Favorite, on".
struct FavoriteButton: View {
    let isFavorite: Bool
    let action: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        ActionButton(
            title: isFavorite ? String(localized: "Remove from favorites") : String(localized: "Add to favorites"),
            systemImage: isFavorite ? "heart.fill" : "heart",
            tint: isFavorite ? theme.favorite.color : nil,
            spokenTitle: Text("Favorite"),
            isOn: isFavorite,
            action: action,
        )
        .accessibilityIdentifier("action.favorite")
    }
}

/// What an item page's alert says.
enum ItemAlert: Hashable {
    /// Play or Shuffle found nothing the player can play, and why.
    case nothingToPlay(String)
    case failed(String)

    var title: String {
        switch self {
        case .nothingToPlay: String(localized: "Nothing to play")
        case .failed: String(localized: "Something went wrong")
        }
    }

    var message: String {
        switch self {
        case let .nothingToPlay(message), let .failed(message):
            message
        }
    }
}

extension View {
    func itemAlert(_ alert: Binding<ItemAlert?>) -> some View {
        self.alert(
            alert.wrappedValue?.title ?? "",
            isPresented: Binding { alert.wrappedValue != nil } set: { isPresented in
                if !isPresented {
                    alert.wrappedValue = nil
                }
            },
            presenting: alert.wrappedValue,
        ) { _ in
            Button("OK") {}
        } message: { alert in
            Text(alert.message)
        }
    }
}

/// A message filling a page that couldn't load, with somewhere for focus to rest so Back and
/// the sidebar still work.
struct PageMessage: View {
    let message: String

    @Environment(\.theme) private var theme

    var body: some View {
        Text(message)
            .foregroundStyle(theme.secondaryText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 1000)
            .focusable()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
