/// Seerr integration for discovering and requesting movies and TV shows.
///
/// The API client will be generated from Seerr's OpenAPI spec with swift-openapi-generator.
/// The feature is compiled in only when the `ANEMONE_SEERR` condition is set, so App Store
/// builds can leave it out.
public enum Seerr {
    public static var isAvailable: Bool {
        #if ANEMONE_SEERR
            true
        #else
            false
        #endif
    }
}
