import NukeUI
import SwiftUI

/// An item's logo, falling back to its title as text when there's no logo or it fails to load,
/// like Wholphin's `TitleOrLogo`.
public struct LogoImage<Title: View>: View {
    private let url: URL?
    private let maxWidth: CGFloat
    private let height: CGFloat
    private let title: Title

    public init(url: URL?, maxWidth: CGFloat, height: CGFloat, @ViewBuilder title: () -> Title) {
        self.url = url
        self.maxWidth = maxWidth
        self.height = height
        self.title = title()
    }

    public var body: some View {
        if let url {
            LazyImage(url: url) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: maxWidth, maxHeight: height, alignment: .leading)
                } else if state.error != nil {
                    title
                } else {
                    // Holds the logo's space while it loads, so the page doesn't jump.
                    Color.clear
                        .frame(width: maxWidth, height: height)
                }
            }
            .frame(maxWidth: maxWidth, minHeight: height, alignment: .leading)
        } else {
            title
        }
    }
}
