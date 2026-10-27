import AnemoneCore
import AnemoneJellyfin

public extension Preferences {
    /// Wholphin's "Cinema mode" (`cinemaMode`): the server's intros play before what's picked.
    /// On by default, as in Wholphin.
    static let cinemaMode = Preference("cinemaMode", default: true)
}

/// Cinema-mode intros, ported from Wholphin's `PlaybackViewModel`: when something starts from
/// the beginning, whatever intros the server has for it play first, such as the pre-rolls of
/// the Local Intros plugin. Not when resuming, as in Wholphin.
public enum CinemaIntros {
    /// What finds a request's intros on `session`, or `nil` when cinema mode is off.
    public static func finder(
        on session: JellyfinSession,
        isOn: Bool = Preferences.cinemaMode.value(),
    ) -> PlaybackRequest.Intros? {
        guard isOn else { return nil }
        return { first in
            guard first.startPosition.map({ $0 <= .zero }) ?? true else { return [] }
            return try await entries(for: session.intros(for: first.itemID))
        }
    }

    /// Queue entries for intros, which play straight into what follows them.
    public static func entries(for intros: [MediaItem]) -> [PlaybackQueue.Entry] {
        intros.map { intro in
            PlaybackQueue.Entry(
                itemID: intro.id,
                metadata: PlaybackMetadata(title: intro.name, overview: intro.overview),
                isIntro: true,
            )
        }
    }
}
