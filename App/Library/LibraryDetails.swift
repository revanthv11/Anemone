import AnemoneJellyfin
import AnemoneUI
import Observation
import SwiftUI

/// The title focus is on in a library grid or a Recommended row, for the details header and the
/// backdrop. Kept out of the page's own state, so a focus move redraws only the views showing it.
@Observable
final class FocusedTitle {
    var details: ItemDetails?
}

/// The focused title's details over a grid or rows, like Wholphin's `HomePageHeader`, which its
/// library grid shows with "Show details": the logo or title, the episode, quick details and the
/// start of the overview.
struct LibraryDetailsHeader: View {
    let focus: FocusedTitle

    @Environment(BrowseModel.self) private var browse
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let details = focus.details
        VStack(alignment: .leading, spacing: 10) {
            LogoImage(
                url: browse.imageURL(details?.logo, width: LibraryDetailsLayout.logoWidth * displayScale),
                maxWidth: LibraryDetailsLayout.logoWidth,
                height: LibraryDetailsLayout.logoHeight,
            ) {
                Text(details?.item.displayTitle ?? " ")
                    .font(.title2.bold())
                    .lineLimit(1)
            }
            .frame(height: LibraryDetailsLayout.logoHeight, alignment: .bottomLeading)
            // Wholphin names the episode under its series, and its quick details give the number.
            if let episode = details?.item, episode.kind == .episode || episode.kind == .season {
                Text(episode.name)
                    .font(.headline)
                    .lineLimit(1)
            }
            if let details {
                QuickDetails(details: details)
                    .foregroundStyle(.secondary)
            }
            // Two lines under an episode's name, as in Wholphin, so the header keeps its height.
            Text(details?.item.overview ?? " ")
                .font(.callout)
                .lineLimit(details?.item.kind == .episode ? 2 : 3, reservesSpace: true)
                .frame(maxWidth: LibraryDetailsLayout.overviewWidth, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .bottomLeading)
        .frame(height: LibraryDetailsLayout.headerHeight, alignment: .bottomLeading)
        .animation(nil, value: details)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("library.details")
    }
}

/// The focused title beside a list, like Wholphin's `CollectionFolderListDetails`: its logo or
/// title, poster, quick details and overview.
struct LibraryDetailsPanel: View {
    let focus: FocusedTitle

    @Environment(BrowseModel.self) private var browse
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let details = focus.details
        let width = LibraryDetailsLayout.panelWidth
        VStack(alignment: .leading, spacing: 20) {
            LogoImage(
                url: browse.imageURL(details?.logo, width: width * displayScale),
                maxWidth: width,
                height: LibraryDetailsLayout.logoHeight,
            ) {
                Text(details?.item.displayTitle ?? " ")
                    .font(.title3.bold())
                    .lineLimit(2)
            }
            .frame(height: LibraryDetailsLayout.logoHeight, alignment: .bottomLeading)
            ShapedArtwork(
                url: browse.imageURL(details?.item.posterImage, width: LibraryDetailsLayout.posterWidth * displayScale),
                shape: .poster,
                width: LibraryDetailsLayout.posterWidth,
            )
            if let details {
                QuickDetails(details: details)
                    .foregroundStyle(.secondary)
            }
            Text(details?.item.overview ?? " ")
                .font(.callout)
                .lineLimit(5)
            Spacer(minLength: 0)
        }
        .frame(width: width, alignment: .leading)
        .padding(.leading, GridLayout.horizontalInset)
        .padding(.vertical, GridLayout.focusPadding)
        .animation(nil, value: details)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("library.details")
    }
}

/// The focused title's backdrop behind the page, following focus after 150 ms as the home
/// page's does, so moving along doesn't load every image.
struct LibraryBackdrop: View {
    let focus: FocusedTitle

    @Environment(BrowseModel.self) private var browse
    @State private var shown: MediaItem?

    var body: some View {
        BackdropImage(url: browse.imageURL(shown?.backdropImage, width: LibraryDetailsLayout.backdropPixelWidth))
            .ignoresSafeArea()
            .task(id: focus.details?.id) {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                shown = focus.details?.item
            }
    }
}

extension FocusedTitle {
    /// Notes the entry at `index` as focused; titles without details get the card's own.
    func note(_ entry: LibraryEntry?) {
        guard let entry else { return }
        details = entry.details ?? ItemDetails(item: entry.item)
    }
}

enum LibraryDetailsLayout {
    static let headerHeight: CGFloat = 250
    static let logoWidth: CGFloat = 520
    static let logoHeight: CGFloat = 80
    static let overviewWidth: CGFloat = 1100
    static let panelWidth: CGFloat = 440
    static let posterWidth: CGFloat = 260
    /// Backdrops are faded and dimmed, so 1080p is plenty even on a 4K screen.
    static let backdropPixelWidth: CGFloat = 1920
}
