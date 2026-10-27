/// Seerr integration for discovering and requesting movies and TV shows.
///
/// The API client in `Generated` comes from Seerr's OpenAPI description, by
/// `scripts/generate-seerr-client.sh`; `SeerrConnection` and `SeerrSignIn` are what the app uses.
/// Everything is compiled in only when the `ANEMONE_SEERR` condition is set, so App Store builds
/// can leave it out (see docs/seerr.md).
public enum Seerr {
    /// Whether this build has Seerr.
    public static var isAvailable: Bool {
        #if ANEMONE_SEERR
            true
        #else
            false
        #endif
    }
}
