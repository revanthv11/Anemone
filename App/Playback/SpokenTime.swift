import Foundation

extension Duration {
    /// A position or length as VoiceOver should say it, "1 minute, 5 seconds", where the clock's
    /// "1:05" reads like a time of day. The player, Now Playing and the chapter cards use it for
    /// their accessibility values.
    var spokenTime: String {
        formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }
}
