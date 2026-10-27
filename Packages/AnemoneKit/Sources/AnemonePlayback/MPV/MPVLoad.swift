import AnemoneJellyfin
import Foundation

/// A stream the MPV engine is playing: its events, and how far libmpv has got with it.
struct MPVLoad {
    let events: AsyncStream<PlayerEvent>.Continuation
    /// Where it was loaded from, which tells subtitles meant for it from those for a stream that
    /// replaced it.
    let url: URL
    /// The playlist entry libmpv made for the file, which tells what libmpv says about it from
    /// what it says about the file this replaced. When libmpv didn't say, the first entry to
    /// start that's newer than `newerThan` is this one's.
    private(set) var entry: Int64?
    private let newerThan: Int64
    /// libmpv opened the file, so subtitles can be added to it.
    var isLoaded = false
    var isReady = false
    var hasEnded = false
    /// Subtitles from beside the file, waiting for it to open.
    var pendingSubtitles: [ExternalSubtitle] = []

    init(events: AsyncStream<PlayerEvent>.Continuation, url: URL, entry: Int64?, newerThan: Int64) {
        self.events = events
        self.url = url
        self.entry = entry
        self.newerThan = newerThan
    }

    /// Whether libmpv's event about `entry` is about this stream.
    func owns(_ entry: Int64) -> Bool {
        self.entry == entry
    }

    /// libmpv started `entry`: this stream's, if libmpv didn't say which its was and it's the
    /// first entry since the load. libmpv numbers entries in order and never reuses one.
    mutating func started(_ entry: Int64) {
        if self.entry == nil, entry > newerThan {
            self.entry = entry
        }
    }

    /// The file was a playlist, which libmpv replaced with its entries: this stream plays on
    /// from the first of them.
    mutating func redirect(to entry: Int64) {
        self.entry = entry
        isLoaded = false
    }
}

extension MPVPlayerEngine {
    /// Whether libmpv's end of the file at `position` is the real end. With `keep-open`, a read
    /// or network error partway reaches libmpv as the end of the file too, which should be
    /// retried as a transcode rather than count as watched. Durations are estimates in some
    /// containers, so the last 2% (at least 10 s) counts as the end; so does any position when
    /// the duration isn't known, as with a live stream.
    static func isRealEnd(at position: Duration, of duration: Duration?) -> Bool {
        guard let duration, duration > .zero else { return true }
        return position >= duration - max(.seconds(10), duration * 0.02)
    }

    /// Seconds as libmpv reads them.
    static func seconds(_ duration: Duration) -> String {
        String(format: "%.3f", duration / .seconds(1))
    }

    /// A value for loadfile's option list, which commas and quotes would break: libmpv's
    /// `%n%` prefix gives the value's length, so anything can follow.
    static func escaped(_ value: String) -> String {
        "%\(value.utf8.count)%\(value)"
    }
}
