#if ANEMONE_SEERR
    import AnemoneCore
    import Foundation
    import JellyfinAPI

    /// What Seerr needs from the Jellyfin server: the plugin's Seerr settings and the TMDB IDs that
    /// Seerr knows items by. Only in builds with `ANEMONE_SEERR` (docs/seerr.md).
    public extension JellyfinSession {
        /// The Seerr server the companion plugin sets up for every user, from its
        /// `GET /wholphin/seerrsettings`, as Wholphin's `fetchSeerrSettings` at `cecfdae`. `nil` when
        /// the plugin isn't installed or sets no server (it answers 404 then).
        func serverPluginSeerrSettings() async throws -> SeerrPluginSettings? {
            try await serverPluginValue(SeerrPluginSettings.self, path: "seerrsettings")
        }

        /// The item's TMDB ID, which Seerr's similar titles and credits are looked up by, as
        /// Wholphin's `SeerrService.similar` reads it from `providerIds`. `nil` when the server has
        /// none for it.
        ///
        /// A request of its own, since `ItemDetails` doesn't keep the provider IDs; it's only made
        /// when a Seerr server is connected.
        func tmdbID(ofItem id: MediaItem.ID) async throws -> Int? {
            let item = try await send(Paths.getItem(itemID: id, userID: userID))
            let ids = item.providerIDs ?? [:]
            // Jellyfin writes "Tmdb"; matched without case, as other clients have written it.
            let value = ids.first { $0.key.caseInsensitiveCompare("Tmdb") == .orderedSame }?.value
            return value.flatMap { Int($0) }
        }
    }
#endif
