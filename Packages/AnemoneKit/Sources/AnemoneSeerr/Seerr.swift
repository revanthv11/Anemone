/// Seerr integration for discovering and requesting movies and TV shows.
///
/// The API client in `Generated` comes from Seerr's OpenAPI description, by
/// `scripts/generate-seerr-client.sh`; `SeerrConnection` and `SeerrSignIn` are what the app uses.
/// Everything is compiled in only with the package's `ANEMONE_SEERR` trait, which also brings in
/// the client's packages, so App Store builds can leave it all out (see docs/seerr.md).
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

// The condition alone, as `-Xswiftc -DANEMONE_SEERR` or a build setting without the trait gives
// it, would compile the client without the packages it needs.
#if ANEMONE_SEERR && !canImport(OpenAPIRuntime)
    #error("ANEMONE_SEERR needs the package's ANEMONE_SEERR trait too; see docs/seerr.md.")
#endif
