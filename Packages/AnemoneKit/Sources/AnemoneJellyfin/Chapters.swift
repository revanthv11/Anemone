public extension [Chapter] {
    /// The chapter playing at `position` in a list in playing order: the last one starting at or
    /// before it, or the first when it's before them all. `nil` when there are no chapters.
    /// Wholphin's chapter row in the player starts with this one in focus.
    func chapter(at position: Duration) -> Chapter? {
        last { $0.start <= position } ?? first
    }
}
