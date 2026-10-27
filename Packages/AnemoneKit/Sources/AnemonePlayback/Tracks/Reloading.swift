/// What `PlaybackController.reload()` keeps track of for the entry playing.
struct Reloading {
    /// Whether the last load allowed direct play, which a reload keeps.
    var allowsDirect = true
    /// Whether the entry's stream was replaced with `reload()`. Features then hear `reloaded` for
    /// its later streams too, a transcode retry's included, since it's still the same entry.
    var hasReloaded = false
    /// Whether the server is being asked for a stream.
    var isAsking = false
    /// Whether a reload came while the server was asked. Once the request has gone out, its
    /// answer is dropped and the server asked again, for what's chosen by then, so quick picks
    /// in the Audio and Subtitles menus come to one more request rather than one each.
    var asksAgain = false

    /// Whether a reload starts now. While the server is asked for a stream it doesn't: the
    /// request asks for what's chosen by the time it goes out, or is asked again afterwards.
    mutating func starts() -> Bool {
        guard !isAsking else {
            asksAgain = true
            return false
        }
        hasReloaded = true
        return true
    }
}
