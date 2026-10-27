import AnemoneJellyfin
import SwiftUI

/// A title in a library's list layout, ported from Wholphin's `CollectionFolderList` rows: a
/// heart for favourites, the title over its year or episode, then the running time and a check
/// for watched titles, or a series' unwatched count. The dense list puts the year beside the
/// title and drops the second line.
struct LibraryListRow: View {
    let entry: LibraryEntry?
    let isDense: Bool

    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: "heart.fill")
                .foregroundStyle(.red)
                .opacity(entry?.details?.userState.isFavorite == true ? 1 : 0)
                .accessibilityLabel("Favorite")
                .accessibilityHidden(entry?.details?.userState.isFavorite != true)
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
    }

    private var item: MediaItem? {
        entry?.item
    }

    /// Movies and albums put their year beside the title in the dense list, and series their years.
    private var title: String {
        guard let item else { return " " }
        guard isDense, let subtitle else { return item.displayTitle }
        return "\(item.displayTitle) (\(subtitle))"
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

    @ViewBuilder
    private var trailing: some View {
        let state = entry?.details?.userState
        HStack(spacing: 12) {
            if item?.kind == .series || item?.kind == .collection {
                if let count = state?.unplayedCount, count > 0 {
                    Text(count, format: .number)
                        .accessibilityLabel("\(count) unwatched")
                } else if state?.isPlayed == true {
                    watchedMark
                }
            } else {
                if let runtime = item?.runtime, runtime > .zero {
                    Text(runtime.roundedToMinutes.lengthText)
                }
                if state?.isPlayed == true {
                    watchedMark
                }
            }
        }
    }

    private var watchedMark: some View {
        Image(systemName: "checkmark.circle.fill")
            .accessibilityLabel("Watched")
    }
}

/// Focus on a list row: a soft highlight that fills the row, like Wholphin's focused list items,
/// over a faint background that marks out each row.
struct ListRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RowBody(configuration: configuration)
    }

    private struct RowBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .background(.white.opacity(isFocused ? 0.25 : 0.06), in: .rect(cornerRadius: 12))
                .scaleEffect(configuration.isPressed ? 0.98 : isFocused ? 1.02 : 1)
                .animation(.easeOut(duration: 0.15), value: isFocused)
        }
    }
}
