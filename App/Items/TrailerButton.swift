import AnemoneJellyfin
import AnemonePlayback
import SwiftUI

/// Plays the item's trailer, or lists its trailers when there are several, like Wholphin's
/// `TrailerButton` and `TrailerDialog`. Hidden when there are none.
///
/// Local trailers play in the player. Remote ones are web pages, which Wholphin opens in the
/// browser; Apple TV has none, so YouTube trailers hand off to the YouTube app and the button says
/// so when it isn't installed.
struct TrailerButton: View {
    let trailers: [Trailer]

    @Environment(BrowseModel.self) private var browse
    @Environment(\.openURL) private var openURL
    @State private var playback: PlaybackRequest?
    @State private var choosing = false
    /// Why a remote trailer didn't open.
    @State private var problem = ""
    @State private var showsProblem = false

    var body: some View {
        if !trailers.isEmpty {
            ActionButton(
                title: trailers.count == 1 ? String(localized: "Play trailer") : String(localized: "Trailers"),
                systemImage: "film",
            ) {
                if let trailer = trailers.first, trailers.count == 1 {
                    play(trailer)
                } else {
                    choosing = true
                }
            }
            .accessibilityIdentifier("action.trailer")
            .confirmationDialog("Trailers", isPresented: $choosing, titleVisibility: .visible) {
                ForEach(Array(trailers.enumerated()), id: \.element.id) { index, trailer in
                    Button("\(title(at: index)) · \(trailer.sourceName)") {
                        play(trailer)
                    }
                    .accessibilityLabel(Text("\(title(at: index)), \(trailer.sourceName)"))
                    .accessibilityIdentifier("trailer.\(index)")
                }
            }
            .alert("Can't play this trailer", isPresented: $showsProblem) {
                Button("OK") {}
            } message: {
                Text(problem)
            }
            // A trailer leaves nothing on the page to update afterwards.
            .player($playback) {}
        }
    }

    private func play(_ trailer: Trailer) {
        switch trailer.source {
        case let .local(details):
            playback = browse.playback(of: details, from: nil)
        case .remote:
            guard let url = trailer.youTubeAppURL else {
                show(String(localized: "This trailer is on a website, and Apple TV can only open YouTube trailers."))
                return
            }
            openURL(url) { accepted in
                if !accepted {
                    show(String(localized: "This trailer is on YouTube. Install the YouTube app to watch it."))
                }
            }
        }
    }

    /// The trailer's name, numbered when others share it, as remote trailers often do ("Trailer 2").
    private func title(at index: Int) -> String {
        let name = trailers[index].name
        let namesakes = trailers.indices.filter { trailers[$0].name == name }
        guard namesakes.count > 1, let number = namesakes.firstIndex(of: index) else { return name }
        return String(localized: "\(name) \(number + 1)")
    }

    private func show(_ problem: String) {
        self.problem = problem
        showsProblem = true
    }
}
