import AnemoneCore
import AnemoneJellyfin
import Foundation
import os

/// Theme music on item pages, ported from Wholphin's `ThemeSongPlayer`: while a movie, series,
/// season, episode or collection page shows, one of its theme songs plays once, at the volume
/// Settings asks for.
///
/// Pages share one player, so going from a series to one of its seasons, which has the series'
/// theme, carries on with the song where Wholphin starts it again. A video playing holds theme
/// music back until its player closes, and the page's theme then plays again, as Wholphin's
/// page does when it resumes. It never takes Now Playing or the remote's play and pause.
@MainActor
public final class ThemeMusic {
    /// The player item pages share.
    public static let shared = ThemeMusic()

    /// Finds a theme song for an item: where to stream it from, or `nil` when it has none.
    public typealias Finder = @Sendable (MediaItem.ID) async throws -> URL?

    /// What the page showing asks for.
    private struct Request {
        let page: UUID
        let itemID: MediaItem.ID
        let find: Finder
    }

    private let output: any ThemeMusicOutput
    private let volume: @MainActor () -> ThemeMusicVolume
    private var request: Request?
    /// The page that last showed, which may be under a player.
    private var lastPage: UUID?
    /// The item whose theme is loading or playing.
    private(set) var playing: MediaItem.ID?
    private var lookup: Task<Void, Never>?
    /// Set while a video plays.
    private(set) var isHeldForVideo = false

    init(output: any ThemeMusicOutput, volume: @escaping @MainActor () -> ThemeMusicVolume) {
        self.output = output
        self.volume = volume
    }

    public convenience init() {
        self.init(output: SystemThemeMusicOutput()) {
            Preferences.playThemeSongs.value()
        }
    }

    /// A page shows `itemID`'s theme. The theme playing carries on when it's the same item's.
    ///
    /// - Parameter page: identifies the page, so only it can stop its theme with `hide(_:)`.
    public func show(_ itemID: MediaItem.ID, for page: UUID, find: @escaping Finder) {
        // Another page can't be under a player, so a video can't be holding it back. The same
        // page can show again under one, as when the app comes back to the foreground.
        if lastPage != page {
            isHeldForVideo = false
        }
        lastPage = page
        request = Request(page: page, itemID: itemID, find: find)
        playRequested()
    }

    /// The page stopped showing: back, another page on top, or the app in the background. Does
    /// nothing if another page has shown since.
    public func hide(_ page: UUID) {
        guard request?.page == page else { return }
        request = nil
        stop()
    }

    /// A video started playing: theme music stops until its player closes.
    public func videoStarted() {
        isHeldForVideo = true
        stop()
    }

    /// The video player closed: the page showing plays its theme again.
    public func videoClosed() {
        guard isHeldForVideo else { return }
        isHeldForVideo = false
        playRequested()
    }

    private func playRequested() {
        guard let request, !isHeldForVideo, request.itemID != playing else { return }
        stop()
        guard let level = volume().level else { return }
        playing = request.itemID
        let itemID = request.itemID
        let find = request.find
        lookup = Task { [weak self] in
            guard let url = try? await find(itemID), !Task.isCancelled else { return }
            Self.log.info("Playing the theme song of \(itemID, privacy: .public) at \(level)")
            self?.output.play(url, volume: level)
        }
    }

    private func stop() {
        lookup?.cancel()
        lookup = nil
        if let itemID = playing {
            playing = nil
            output.stop()
            Self.log.info("Stopped the theme song of \(itemID, privacy: .public)")
        }
    }

    private static let log = Logger(subsystem: "com.revanthv11.anemone", category: "ThemeMusic")
}
