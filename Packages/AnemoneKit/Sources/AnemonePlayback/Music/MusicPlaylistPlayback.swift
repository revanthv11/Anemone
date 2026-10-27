import AnemoneJellyfin

/// Playing a playlist whose entries aren't known yet.
public extension MusicPlayer {
    /// Play or Shuffle on a playlist page whose entries haven't loaded. The playlist plays from
    /// the paged `.playlist` source, as `play(_:shuffled:)` plays it, if its first page holds
    /// only songs: that's how this tells a playlist of songs without fetching all of it, as
    /// Wholphin's playlist page looks at no more than its first 50 entries. An entry's type
    /// decides, not whether it could be read. What was playing stops at once.
    ///
    /// Returns once the queue has started. The rest pages in behind it, up to `queueLimit`
    /// entries, and a later page that fails ends the queue there, as with `play(_:shuffled:)`.
    /// Shuffled, the whole queue is fetched before it starts.
    ///
    /// - Returns: `false` when the first page holds anything but songs, or nothing: the playlist
    ///   is the video player's, and the player has stopped. `true` once the songs are queued, or
    ///   when another queue took over meanwhile.
    /// - Throws: when the first page couldn't be fetched, after stopping the player.
    func play(playlist id: MediaItem.ID, shuffled: Bool = false) async throws -> Bool {
        let source = MusicSource.playlist(id)
        let request = clearForNewQueue()
        let first: MusicPage
        do {
            first = try await loadSongs(source, shuffled, 0, Self.pageSize)
        } catch {
            if request == requests {
                stop()
            }
            throw error
        }
        guard request == requests else { return true }
        guard first.serverCount > 0, first.isAllSongs else {
            stop()
            return false
        }
        guard shuffled else {
            start(MusicQueue(first.items), paused: status == .paused)
            if request == requests {
                Task { await addPages(of: source, after: first, request: request) }
            }
            return true
        }
        let songs = await songs(of: source, after: first, request: request)
        guard request == requests else { return true }
        start(MusicQueue(songs, shuffled: true), paused: status == .paused)
        return true
    }
}

private extension MusicPlayer {
    /// The songs of `first` and of the pages after it, up to `queueLimit` entries, for a
    /// shuffled queue. A page that fails ends them there, as it ends a queue that's playing.
    func songs(of source: MusicSource, after first: MusicPage, request: Int) async -> [MusicItem] {
        var songs = first.items
        var fetched = first.serverCount
        let total = min(first.totalCount ?? fetched, Self.queueLimit)
        while fetched < total {
            let page: MusicPage
            do {
                page = try await loadSongs(source, true, fetched, min(Self.pageSize * 5, total - fetched))
            } catch {
                let reason = String(describing: error)
                Self.log.error("A shuffled queue stopped at \(fetched) of \(total), as a page failed: \(reason)")
                break
            }
            guard request == requests, page.serverCount > 0 else { break }
            songs += page.items
            fetched += page.serverCount
        }
        return songs
    }
}
