import SwiftUI

/// An icon button that shows its title while focused, like Wholphin's expandable buttons.
struct ActionButton: View {
    let title: String
    let systemImage: String
    var tint: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ActionLabel(title: title, systemImage: systemImage, tint: tint)
        }
        .accessibilityLabel(title)
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
///
/// Playback is Phase 3, so these don't play anything yet: they say so instead, and a note beside
/// them says it up front.
struct PlaybackButtons: View {
    let resumePosition: Duration?
    let focus: FocusState<ItemFocus?>.Binding
    @Binding var alert: ItemAlert?

    var body: some View {
        if let resumePosition {
            ActionButton(title: "Resume from \(resumePosition.clockText)", systemImage: "play.fill") {
                alert = .playbackUnavailable(resumeAt: resumePosition)
            }
            .focused(focus, equals: .action(.play))
            .accessibilityIdentifier("action.resume")
            ActionButton(title: "Restart", systemImage: "arrow.counterclockwise") {
                alert = .playbackUnavailable(resumeAt: nil)
            }
            .focused(focus, equals: .action(.restart))
        } else {
            ActionButton(title: "Play", systemImage: "play.fill") {
                alert = .playbackUnavailable(resumeAt: nil)
            }
            .focused(focus, equals: .action(.play))
            .accessibilityIdentifier("action.play")
        }
    }
}

/// Marks the play buttons as not wired up yet.
struct PlaybackNotWiredNote: View {
    var body: some View {
        Label("Playback isn't wired up yet (Phase 3)", systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

/// Mark watched or unwatched.
struct PlayedButton: View {
    let isPlayed: Bool
    let action: () -> Void

    var body: some View {
        ActionButton(
            title: isPlayed ? "Mark as unwatched" : "Mark as watched",
            systemImage: isPlayed ? "eye" : "eye.slash",
            action: action,
        )
        .accessibilityIdentifier("action.played")
    }
}

/// Add to or remove from favourites.
struct FavoriteButton: View {
    let isFavorite: Bool
    let action: () -> Void

    var body: some View {
        ActionButton(
            title: isFavorite ? "Remove from favorites" : "Add to favorites",
            systemImage: isFavorite ? "heart.fill" : "heart",
            tint: isFavorite ? .red : nil,
            action: action,
        )
        .accessibilityIdentifier("action.favorite")
    }
}

/// What an item page's alert says.
enum ItemAlert: Hashable {
    case playbackUnavailable(resumeAt: Duration?)
    case failed(String)

    var title: String {
        switch self {
        case .playbackUnavailable: "Playback isn't available yet"
        case .failed: "Something went wrong"
        }
    }

    var message: String {
        switch self {
        case let .playbackUnavailable(position?):
            "Anemone can't play anything until Phase 3. This would resume from \(position.clockText)."
        case .playbackUnavailable(nil):
            "Anemone can't play anything until Phase 3."
        case let .failed(message):
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

    var body: some View {
        Text(message)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 1000)
            .focusable()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
