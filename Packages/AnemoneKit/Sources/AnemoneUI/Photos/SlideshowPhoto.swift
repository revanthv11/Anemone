import Nuke
import NukeUI
import SwiftUI

/// A photo filling the screen without cropping, as Wholphin's slideshow shows it. A new photo
/// stays hidden behind the one showing until it has loaded, then cross-fades in over 750 ms,
/// Wholphin's `CrossFadeFactory(750.milliseconds)`. `Slideshow` moves a running slideshow on
/// from a photo that fails or never loads.
public struct SlideshowPhoto: View {
    private let url: URL?
    private let loaded: @MainActor (Bool) -> Void

    /// The photo on screen; it lags `url` while the next one loads.
    @State private var shown: URL?
    @State private var failed: URL?

    /// - Parameter loaded: called once `url` has loaded (`true`) or couldn't be (`false`).
    public init(url: URL?, loaded: @escaping @MainActor (Bool) -> Void) {
        self.url = url
        self.loaded = loaded
    }

    public var body: some View {
        ZStack {
            ForEach(layers, id: \.self) { layer in
                LazyImage(url: layer) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .scaledToFit()
                    }
                }
                .onCompletion { result in
                    finished(layer, loaded: (try? result.get()) != nil)
                }
                .opacity(layer == shown ? 1 : 0)
            }
            if url != nil, url != shown, url != failed {
                ProgressView()
            } else if url != nil, url == failed {
                Text("Couldn't load this photo.")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.75), value: shown)
        .onChange(of: url) {
            // Back on a photo that failed just before: it isn't loaded again, so it fails now,
            // and a running slideshow moves on rather than waiting for it.
            if url != nil, url == failed {
                loaded(false)
            }
        }
    }

    /// The photo showing, and the one loading behind it.
    private var layers: [URL] {
        var layers = shown.map { [$0] } ?? []
        if let url, url != shown, url != failed {
            layers.append(url)
        }
        return layers
    }

    private func finished(_ layer: URL, loaded success: Bool) {
        guard layer == url else { return }
        if success {
            shown = layer
        } else {
            failed = layer
            // The message shows on its own, not over the last photo.
            shown = nil
        }
        loaded(success)
    }

    /// Starts loading photos about to show, as Wholphin fetches the next one ahead.
    @MainActor
    public static func prefetch(_ urls: [URL]) {
        prefetcher.startPrefetching(with: urls)
    }

    @MainActor private static let prefetcher = ImagePrefetcher()
}
