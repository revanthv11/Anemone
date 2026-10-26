import AnemoneJellyfin
import AnemoneUI
import SwiftUI

/// The item's logo, or its title when there's no logo, like Wholphin's `TitleOrLogo`.
struct ItemTitle: View {
    let title: String
    let logo: ItemImage?

    @Environment(BrowseModel.self) private var browse
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        LogoImage(
            url: browse.imageURL(logo, width: ItemLayout.logoWidth * displayScale),
            maxWidth: ItemLayout.logoWidth,
            height: ItemLayout.logoHeight,
        ) {
            Text(title)
                .font(.title.bold())
                .lineLimit(2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("detail.title")
    }
}

/// Wholphin's quick details: year or episode, runtime, time left, age rating and scores, then
/// when the item would end if started now.
struct QuickDetails: View {
    let details: ItemDetails

    var body: some View {
        TimelineView(.everyMinute) { context in
            let parts = details.quickDetails(now: context.date)
            if let first = parts.first {
                parts.dropFirst().reduce(first) { line, part in Text("\(line) · \(part)") }
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
        Text(names.count > 4 ? "\(shown), +\(names.count - 4)" : shown)
            .font(.callout)
            .lineLimit(1)
    }
}

/// The overview, cut to a few lines; selecting it shows all of it, like Wholphin's
/// `OverviewText` and its details dialog.
struct OverviewButton: View {
    let title: String
    let overview: String
    var lineLimit = 3

    @State private var showsAll = false

    var body: some View {
        Button {
            showsAll = true
        } label: {
            Text(overview)
                .font(.callout)
                .lineLimit(lineLimit, reservesSpace: true)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: ItemLayout.textWidth, alignment: .leading)
        }
        .buttonStyle(HighlightButtonStyle())
        .accessibilityHint("Shows the whole overview")
        .sheet(isPresented: $showsAll) {
            VStack(alignment: .leading, spacing: 32) {
                Text(title)
                    .font(.title2.bold())
                Text(overview)
                    .font(.body)
            }
            .frame(maxWidth: 1200, alignment: .leading)
            .padding(60)
            // Gives the sheet somewhere for focus to rest; Back closes it.
            .focusable()
        }
    }
}

/// Shows focus as a soft highlight behind the content, like Wholphin's focused overview and
/// list rows, instead of the platter tvOS draws behind buttons.
struct HighlightButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HighlightBody(configuration: configuration)
    }

    private struct HighlightBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .padding(16)
                .background(.white.opacity(isFocused ? 0.15 : 0), in: .rect(cornerRadius: 16))
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                // Keeps the content lined up with the text around it.
                .padding(-16)
                .animation(.easeOut(duration: 0.15), value: isFocused)
        }
    }
}
