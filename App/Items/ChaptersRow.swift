import AnemoneJellyfin
import AnemoneUI
import SwiftUI

/// Wholphin's chapter row (`ChapterRow`): a card per chapter with its image, name and start,
/// which plays the item from there. Hidden when the item has no chapters. VoiceOver reads a
/// card's name and start, "Intro, starts at 10 seconds".
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
            CardRow(
                id: rowID,
                title: String(localized: "Chapters"),
                elements: chapters,
                focus: focus,
                memory: memory,
            ) { chapter in
                let name = chapter.name ?? String(localized: "Chapter \(chapter.index + 1)")
                Button {
                    play(chapter.start)
                } label: {
                    MediaCard(
                        title: name,
                        subtitle: chapter.start.clockText,
                        spokenSubtitle: Text("starts at \(chapter.start.spokenPosition)"),
                        imageURL: browse.session.imageURL(for: chapter, maxWidth: Int(Self.cardWidth * displayScale)),
                        shape: .thumb,
                        width: Self.cardWidth,
                    )
                }
                .buttonStyle(.borderless)
                .accessibilityHint("Plays from this chapter")
            }
        }
    }

    /// A row of its own for each item's chapters. Chapters are known by their index, so on the
    /// season page, where the row follows the selected episode, one row for every episode would
    /// enter a new episode's chapters at the index last focused in another's.
    private var rowID: String {
        "chapters.\(chapters.first?.itemID ?? "")"
    }

    private static let cardWidth = CardShape.thumb.cardWidth
}
