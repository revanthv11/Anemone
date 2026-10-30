import AnemoneCore
@testable import AnemonePlayback
import Foundation
import Testing

/// Wholphin's Video Scale choices: where each puts the video on the screen, and the overlay's
/// menu for them.
@MainActor
struct VideoScaleTests {
    private let screen = CGSize(width: 1920, height: 1080)
    /// A 2.4:1 film, in 4K.
    private let wide = CGSize(width: 3840, height: 1600)
    /// A 4:3 show.
    private let tall = CGSize(width: 1440, height: 1080)

    private func frame(_ scale: VideoScale, _ video: CGSize, pixelsPerPoint: CGFloat = 1) -> CGRect {
        scale.frame(video: video, in: screen, pixelsPerPoint: pixelsPerPoint)
    }

    @Test func `fit letterboxes and crop fills the screen, each keeping the proportions`() {
        #expect(VideoScale.fit.frame(video: wide, in: screen) == CGRect(x: 0, y: 140, width: 1920, height: 800))
        #expect(VideoScale.fit.frame(video: tall, in: screen) == CGRect(x: 240, y: 0, width: 1440, height: 1080))
        #expect(VideoScale.crop.frame(video: wide, in: screen) == CGRect(x: -336, y: 0, width: 2592, height: 1080))
        #expect(VideoScale.crop.frame(video: tall, in: screen) == CGRect(x: 0, y: -180, width: 1920, height: 1440))
    }

    @Test func `fill takes the screen, and none shows the pixels as they are`() {
        #expect(VideoScale.fill.frame(video: wide, in: screen) == CGRect(origin: .zero, size: screen))
        #expect(VideoScale.fill.stretches)
        #expect(frame(.unscaled, wide) == CGRect(x: -960, y: -260, width: 3840, height: 1600))
        #expect(!VideoScale.unscaled.stretches)
        // Pixel for pixel on a 4K screen, which has two pixels a point.
        #expect(frame(.unscaled, wide, pixelsPerPoint: 2) == CGRect(x: 0, y: 140, width: 1920, height: 800))
    }

    @Test func `fill width and fill height fit one side and let the other run over or short`() {
        #expect(VideoScale.fillWidth.frame(video: wide, in: screen) == CGRect(x: 0, y: 140, width: 1920, height: 800))
        #expect(VideoScale.fillWidth.frame(video: tall, in: screen) == CGRect(x: 0, y: -180, width: 1920, height: 1440))
        #expect(frame(.fillHeight, wide) == CGRect(x: -336, y: 0, width: 2592, height: 1080))
        #expect(VideoScale.fillHeight.frame(video: tall, in: screen) == CGRect(x: 240, y: 0, width: 1440, height: 1080))
    }

    @Test func `without the video's size, every choice takes the screen`() {
        for scale in VideoScale.allCases {
            #expect(scale.frame(video: .zero, in: screen) == CGRect(origin: .zero, size: screen))
        }
        #expect(VideoScale.crop.frame(video: wide, in: .zero) == .zero)
    }

    @Test func `the setting has Wholphin's name and default, as does the clock's`() {
        #expect(Preferences.videoScale.key == "globalContentScale")
        #expect(Preferences.videoScale.defaultValue == .fit)
        #expect(Preferences.showClock.key == "showClock")
        #expect(Preferences.showClock.defaultValue == true)
        #expect(VideoScale.allCases.map(\.title) == ["Fit", "None", "Crop", "Fill", "Fill width", "Fill height"])
    }

    @Test func `the overlay's menu comes after the features' menus, and a pick lasts for the player`() async throws {
        // `FakeEngine` draws into a layer of its own, as MPV does, which the speed menu shows for.
        let playback = PlaybackController(
            request: PlaybackRequest(.item("m1")),
            engine: FakeEngine(),
            features: [PlaybackSpeedMenu()],
            loadStream: FakeStreams().load,
        )
        await playback.start()
        #expect(await eventually { !playback.accessories.menus.isEmpty })
        let overlay = PlayerOverlay(controller: playback, videoScale: .crop)

        #expect(overlay.menus.map(\.id) == ["speed", PlayerOverlay.videoScaleMenuID])
        let menu = overlay.videoScaleMenu
        #expect(menu.title == "Video scale")
        #expect(menu.options.map(\.title) == ["Fit", "Crop", "Fill width", "Fill height"])
        #expect(menu.options.filter(\.isSelected).map(\.id) == ["crop"])

        try #require(menu.options.first { $0.id == "fillWidth" }).select()

        #expect(overlay.videoScale == .fillWidth)
        #expect(overlay.videoScaleMenu.options.filter(\.isSelected).map(\.id) == ["fillWidth"])
        // The setting it started from is left alone.
        #expect(Preferences.videoScale.value() == .fit)
        await playback.stop()
    }

    @Test func `AVPlayer gets every choice, and an engine's own layer those that need only the proportions`() {
        func controller(_ engine: any PlayerEngine) -> PlaybackController {
            PlaybackController(
                request: PlaybackRequest(.item("m1")),
                engine: engine,
                features: [],
                loadStream: FakeStreams().load,
            )
        }
        let avPlayer = PlayerOverlay(controller: controller(AVPlayerEngine()), videoScale: .fill)
        #expect(avPlayer.videoScale == .fill)
        let titles = ["Fit", "None", "Crop", "Fill", "Fill width", "Fill height"]
        #expect(avPlayer.videoScaleMenu.options.map(\.title) == titles)
        #expect(avPlayer.videoScaleMenu.options.filter(\.isSelected).map(\.id) == ["fill"])

        // `FakeEngine` draws into a layer of its own, as MPV does.
        let playback = controller(FakeEngine())
        #expect(VideoScale.choices(for: playback.engine.videoOutput) == [.fit, .crop, .fillWidth, .fillHeight])

        // A saved Fill can't be drawn there, so the player starts from Fit.
        let overlay = PlayerOverlay(controller: playback, videoScale: .fill)
        #expect(overlay.videoScale == .fit)
        #expect(overlay.videoScaleMenu.options.map(\.id) == ["fit", "crop", "fillWidth", "fillHeight"])
        #expect(overlay.videoScaleMenu.options.filter(\.isSelected).map(\.id) == ["fit"])
        #expect(PlayerOverlay(controller: playback, videoScale: .crop).videoScale == .crop)
    }
}
