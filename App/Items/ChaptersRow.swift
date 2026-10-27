import AnemoneJellyfin
import AnemoneUI
import SwiftUI

/// Wholphin's chapter row (`ChapterRow`): a card per chapter with its image, name and start,
/// which plays the item from there. Hidden when the item has no chapters.
struct ChaptersRow: View {
    let chapters: [Chapter]
    let focus: FocusState<ItemFocus?>.Binding
    let memory: RowMemory
    /// Plays the item from a position.
    let play: (Duration) -> Void

    @Environment(BrowseModel.self) private var browse
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        if !chapters.isEmpty {
            CardRow(id: "chapters", title: "Chapters", elements: chapters, focus: focus, memory: memory) { chapter in
                Button {
                    play(chapter.start)
                } label: {
                    MediaCard(
                        title: chapter.name ?? "Chapter \(chapter.index + 1)",
                        subtitle: chapter.start.clockText,
                        imageURL: browse.session.imageURL(for: chapter, maxWidth: Int(Self.cardWidth * displayScale)),
                        shape: .thumb,
                        width: Self.cardWidth,
                    )
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private static let cardWidth = CardShape.thumb.cardWidth
}
