import Foundation

/// Where the home page's Live TV rows come from: Wholphin's Active Recordings, Watch Live and
/// Channels rows. The Live TV feature (Phase 5a) provides the real one; until then Home uses
/// `NoLiveTV`, and DEBUG builds can show made-up rows.
public protocol HomeLiveTVSource: Sendable {
    /// Recordings in progress.
    func recordingsInProgress(limit: Int) async throws -> [MediaItem]
    /// Programmes airing now.
    func programsOnNow(limit: Int) async throws -> [MediaItem]
    func channels(limit: Int) async throws -> [MediaItem]
}

/// Live TV rows that stay empty, so Home hides them.
public struct NoLiveTV: HomeLiveTVSource {
    public init() {}

    public func recordingsInProgress(limit _: Int) async throws -> [MediaItem] {
        []
    }

    public func programsOnNow(limit _: Int) async throws -> [MediaItem] {
        []
    }

    public func channels(limit _: Int) async throws -> [MediaItem] {
        []
    }
}
