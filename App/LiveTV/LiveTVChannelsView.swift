import AnemoneCore
import AnemoneJellyfin
import AnemoneUI
import SwiftUI

/// Every channel as a tile with what's on now, in the guide's order. Selecting one watches it;
/// a long press adds it to or removes it from favourites, as the guide's channel dialog does.
struct LiveTVChannelsView: View {
    /// Changes when the channels should load again.
    let version: Int
    let watch: (LiveTVChannel) -> Void
    let toggleFavorite: (LiveTVChannel) -> Void

    @Environment(BrowseModel.self) private var browse
    @Environment(\.theme) private var theme
    @State private var channels: [LiveTVChannel]?
    @State private var problem: String?

    private static let tileWidth: CGFloat = 370
    private static let columns = Array(repeating: GridItem(.fixed(tileWidth), spacing: 48, alignment: .top), count: 4)

    var body: some View {
        Group {
            if let channels, !channels.isEmpty {
                ScrollView(.vertical) {
                    LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 48) {
                        ForEach(channels) { channel in
                            tile(channel)
                        }
                    }
                    .padding(.vertical, 30)
                }
                .scrollClipDisabled()
            } else if let problem {
                PageMessage(message: problem)
            } else if channels != nil {
                PageMessage(message: String(localized: "Live TV is on, but \(browse.server.name) has no channels."))
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: version) {
            await load()
        }
    }

    private func tile(_ channel: LiveTVChannel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                watch(channel)
            } label: {
                LogoImage(url: browse.imageURL(channel.image, width: 400), maxWidth: 280, height: 120) {
                    Text(channel.name)
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .frame(width: Self.tileWidth, height: Self.tileWidth * 9 / 16)
                .background(theme.surfaceVariant)
                .overlay(alignment: .topTrailing) {
                    if channel.isFavorite {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(theme.favorite)
                            .padding(14)
                    }
                }
            }
            .buttonStyle(.card)
            .contextMenu {
                Button(
                    channel.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                    systemImage: channel.isFavorite ? "heart.slash" : "heart",
                ) {
                    toggleFavorite(channel)
                }
            }
            .accessibilityIdentifier("channels.card.\(channel.id)")
            // The channel, then what's on it now and whether it's a favourite: the caption under
            // the tile isn't focusable, so the tile says it.
            .accessibilityLabel(channel.title)
            .accessibilityValue(channelValue(channel))
            VStack(alignment: .leading, spacing: 2) {
                Text(channel.title)
                    .font(.caption)
                    .foregroundStyle(theme.onBackground)
                    .lineLimit(1)
                Text(channel.currentProgram?.name ?? " ")
                    .font(.caption2)
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
            }
            .frame(width: Self.tileWidth, alignment: .leading)
            .accessibilityHidden(true)
        }
    }

    private func channelValue(_ channel: LiveTVChannel) -> Text {
        switch (channel.currentProgram?.name, channel.isFavorite) {
        // "Favorite" is the word the guide and the cards read too, one key for all of them.
        case let (program?, true): Text("\(Text(verbatim: program)), \(Text("Favorite"))")
        case let (program?, false): Text(program)
        case (nil, true): Text("Favorite")
        case (nil, false): Text(verbatim: "")
        }
    }

    private func load() async {
        do {
            channels = try await browse.session.liveTVChannels(
                order: Preferences.liveTVChannelOrder,
                includesCurrentProgram: true,
            )
            problem = nil
        } catch {
            if channels == nil {
                problem = browse.problem(with: error, failure: "Couldn't load the channels from \(browse.server.name).")
            }
        }
    }
}
