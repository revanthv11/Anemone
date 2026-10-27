import AnemoneCore

/// What NOTICE.md credits for Seerr alone: Seerr's API description and the packages its client
/// runs on. Builds without `ANEMONE_SEERR` include none of it, so Settings › About leaves it out
/// of them (docs/seerr.md).
enum SeerrCredits {
    static let names: Set<String> = [
        "Seerr",
        "swift-openapi-runtime",
        "swift-openapi-urlsession",
        "swift-http-types",
    ]

    /// What this build's About page leaves out.
    static var leftOut: Set<String> {
        #if ANEMONE_SEERR
            []
        #else
            names
        #endif
    }
}
