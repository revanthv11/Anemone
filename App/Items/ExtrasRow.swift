import AnemoneJellyfin
import AnemonePlayback
import AnemoneUI
import SwiftUI

/// Wholphin's Extras row (`ExtrasRow`): special features such as featurettes and deleted scenes,
/// a card per extra, or per kind when there are several of it. Selecting an extra plays it; a
/// kind's card lists its extras to pick from. Hidden when there are none.
struct ExtrasRow: View {
    let extras: [ExtrasEntry]
    let focus: FocusState<ItemFocus?>.Binding
    let memory: RowMemory

    @Environment(BrowseModel.self) private var browse
    @State private var playback: PlaybackRequest?
    /// The kind whose extras are being picked from.
    @State private var picking: ExtrasEntry?
    @State private var isPicking = false

    var body: some View {
        if !extras.isEmpty {
            CardRow(id: "extras", title: "Extras", elements: extras, focus: focus, memory: memory) { entry in
                Button {
                    if let extra = entry.items.first, entry.items.count == 1 {
                        play(extra)
                    } else {
                        picking = entry
                        isPicking = true
                    }
                } label: {
                    ExtrasCard(entry: entry)
                }
                .buttonStyle(.borderless)
            }
            .confirmationDialog(
                picking?.kind.title ?? "",
                isPresented: $isPicking,
                titleVisibility: .visible,
                presenting: picking,
            ) { entry in
                ForEach(entry.items) { extra in
                    Button(extra.item.name.isEmpty ? entry.kind.singularTitle : extra.item.name) {
                        play(extra)
                    }
                    .accessibilityIdentifier("extra.\(extra.id)")
                }
            }
            .player($playback) {}
        }
    }

    /// From where it was left, as episode cards play.
    private func play(_ extra: ItemDetails) {
        playback = browse.playback(of: extra, from: extra.userState.resumePosition)
    }
}

/// An extra's 16:9 card: the extra's own still, or the first of its kind's.
private struct ExtrasCard: View {
    let entry: ExtrasEntry

    @Environment(BrowseModel.self) private var browse
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        MediaCard(
            title: entry.title,
            subtitle: entry.subtitle,
            imageURL: browse.imageURL(
                entry.items.first?.item.thumbImage,
                width: CardShape.thumb.cardWidth * displayScale,
            ),
            shape: .thumb,
            width: CardShape.thumb.cardWidth,
            progress: entry.progress,
            badges: CardBadges(isPlayed: entry.isPlayed),
        )
    }
}

extension View {
    /// Loads `extras` for the item `id` names, and again whenever it changes. What can't be
    /// loaded is left out, as Wholphin does, though a revoked token still sends Home to sign-in.
    ///
    /// The first item's extras are asked for at once. When the item changes after that, as when
    /// focus moves along a season's episodes, the old item's extras go at once, and the new ones
    /// are asked for only once the item has stayed for 300 ms, so moving along the row doesn't
    /// send a request per card.
    func itemExtras(_ extras: Binding<ItemExtras>, of id: MediaItem.ID?) -> some View {
        modifier(ItemExtrasLoader(extras: extras, id: id))
    }
}

private struct ItemExtrasLoader: ViewModifier {
    @Binding var extras: ItemExtras
    let id: MediaItem.ID?

    @Environment(BrowseModel.self) private var browse
    /// Set once extras have been asked for, so later items wait for focus to settle.
    @State private var hasAsked = false

    func body(content: Content) -> some View {
        content
            .task(id: id) {
                guard let id else {
                    extras = ItemExtras()
                    return
                }
                guard extras.itemID != id else { return }
                if extras.itemID != nil {
                    extras = ItemExtras()
                }
                if hasAsked {
                    do {
                        try await Task.sleep(for: .milliseconds(300))
                    } catch {
                        // The item changed again first; its own task asks instead.
                        return
                    }
                }
                hasAsked = true
                let session = browse.session
                let loaded = await browse.optional(attempt { try await session.itemExtras(id: id) })
                // A newer item replaced this one meanwhile.
                guard !Task.isCancelled, let loaded else { return }
                extras = loaded
            }
    }
}
