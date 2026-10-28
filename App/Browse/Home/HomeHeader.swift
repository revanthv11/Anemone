import AnemoneJellyfin
import AnemoneUI
import SwiftUI

/// The focused card's item above Home's rows, like Wholphin's `HomePageHeader`: its title, the
/// episode, quick details and the start of the overview.
struct HomeHeader: View {
    let item: MediaItem?

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(item?.displayTitle ?? " ")
                .font(.title2.bold())
                .lineLimit(1)
                .accessibilityIdentifier("home.header.title")
            // An episode's series and number; a movie has none, and no blank line for it, as
            // the library pages' headers have none.
            if let subtitle = item?.subtitle {
                Text(subtitle)
                    .font(.title3)
                    .lineLimit(1)
            }
            Text(item?.details ?? " ")
                .font(.callout)
                .foregroundStyle(theme.secondaryText)
            Text(item?.overview ?? " ")
                .font(.callout)
                .lineLimit(3, reservesSpace: true)
                .frame(maxWidth: 1100, alignment: .leading)
        }
        .foregroundStyle(theme.onBackground)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: HomeLayout.headerHeight, alignment: .bottomLeading)
        .animation(nil, value: item)
    }
}

/// What Home shows instead of rows: nothing to show, a failure or a sign-out, with what to do.
struct HomeMessage<Actions: View>: View {
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 24) {
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(theme.onBackground)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 1000)
            actions
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension HomeMessage where Actions == EmptyView {
    init(title: String, message: String) {
        self.init(title: title, message: message) { EmptyView() }
    }
}
