import AnemoneJellyfin
import AnemoneUI
import SwiftUI

/// Stand-in for item pages until Phase 2c: the poster, title, year and overview.
struct ItemDetailView: View {
    let item: MediaItem

    @Environment(BrowseModel.self) private var browse
    @Environment(\.displayScale) private var displayScale
    /// The full item; home rows can hold a series built from one of its episodes.
    @State private var loaded: MediaItem?
    @State private var problem: String?

    var body: some View {
        let shown = loaded ?? item
        HStack(alignment: .top, spacing: 80) {
            ShapedArtwork(
                url: url(for: shown.posterImage, pixels: Int(Self.posterWidth * displayScale)),
                shape: .poster,
                width: Self.posterWidth,
                cornerRadius: 16,
            )

            VStack(alignment: .leading, spacing: 24) {
                Text(shown.displayTitle)
                    .font(.largeTitle.bold())
                    .accessibilityIdentifier("detail.title")
                if let subtitle = shown.subtitle {
                    Text(subtitle)
                        .font(.title3)
                }
                if !shown.details.isEmpty {
                    Text(shown.details)
                        .foregroundStyle(.secondary)
                }
                if let overview = shown.overview {
                    Text(overview)
                        .lineLimit(8)
                }
                if let problem {
                    NoticeText(problem)
                }
                Text("Full item pages and playback arrive in later phases.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Keeps focus on this page rather than the sidebar, which has nothing to do here.
            .focusable()
        }
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            BackdropImage(url: url(for: shown.backdropImage, pixels: 1920))
                .ignoresSafeArea()
        }
        .task {
            await load()
        }
    }

    private static let posterWidth: CGFloat = 400

    private func load() async {
        do {
            loaded = try await browse.session.item(id: item.id)
        } catch SessionError.signedOut {
            browse.noteSignedOut()
            problem = "\(browse.server.name) signed you out. Go back to sign in again."
        } catch {
            // Leaving the page cancels the request; that isn't worth reporting.
            guard !Task.isCancelled else { return }
            problem = "Couldn't load the full details from \(browse.server.name)."
        }
    }

    private func url(for image: ItemImage?, pixels: Int) -> URL? {
        image.flatMap { browse.session.imageURL(for: $0, maxWidth: pixels) }
    }
}
