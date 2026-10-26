import SwiftUI

/// Full-screen art behind a page, faded out towards the left and bottom so text stays readable,
/// like Wholphin's backdrop. Cross-fades when the URL changes.
public struct BackdropImage: View {
    private let url: URL?

    public init(url: URL?) {
        self.url = url
    }

    public var body: some View {
        ZStack {
            if let url {
                ArtworkImage(url: url)
                    .id(url)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .opacity(0.6)
        .mask {
            LinearGradient(
                stops: [.init(color: .clear, location: 0.1), .init(color: .black, location: 0.6)],
                startPoint: .leading,
                endPoint: .trailing,
            )
        }
        .mask {
            LinearGradient(
                stops: [.init(color: .black, location: 0.4), .init(color: .clear, location: 0.95)],
                startPoint: .top,
                endPoint: .bottom,
            )
        }
        .animation(.easeInOut(duration: 0.5), value: url)
        .accessibilityHidden(true)
    }
}
