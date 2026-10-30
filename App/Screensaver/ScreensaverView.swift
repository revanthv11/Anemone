import AnemoneCore
import AnemoneJellyfin
import AnemoneUI
import SwiftUI

/// Wholphin's `AppScreensaver`: the backdrops of random movies and shows, one at a time, each
/// with its logo or title, slowly zooming, under a vignette and the clock. When the server has
/// nothing to show or can't be reached, a message moves around the screen instead, so nothing
/// stays in one place.
struct ScreensaverView: View {
    let session: JellyfinSession

    @AppStorage(Preferences.screensaverDuration) private var duration
    @AppStorage(Preferences.screensaverShowClock) private var showsClock
    @AppStorage(Preferences.screensaverAnimate) private var animates
    @AppStorage(Preferences.screensaverMaxAge) private var maxAge
    @State private var slide: ScreensaverSlide?
    @State private var message: String?
    @State private var messagePlace = Alignment.bottomLeading
    /// Read here, since this view's own environment is outside the `appTheme()` its body sets.
    @AppStorage(Preferences.appThemeColors) private var themeColors

    var body: some View {
        ZStack {
            // Behind the pictures, like the black around a photo, so it's not the theme's.
            Color.black
            if let slide {
                SlideView(
                    slide: slide,
                    backdropURL: imageURL(slide.backdrop, width: 1920),
                    logoURL: imageURL(slide.logo, width: 960),
                    zoomDuration: animates ? Double(duration) : nil,
                )
                .id(slide.id)
                .transition(.opacity)
            } else if let message {
                Text(message)
                    .font(.title2)
                    .foregroundStyle(theme.secondaryText)
                    .padding(.horizontal, ScreensaverLayout.horizontalInset)
                    .padding(.vertical, ScreensaverLayout.verticalInset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: messagePlace)
                    .transition(.opacity)
                    .accessibilityIdentifier("screensaver.message")
            }
            vignette
            if showsClock {
                clock
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 2), value: slide)
        .animation(.easeInOut(duration: 0.5), value: messagePlace)
        .task {
            await showSlides()
        }
        // ScreensaverPresenter hosts it on its own, outside the app's environment.
        .appTheme()
    }

    /// Darker towards the edges, and at the top behind the clock, as in Wholphin.
    private var vignette: some View {
        GeometryReader { geometry in
            let radius = max(geometry.size.width, geometry.size.height) / 1.5
            ZStack {
                RadialGradient(
                    stops: [.init(color: .clear, location: 0), .init(color: scrim(0.25), location: 0.85)],
                    center: .center,
                    startRadius: 0,
                    endRadius: radius,
                )
                if showsClock {
                    LinearGradient(
                        stops: [.init(color: scrim(0.6), location: 0), .init(color: .clear, location: 0.25)],
                        startPoint: .top,
                        endPoint: .bottom,
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var theme: Theme {
        Theme(themeColors)
    }

    private func scrim(_ alpha: Double) -> Color {
        theme.scrim.withAlpha(alpha).color
    }

    private var clock: some View {
        ClockText()
            .font(.title3)
            .foregroundStyle(theme.onBackground)
            .accessibilityIdentifier("screensaver.clock")
            .padding(.top, ScreensaverLayout.verticalInset)
        .padding(.trailing, ScreensaverLayout.horizontalInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }

    /// Wholphin's item flow: a random set of items, each shown for the chosen duration once its
    /// backdrop has loaded, then a new random set.
    private func showSlides() async {
        while !Task.isCancelled {
            let slides: [ScreensaverSlide]
            do {
                slides = try await session.screensaverSlides(maxAgeRating: maxAge >= 0 ? maxAge : nil)
            } catch {
                await showMessage(String(localized: "Couldn't reach the server."))
                continue
            }
            guard !slides.isEmpty else {
                await showMessage(String(localized: "Nothing to show."))
                continue
            }
            for next in slides {
                if let url = imageURL(next.backdrop, width: 1920) {
                    await ArtworkImage.preload(url)
                }
                guard !Task.isCancelled else { return }
                message = nil
                slide = next
                try? await Task.sleep(for: .seconds(duration))
            }
        }
    }

    /// Shows a message in a new place for one picture's time, as Wholphin's placeholder moves.
    private func showMessage(_ text: String) async {
        slide = nil
        message = text
        messagePlace = ScreensaverLayout.messagePlaces.filter { $0 != messagePlace }.randomElement() ?? .center
        try? await Task.sleep(for: .seconds(duration))
    }

    private func imageURL(_ image: ItemImage?, width: Int) -> URL? {
        image.flatMap { session.imageURL(for: $0, maxWidth: width) }
    }
}

/// One picture: the backdrop, zooming in and out over `zoomDuration` when set, and the logo or
/// title at the bottom left.
private struct SlideView: View {
    let slide: ScreensaverSlide
    let backdropURL: URL?
    let logoURL: URL?
    let zoomDuration: Double?

    @State private var scale = 1.0
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ArtworkImage(url: backdropURL)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(scale)
                .clipped()
            LogoImage(url: logoURL, maxWidth: 480, height: 240) {
                Text(slide.title)
                    .font(.title.bold())
                    .foregroundStyle(theme.onBackground)
                    .lineLimit(2)
                    .frame(maxWidth: 960, alignment: .bottomLeading)
                    .shadow(radius: 8)
            }
            .padding(.horizontal, ScreensaverLayout.horizontalInset)
            .padding(.bottom, ScreensaverLayout.verticalInset)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: slide.title))
        .accessibilityIdentifier("screensaver.slide")
        .onAppear {
            guard let zoomDuration else { return }
            withAnimation(.linear(duration: zoomDuration).delay(0.5).repeatForever(autoreverses: true)) {
                scale = 1.1
            }
        }
    }
}

private enum ScreensaverLayout {
    /// The TV's title-safe insets.
    static let horizontalInset: CGFloat = 80
    static let verticalInset: CGFloat = 60
    static let messagePlaces: [Alignment] = [
        .topLeading, .top, .topTrailing, .leading, .center, .trailing, .bottomLeading, .bottom, .bottomTrailing,
    ]
}
