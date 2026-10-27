import AnemoneJellyfin
import AnemonePlayback
import AnemoneUI
import SwiftUI

/// The video's chapters with their images, starting with the one playing in focus; choosing one
/// jumps there. Ported from Wholphin's `ChapterRowOverlay` and `ChapterCard`.
struct ChapterRow: View {
    let chapters: [Chapter]
    let itemID: MediaItem.ID
    /// Where playback is, for which chapter starts in focus.
    let playing: Duration
    let session: JellyfinSession
    var focus: FocusState<OverlayFocus?>.Binding
    let choose: (Chapter) -> Void

    var body: some View {
        OverlayRow(title: "Chapters") {
            ForEach(chapters) { chapter in
                Button {
                    choose(chapter)
                } label: {
                    OverlayCard(
                        imageURL: session.chapterImageURL(chapter, of: itemID, maxWidth: 480),
                        placeholder: "film",
                        title: chapter.name ?? "Chapter \(chapter.index + 1)",
                        detail: chapter.start.timecode,
                    )
                }
                .buttonStyle(.card)
                .focused(focus, equals: .chapter(chapter.index))
                .accessibilityIdentifier("player.chapter.\(chapter.index)")
            }
        }
        .defaultFocus(focus, chapters.index(at: playing).map { .chapter(chapters[$0].index) })
    }
}

/// What plays after this entry; choosing one plays it. Ported from Wholphin's `QueueRowOverlay`.
/// Each entry shows its artwork when the page that queued it gave one.
struct QueueRow: View {
    let entries: [(index: Int, entry: PlaybackQueue.Entry)]
    var focus: FocusState<OverlayFocus?>.Binding
    let play: (Int) -> Void

    var body: some View {
        OverlayRow(title: "Queue") {
            ForEach(entries, id: \.index) { index, entry in
                Button {
                    play(index)
                } label: {
                    OverlayCard(
                        imageURL: entry.metadata.artworkURL,
                        placeholder: "play.rectangle",
                        title: entry.metadata.title,
                        detail: entry.metadata.subtitle,
                    )
                }
                .buttonStyle(.card)
                .focused(focus, equals: .queueEntry(index))
                .accessibilityIdentifier("player.queue.\(index)")
            }
        }
        .defaultFocus(focus, entries.first.map { .queueEntry($0.index) })
    }
}

/// A titled row of cards that scrolls sideways, as tall as its cards.
private struct OverlayRow<Cards: View>: View {
    let title: String
    @ViewBuilder let cards: () -> Cards

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 40, content: cards)
                    .padding(.vertical, 24)
            }
            .scrollClipDisabled()
            .fixedSize(horizontal: false, vertical: true)
            .focusSection()
        }
    }
}

/// Wholphin's chapter card: the image, with the title and a detail over its bottom edge.
private struct OverlayCard: View {
    let imageURL: URL?
    /// An SF Symbol for while the image loads, or when there's none.
    let placeholder: String
    let title: String
    let detail: String?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.white.opacity(0.1)
            Image(systemName: placeholder)
                .font(.title)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            ArtworkImage(url: imageURL)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.black.opacity(0.55))
        }
        .frame(width: 320, height: 180)
    }
}
