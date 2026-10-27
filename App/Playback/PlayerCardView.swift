import AnemonePlayback
import AnemoneUI
import SwiftUI

/// A feature's card over the video, such as Up Next: artwork, a title and message, and its
/// buttons, the first of which takes focus when the card appears.
struct PlayerCardView: View {
    let card: PlayerCard

    @Environment(\.theme) private var theme
    @FocusState private var focusedAction: PlayerAction.ID?

    var body: some View {
        HStack(alignment: .top, spacing: 32) {
            if let imageURL = card.imageURL {
                ArtworkImage(url: imageURL)
                    .frame(width: 320, height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 12) {
                // The card's own label reads the title, so it's said once.
                Text(card.title)
                    .font(.title3.bold())
                    .foregroundStyle(theme.onSurface)
                    .accessibilityHidden(true)
                if let message = card.message {
                    // Its own element: tvOS doesn't always read a container's value, so the
                    // message ("Next: …, starting in 10 s") is read as text in the card.
                    Text(message)
                        .foregroundStyle(theme.secondaryText)
                        .accessibilityIdentifier("player.card.message")
                }
                HStack(spacing: 24) {
                    ForEach(card.actions) { action in
                        Button(action.title, action: action.perform)
                            .focused($focusedAction, equals: action.id)
                            .accessibilityIdentifier("player.card.\(action.id)")
                    }
                }
                .padding(.top, 12)
            }
        }
        .padding(40)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        .focusSection()
        .defaultFocus($focusedAction, card.actions.first?.id)
        .onAppear {
            focusedAction = card.actions.first?.id
        }
        // A container, so its buttons and message keep their own elements. Named by its title,
        // which VoiceOver reads as focus moves into it, before the button focused.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(card.title)
        .accessibilityIdentifier("player.card")
    }
}
