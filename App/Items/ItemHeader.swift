import AnemoneJellyfin
import AnemoneUI
import SwiftUI

/// The item's logo, or its title when there's no logo, like Wholphin's `TitleOrLogo`.
struct ItemTitle: View {
    let title: String
    let logo: ItemImage?

    @Environment(BrowseModel.self) private var browse
    @Environment(\.displayScale) private var displayScale
    @Environment(\.theme) private var theme

    var body: some View {
        LogoImage(
            url: browse.imageURL(logo, width: ItemLayout.logoWidth * displayScale),
            maxWidth: ItemLayout.logoWidth,
            height: ItemLayout.logoHeight,
        ) {
            Text(title)
                .font(.title.bold())
                .foregroundStyle(theme.onBackground)
                .lineLimit(2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("detail.title")
    }
}

/// Wholphin's quick details: year or episode, runtime, time left, age rating and scores, then
/// when the item would end if started now. VoiceOver reads the parts in words, with a pause
/// between them.
struct QuickDetails: View {
    let details: ItemDetails

    var body: some View {
        TimelineView(.everyMinute) { context in
            let parts = details.quickDetails(now: context.date)
            if let first = parts.first {
                parts.dropFirst().reduce(first) { line, part in Text("\(line) · \(part)") }
                    .accessibilityLabel(details.quickDetails(now: context.date, spoken: true).spokenList ?? first)
                    .accessibilityIdentifier("detail.quickDetails")
            }
        }
        .font(.callout)
        .lineLimit(1)
    }
}

/// Up to four genres or studios, then how many more, as Wholphin's `GenreText` lists them.
struct NameList: View {
    let names: [String]

    var body: some View {
        let shown = names.prefix(4).joined(separator: ", ")
        let more = names.count - 4
        Text(more > 0 ? "\(shown), +\(more)" : shown)
            .font(.callout)
            .lineLimit(1)
            // VoiceOver would read "+2" as "plus 2".
            .accessibilityLabel(more > 0 ? Text("\(shown) and \(more) more") : Text(shown))
    }
}

/// The overview, cut to a few lines; selecting it shows all of it, like Wholphin's
/// `OverviewText` and its details dialog.
struct OverviewButton: View {
    let title: String
    let overview: String
    var lineLimit = 3

    @State private var showsAll = false
    @Environment(\.theme) private var theme

    var body: some View {
        Button {
            showsAll = true
        } label: {
            Text(overview)
                .font(.callout)
                .foregroundStyle(theme.onBackground)
                .lineLimit(lineLimit, reservesSpace: true)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: ItemLayout.textWidth, alignment: .leading)
        }
        .buttonStyle(HighlightButtonStyle())
        .accessibilityHint("Shows the whole overview")
        .accessibilityIdentifier("detail.overview")
        .sheet(isPresented: $showsAll) {
            VStack(alignment: .leading, spacing: 32) {
                Text(title)
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Text(overview)
                    .font(.body)
            }
            .frame(maxWidth: 1200, alignment: .leading)
            .padding(60)
            // Gives the sheet somewhere for focus to rest; Back closes it. VoiceOver reads the
            // title and the whole overview there.
            .focusable()
            .accessibilityElement(children: .combine)
        }
    }
}

/// Shows focus as a soft highlight behind the content, like Wholphin's focused overview and
/// list rows, instead of the platter tvOS draws behind buttons.
///
/// The highlight is the theme's quiet `platter`, under which light text stays readable.
/// Wholphin's overview uses its `onPrimary` at 40%, which some themes' pages all but hide (green's
/// is 1.1 to 1 on its background), and on a TV focus has to show.
struct HighlightButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HighlightBody(configuration: configuration)
    }

    private struct HighlightBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isFocused) private var isFocused
        @Environment(\.theme) private var theme

        var body: some View {
            configuration.label
                .padding(16)
                .background(theme.platter.withAlpha(isFocused ? theme.platter.alpha : 0), in: .rect(cornerRadius: 16))
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                // Keeps the content lined up with the text around it.
                .padding(-16)
                .animation(.easeOut(duration: 0.15), value: isFocused)
        }
    }
}
