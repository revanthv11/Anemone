import AnemoneJellyfin
import AnemoneUI
import SwiftUI

/// The series taken out of Next Up, each of which can go back, like Wholphin's
/// `RemovedNextUpContent`.
struct HomeRemovedNextUpPage: View {
    @Environment(BrowseModel.self) private var browse
    @Environment(\.theme) private var theme
    @State private var content = Content.loading

    private enum Content {
        case loading
        case loaded([(series: MediaItem, removed: Date)])
        case failed(String)
    }

    var body: some View {
        Group {
            switch content {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .loaded(entries) where entries.isEmpty:
                message(String(localized: "No series have been removed from Next Up."))
            case let .loaded(entries):
                List(entries, id: \.series.id) { entry in
                    Button {
                        allow(entry.series)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.series.name)
                            Text("Removed \(entry.removed.formatted(date: .abbreviated, time: .shortened))")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityHint("Shows the series in Next Up again")
                }
            case let .failed(problem):
                message(problem)
            }
        }
        .navigationTitle("Removed from Next Up")
        .task {
            await load()
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(theme.secondaryText)
            .focusable()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load() async {
        do {
            let removed = try await browse.session.removedFromNextUp()
            let series = try await browse.session.mediaItems(ids: Array(removed.dates.keys))
            content = .loaded(series.compactMap { item in removed.dates[item.id].map { (item, $0) } })
        } catch {
            content = .failed(browse.problem(with: error, failure: "Couldn't load the series removed from Next Up.")
                ?? String(localized: "Couldn't load the series removed from Next Up."))
        }
    }

    private func allow(_ series: MediaItem) {
        Task {
            do {
                try await browse.homeWriter.allowInNextUp(seriesID: series.id)
                await load()
            } catch {
                content = .failed(browse.problem(with: error, failure: "Couldn't update Next Up.")
                    ?? String(localized: "Couldn't update Next Up."))
            }
        }
    }
}
