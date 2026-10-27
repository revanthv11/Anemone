import AnemoneJellyfin
import AnemonePlayback
import AnemoneUI
import SwiftUI

/// The video's chapters with their images, starting with the one playing in focus; choosing one
/// jumps there. Ported from Wholphin's `ChapterRowOverlay` and `ChapterCard`.
struct ChapterRow: View {
    let chapters: [Chapter]
    /// Where playback is, for which chapter starts in focus.
    let playing: Duration
    let session: JellyfinSession
    var focus: FocusState<OverlayFocus?>.Binding
    let choose: (Chapter) -> Void

    /// Where focus starts: the card of the chapter playing at `position`.
    static func playingFocus(_ chapters: [Chapter], at position: Duration) -> OverlayFocus? {
        chapters.chapter(at: position).map { .chapter($0.id) }
    }

    var body: some View {
        let playingChapter = chapters.chapter(at: playing)?.id
        // Not lazy, so a late chapter's card is there for focus to move to as the row opens.
        // Videos have few chapters.
        OverlayRow(title: String(localized: "Chapters"), isLazy: false) {
            ForEach(chapters) { chapter in
                let title = chapter.name ?? String(localized: "Chapter \(chapter.index + 1)")
                Button {
                    choose(chapter)
                } label: {
                    OverlayCard(
                        imageURL: session.imageURL(for: chapter, maxWidth: 480),
                        placeholder: "film",
                        title: title,
                        detail: chapter.start.clockText,
                    )
                }
                .buttonStyle(.card)
                .focused(focus, equals: .chapter(chapter.id))
                // The chapter and where it starts; the one playing reads as selected.
                .accessibilityLabel(title)
                .accessibilityValue(Text("starts at \(chapter.start.spokenPosition)"))
                .accessibilityAddTraits(chapter.id == playingChapter ? .isSelected : [])
                .accessibilityIdentifier("player.chapter.\(chapter.id)")
            }
        }
        .defaultFocus(focus, Self.playingFocus(chapters, at: playing))
    }
}

/// What plays after this entry; choosing one plays it. Ported from Wholphin's `QueueRowOverlay`.
/// Each entry shows its artwork when the page that queued it gave one.
struct QueueRow: View {
    let entries: [(index: Int, entry: PlaybackQueue.Entry)]
    var focus: FocusState<OverlayFocus?>.Binding
    let play: (Int) -> Void

    var body: some View {
        OverlayRow(title: String(localized: "Queue")) {
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
                .accessibilityLabel(entry.metadata.title)
                .accessibilityValue(entry.metadata.subtitle ?? "")
                .accessibilityIdentifier("player.queue.\(index)")
            }
        }
        .defaultFocus(focus, entries.first.map { .queueEntry($0.index) })
    }
}

/// A titled row of cards that scrolls sideways, as tall as its cards. A lazy row makes only the
/// cards near the start, so it suits rows whose focus starts on the first card.
private struct OverlayRow<Cards: View>: View {
    let title: String
    var isLazy = true
    @ViewBuilder let cards: () -> Cards

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(theme.onBackground)
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal) {
                Group {
                    if isLazy {
                        LazyHStack(spacing: 40, content: cards)
                    } else {
                        HStack(spacing: 40, content: cards)
                    }
                }
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

    @Environment(\.theme) private var theme

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            theme.surfaceVariant.color
            Image(systemName: placeholder)
                .font(.title)
                .foregroundStyle(theme.onSurfaceVariant)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
            ArtworkImage(url: imageURL)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(theme.onBackground)
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.scrim.withAlpha(0.55))
        }
        .frame(width: 320, height: 180)
    }
}
