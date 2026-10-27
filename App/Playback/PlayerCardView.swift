import AnemonePlayback
import AnemoneUI
import SwiftUI

/// A feature's card over the video, such as Up Next: artwork, a title and message, and its
/// buttons, the first of which takes focus when the card appears.
struct PlayerCardView: View {
    let card: PlayerCard

    @FocusState private var focusedAction: PlayerAction.ID?

    var body: some View {
        HStack(alignment: .top, spacing: 32) {
            if let imageURL = card.imageURL {
                ArtworkImage(url: imageURL)
                    .frame(width: 320, height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            VStack(alignment: .leading, spacing: 12) {
                Text(card.title)
                    .font(.title3.bold())
                if let message = card.message {
                    Text(message)
                        .foregroundStyle(.secondary)
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
        // A container, so its buttons keep their own identifiers.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("player.card")
    }
}
