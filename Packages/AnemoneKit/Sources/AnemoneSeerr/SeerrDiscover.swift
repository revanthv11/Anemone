#if ANEMONE_SEERR
    import Foundation

    /// The rows of Wholphin's Discover page (`SeerrDiscoverPage`), in its order.
    public enum DiscoverRow: String, CaseIterable, Hashable, Sendable {
        case trending
        case popularMovies
        case upcomingMovies
        case popularSeries
        case upcomingSeries

        public var title: String {
            switch self {
            case .trending: "Trending"
            case .popularMovies: "Movies"
            case .upcomingMovies: "Upcoming Movies"
            case .popularSeries: "TV Shows"
            case .upcomingSeries: "Upcoming TV Shows"
            }
        }
    }

    /// Finding titles, as Wholphin's `SeerrService`.
    public extension SeerrConnection {
        /// A page of one of the Discover page's rows.
        func discover(_ row: DiscoverRow, page: Int = 1) async throws -> [DiscoverItem] {
            switch row {
            case .trending:
                let results = try await client.getDiscoverTrending(query: .init(page: page)).ok.body.json.results
                return (results ?? []).compactMap { item(movie: $0.value1, series: $0.value2, person: $0.value3) }
            case .popularMovies:
                let results = try await client.getDiscoverMovies(query: .init(page: page)).ok.body.json.results
                return (results ?? []).compactMap(item(movie:))
            case .upcomingMovies:
                let results = try await client.getDiscoverMoviesUpcoming(query: .init(page: page)).ok.body.json.results
                return (results ?? []).compactMap(item(movie:))
            case .popularSeries:
                let results = try await client.getDiscoverTv(query: .init(page: page)).ok.body.json.results
                return (results ?? []).compactMap(item(series:))
            case .upcomingSeries:
                let results = try await client.getDiscoverTvUpcoming(query: .init(page: page)).ok.body.json.results
                return (results ?? []).compactMap(item(series:))
            }
        }

        /// Movies and series matching `query`; people are left out, as in Wholphin's Discover
        /// search.
        func search(_ query: String, page: Int = 1) async throws -> [DiscoverItem] {
            let results = try await client.getSearch(query: .init(query: query, page: page)).ok.body.json.results
            return (results ?? []).compactMap { item(movie: $0.value1, series: $0.value2, person: nil) }
        }

        /// Titles like the movie or series with this TMDB ID, as Wholphin's `similar` for the Discover
        /// row on its movie and series pages.
        func similar(to tmdbID: Int, kind: SeerrMediaKind) async throws -> [DiscoverItem] {
            switch kind {
            case .movie:
                let results = try await client.getMovieMovieIdSimilar(path: .init(movieId: tmdbID)).ok.body.json.results
                return (results ?? []).compactMap(item(movie:))
            case .series:
                let results = try await client.getTvTvIdSimilar(path: .init(tvId: tmdbID)).ok.body.json.results
                return (results ?? []).compactMap(item(series:))
            case .person:
                return try await credits(ofPerson: tmdbID)
            }
        }

        /// What TMDB recommends after the movie or series with this TMDB ID.
        func recommendations(for tmdbID: Int, kind: SeerrMediaKind) async throws -> [DiscoverItem] {
            switch kind {
            case .movie:
                let output = try await client.getMovieMovieIdRecommendations(path: .init(movieId: tmdbID))
                return try (output.ok.body.json.results ?? []).compactMap(item(movie:))
            case .series:
                let output = try await client.getTvTvIdRecommendations(path: .init(tvId: tmdbID))
                return try (output.ok.body.json.results ?? []).compactMap(item(series:))
            case .person:
                return []
            }
        }

        /// A person's movies and series, as Wholphin's `personCredits`: cast and crew together,
        /// each title once (a person can be both), newest first and undated ones last.
        func credits(ofPerson tmdbID: Int) async throws -> [DiscoverItem] {
            let output = try await client.getPersonPersonIdCombinedCredits(path: .init(personId: tmdbID))
            let credits = try output.ok.body.json
            let cast = (credits.cast ?? []).compactMap { credit in
                item(
                    credit: credit.id,
                    mediaType: credit.mediaType,
                    title: credit.title ?? credit.name,
                    role: credit.character,
                    overview: credit.overview,
                    date: credit.releaseDate ?? credit.firstAirDate,
                    poster: credit.posterPath,
                    backdrop: credit.backdropPath,
                    media: credit.mediaInfo,
                )
            }
            let crew = (credits.crew ?? []).compactMap { credit in
                item(
                    credit: credit.id,
                    mediaType: credit.mediaType,
                    title: credit.title ?? credit.name,
                    role: credit.job,
                    overview: credit.overview,
                    date: credit.releaseDate ?? credit.firstAirDate,
                    poster: credit.posterPath,
                    backdrop: credit.backdropPath,
                    media: credit.mediaInfo,
                )
            }
            return Self.newestFirst(Self.unique(cast + crew))
        }

        /// Each title once, in its first place, as Wholphin's `distinctBy`.
        static func unique(_ items: [DiscoverItem]) -> [DiscoverItem] {
            var seen = Set<DiscoverItem.ID>()
            return items.filter { seen.insert($0.id).inserted }
        }

        /// Newest first, undated last; titles from the same date keep their order.
        static func newestFirst(_ items: [DiscoverItem]) -> [DiscoverItem] {
            items.enumerated().sorted { lhs, rhs in
                switch (lhs.element.releaseDate, rhs.element.releaseDate) {
                case let (left?, right?) where left != right: left > right
                case (_?, nil): true
                case (nil, _?): false
                default: lhs.offset < rhs.offset
                }
            }
            .map(\.element)
        }
    }

    // MARK: Turning Seerr's results into items

    extension SeerrConnection {
        func item(movie: Components.Schemas.MovieResult) -> DiscoverItem? {
            DiscoverItem(
                tmdbID: movie.id,
                kind: .movie,
                title: movie.title ?? movie.originalTitle ?? "",
                overview: movie.overview,
                availability: SeerrAvailability(status: movie.mediaInfo?.status),
                releaseDate: movie.releaseDate,
                posterURL: imageURL(.poster, path: movie.posterPath),
                backdropURL: imageURL(.backdrop, path: movie.backdropPath),
                jellyfinItemID: movie.mediaInfo?.jellyfinItemID,
            )
        }

        func item(series: Components.Schemas.TvResult) -> DiscoverItem? {
            guard let id = series.id else { return nil }
            return DiscoverItem(
                tmdbID: id,
                kind: .series,
                title: series.name ?? series.originalName ?? "",
                overview: series.overview,
                availability: SeerrAvailability(status: series.mediaInfo?.status),
                releaseDate: series.firstAirDate,
                posterURL: imageURL(.poster, path: series.posterPath),
                backdropURL: imageURL(.backdrop, path: series.backdropPath),
                jellyfinItemID: series.mediaInfo?.jellyfinItemID,
            )
        }

        /// One of a mixed list's results, which may decode as any of its types, so its
        /// `mediaType` says which it is.
        func item(
            movie: Components.Schemas.MovieResult?,
            series: Components.Schemas.TvResult?,
            person: Components.Schemas.PersonResult?,
        ) -> DiscoverItem? {
            let mediaType = movie?.mediaType ?? series?.mediaType ?? person?.mediaType
            switch SeerrMediaKind(mediaType: mediaType) {
            case .movie: return movie.flatMap(item(movie:))
            case .series: return series.flatMap(item(series:))
            case .person, nil: return nil
            }
        }

        // swiftlint:disable:next function_parameter_count
        func item(
            credit id: Int?,
            mediaType: String?,
            title: String?,
            role: String?,
            overview: String?,
            date: String?,
            poster: String?,
            backdrop: String?,
            media: Components.Schemas.MediaInfo?,
        ) -> DiscoverItem? {
            // Wholphin falls back to a person for credits without a type; there are none in
            // practice, and a person can't be requested, so they're left out.
            guard let id, let kind = SeerrMediaKind(mediaType: mediaType), kind != .person else { return nil }
            return DiscoverItem(
                tmdbID: id,
                kind: kind,
                title: title ?? "",
                subtitle: role,
                overview: overview,
                availability: SeerrAvailability(status: media?.status),
                releaseDate: date,
                posterURL: imageURL(.poster, path: poster),
                backdropURL: imageURL(.backdrop, path: backdrop),
                jellyfinItemID: media?.jellyfinItemID,
            )
        }

        enum ImageKind {
            case poster
            case backdrop
        }

        /// A TMDB image, through Seerr when it caches images, as Wholphin's `createImageUrl`.
        func imageURL(_ kind: ImageKind, path: String?) -> URL? {
            guard let path, !path.isEmpty else { return nil }
            var base = settings.cachesImages ? serverURL.absoluteString : "https://image.tmdb.org"
            while base.hasSuffix("/") {
                base.removeLast()
            }
            if settings.cachesImages {
                base += "/imageproxy/tmdb"
            }
            let size = switch kind {
            case .poster: "/t/p/w500"
            case .backdrop: "/t/p/w1920_and_h1080_multi_faces"
            }
            return URL(string: base + size + (path.hasPrefix("/") ? path : "/" + path))
        }
    }

    extension Components.Schemas.MediaInfo {
        /// The Jellyfin item, preferring the 4K copy as Wholphin's `jellyfinId` does, written the
        /// way Anemone's item IDs are: 32 lowercase hex digits.
        var jellyfinItemID: String? {
            [jellyfinMediaId4k, jellyfinMediaId]
                .compactMap { $0?.replacingOccurrences(of: "-", with: "").lowercased() }
                .first { $0.count == 32 && $0.allSatisfy(\.isHexDigit) }
        }
    }

    extension SeerrUser {
        init(_ user: Components.Schemas.User) {
            let name = [user.username, user.plexUsername, user.email]
                .compactMap(\.self)
                .first { !$0.isEmpty }
            self.init(id: user.id, name: name ?? "", permissions: SeerrPermissions(rawValue: user.permissions ?? 0))
        }
    }

    extension SeerrServerSettings {
        init(_ settings: Components.Schemas.PublicSettings) {
            self.init(
                cachesImages: settings.cacheImages ?? false,
                allows4KMovies: settings.movie4kEnabled ?? false,
                allows4KSeries: settings.series4kEnabled ?? false,
            )
        }
    }
#endif
