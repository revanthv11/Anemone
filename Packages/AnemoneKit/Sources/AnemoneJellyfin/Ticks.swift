/// Jellyfin counts time in 100-nanosecond ticks.
extension Duration {
    init(ticks: Int) {
        self = .microseconds(ticks / 10)
    }

    var ticks: Int {
        Int(components.seconds) * 10_000_000 + Int(components.attoseconds / 100_000_000_000)
    }
}
