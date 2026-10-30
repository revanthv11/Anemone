import AnemoneJellyfin
import AnemoneUI
import SwiftUI

/// A title in a library's list layout, ported from Wholphin's `CollectionFolderList` rows: a
/// heart for favourites, the title over its year or episode, then the running time and a check
/// for watched titles, or a series' unwatched count. The dense list puts the year beside the
/// title and drops the second line.
///
/// VoiceOver reads it as a card reads: the title, the year or episode, the running time, then
/// the marks.
struct LibraryListRow: View {
    let entry: LibraryEntry?
    let isDense: Bool

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: "heart.fill")
                .foregroundStyle(theme.favorite)
                .opacity(entry?.details?.userState.isFavorite == true ? 1 : 0)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .lineLimit(1)
                if !isDense {
                    Text(subtitle ?? " ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 20)
            trailing
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .font(isDense ? .callout : .body)
        .padding(.horizontal, 24)
        .padding(.vertical, isDense ? 10 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel { _ in
            if let item {
                Text(verbatim: item.displayTitle)
                if let spoken = item.spokenSubtitle ?? subtitle.map(Text.init(verbatim:)) {
                    spoken
                }
                if let runtime = shownRuntime {
                    Text(runtime, format: .units(allowed: [.hours, .minutes], width: .wide))
                }
                ForEach(CardSpokenMark.marks(for: CardMarks(badges: shownBadges)), id: \.self) { mark in
                    Text(mark.spoken)
                }
            }
        }
        // The card menu, which a MediaCard asks for itself: the row's button opens it.
        // With its details, as the grid card gives them, so the menu knows what's watched and a favourite.
        .cardMenuItem(
            entry?.details.map { CardMenuItem($0) } ?? item.map(CardMenuItem.init),
            marks: CardMarks(badges: shownBadges),
        )
    }

    private var item: MediaItem? {
        entry?.item
    }

    /// Movies and albums put their year beside the title in the dense list, and series their years.
    private var title: String {
        guard let item else { return " " }
        guard isDense, let subtitle else { return item.displayTitle }
        return String(localized: "\(item.displayTitle) (\(subtitle))")
    }

    /// A series' years, an episode's number and name, or the year.
    private var subtitle: String? {
        switch item?.kind {
        case .series:
            entry?.details?.seriesYears ?? item?.year.map(String.init)
        case .episode, .season:
            item?.subtitle
        default:
            item?.year.map(String.init)
        }
    }

    /// Series and collections show how many episodes are left instead of a running time.
    private var isFolder: Bool {
        item?.kind == .series || item?.kind == .collection
    }

    private var shownRuntime: Duration? {
        guard !isFolder, let runtime = item?.runtime, runtime > .zero else { return nil }
        return runtime.roundedToMinutes
    }

    /// The marks the row draws: the heart, and the check or the unwatched count.
    private var shownBadges: CardBadges {
        let state = entry?.details?.userState
        let count = isFolder ? state?.unplayedCount ?? 0 : 0
        return CardBadges(
            isFavorite: state?.isFavorite == true,
            isPlayed: count <= 0 && state?.isPlayed == true,
            unplayedCount: count,
        )
    }

    @ViewBuilder
    private var trailing: some View {
        let badges = shownBadges
        HStack(spacing: 12) {
            if let count = badges.unplayedCount, count > 0 {
                Text(count, format: .number)
            }
            if let runtime = shownRuntime {
                Text(runtime.lengthText)
            }
            if badges.isPlayed {
                Image(systemName: "checkmark.circle.fill")
            }
        }
    }
}

/// Focus on a list row, like Wholphin's focused list items: the theme's light platter with dark
/// text, over a faint fill that marks out each row at rest.
struct ListRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RowBody(configuration: configuration)
    }

    private struct RowBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isFocused) private var isFocused
        @Environment(\.theme) private var theme

        var body: some View {
            configuration.label
                // The row's quieter text is `.secondary` of this, so it follows focus too.
                .foregroundStyle(isFocused ? theme.onFocusedPlatter : theme.onBackground)
                .background(
                    isFocused ? theme.focusedPlatter : theme.surfaceVariant.withAlpha(0.3),
                    in: .rect(cornerRadius: 12),
                )
                .scaleEffect(configuration.isPressed ? 0.98 : isFocused ? 1.02 : 1)
                .animation(.easeOut(duration: 0.15), value: isFocused)
        }
    }
}
