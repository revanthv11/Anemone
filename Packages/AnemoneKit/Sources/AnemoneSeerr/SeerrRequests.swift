#if ANEMONE_SEERR
    import Foundation

    /// A title's page and requests, as Wholphin's `DiscoverMovieViewModel`,
    /// `DiscoverSeriesViewModel` and `SeerrRequestsViewModel`.
    public extension SeerrConnection {
        /// A movie's details and requests.
        func movie(_ tmdbID: Int) async throws -> DiscoverDetails {
            let movie = try await client.getMovieMovieId(path: .init(movieId: tmdbID)).ok.body.json
            let item = DiscoverItem(
                tmdbID: movie.id ?? tmdbID,
                kind: .movie,
                title: movie.title ?? movie.originalTitle ?? "",
                overview: movie.overview,
                availability: SeerrAvailability(status: movie.mediaInfo?.status),
                releaseDate: movie.releaseDate,
                posterURL: imageURL(.poster, path: movie.posterPath),
                backdropURL: imageURL(.backdrop, path: movie.backdropPath),
                jellyfinItemID: movie.mediaInfo?.jellyfinItemID,
            )
            return DiscoverDetails(
                item: item,
                tagline: movie.tagline.flatMap { $0.isEmpty ? nil : $0 },
                genres: (movie.genres ?? []).compactMap(\.name),
                runtime: movie.runtime.map { Int($0) },
                rating: movie.voteAverage,
                requests: (movie.mediaInfo?.requests ?? []).map(SeerrRequest.init),
            )
        }

        /// A series' details, requests and seasons. Its availability is the user's, as Wholphin's
        /// `updateAvailability`: a series Seerr knows nothing of shows the user's own pending or
        /// approved request.
        func series(_ tmdbID: Int) async throws -> DiscoverDetails {
            let series = try await client.getTvTvId(path: .init(tvId: tmdbID)).ok.body.json
            let requests = (series.mediaInfo?.requests ?? []).map(SeerrRequest.init)
            var item = DiscoverItem(
                tmdbID: series.id ?? tmdbID,
                kind: .series,
                title: series.name ?? series.originalName ?? "",
                overview: series.overview,
                availability: SeerrAvailability(status: series.mediaInfo?.status),
                releaseDate: series.firstAirDate,
                posterURL: imageURL(.poster, path: series.posterPath),
                backdropURL: imageURL(.backdrop, path: series.backdropPath),
                jellyfinItemID: series.mediaInfo?.jellyfinItemID,
            )
            item.availability = SeerrRequest.availability(item.availability, requests: requests, user: user.id)
            let seasons = (series.seasons ?? []).compactMap(SeasonFacts.init)
            let known = (series.mediaInfo?.seasons ?? []).compactMap(SeasonFacts.init)
            return DiscoverDetails(
                item: item,
                tagline: series.tagline.flatMap { $0.isEmpty ? nil : $0 },
                genres: (series.genres ?? []).compactMap(\.name),
                runtime: series.episodeRunTime?.first,
                rating: series.voteAverage,
                requests: requests,
                seasons: SeerrSeason.seasons(seasons, known: known, requests: requests, user: user.id, is4K: false),
                seasons4K: SeerrSeason.seasons(seasons, known: known, requests: requests, user: user.id, is4K: true),
            )
        }

        /// How many requests a page of the Requests list holds: Wholphin's `SEERR_PAGE_SIZE`, the
        /// page size of its Discover grids.
        static let requestsPageSize = 20

        /// A page of the requests the user may see, newest first: `take` of them from the
        /// `skip`th, each with its title. Like Wholphin, a title is looked up for each request,
        /// three at a time, and requests whose title can't be found are left out.
        ///
        /// Fixed while porting: Wholphin reads only the first page, at Seerr's default of 10
        /// requests, so a user with more never sees the older ones. `SeerrRequestList` reads on.
        func requests(skip: Int = 0, take: Int = requestsPageSize) async throws -> SeerrRequestsPage {
            struct Wanted {
                let request: SeerrRequest
                let tmdbID: Int
                let kind: SeerrMediaKind
            }
            let page = try await client.getRequest(query: .init(take: take, skip: skip)).ok.body.json
            let requests = page.results ?? []
            let end = skip + requests.count
            // Seerr counts every request the user may see. Without that count, a full page may
            // have more after it.
            let hasMore = !requests.isEmpty && (page.pageInfo?.results.map { end < $0 } ?? (requests.count >= take))
            let wanted = requests.compactMap { request -> Wanted? in
                guard let tmdbID = request.media?.tmdbId,
                      let kind = SeerrMediaKind(mediaType: request._type), kind != .person
                else { return nil }
                return Wanted(request: SeerrRequest(request), tmdbID: tmdbID, kind: kind)
            }
            var found: [Int: SeerrRequestedItem] = [:]
            try await withThrowingTaskGroup(of: SeerrRequestedItem?.self) { group in
                var next = wanted.makeIterator()
                func addNext() {
                    guard let wanted = next.next() else { return }
                    group.addTask {
                        let details = try? await wanted.kind == .movie ? movie(wanted.tmdbID) : series(wanted.tmdbID)
                        return details.map { SeerrRequestedItem(request: wanted.request, item: $0.item) }
                    }
                }
                for _ in 0 ..< 3 {
                    addNext()
                }
                while let result = try await group.next() {
                    if let result {
                        found[result.id] = result
                    }
                    addNext()
                }
            }
            return SeerrRequestsPage(items: wanted.compactMap { found[$0.request.id] }, end: end, hasMore: hasMore)
        }

        /// Asks for a movie, in 4K or not. Seerr picks the server, quality and folder.
        func requestMovie(_ tmdbID: Int, is4K: Bool) async throws {
            let body = Operations.PostRequest.Input.Body.JsonPayload(mediaType: .movie, mediaId: tmdbID, is4k: is4K)
            let output = try await client.postRequest(body: .json(body))
            if case let .undocumented(status, _) = output {
                throw SeerrError(statusCode: status)
            }
        }

        /// Asks for a series' seasons, in 4K or not. When the user already has a pending request
        /// at that quality, it's changed to these seasons, as Wholphin does, rather than adding a
        /// second one.
        ///
        /// - Parameter seasons: the seasons ticked among those `details` offers at that quality
        ///   (`isRequestable`). A season of the user's pending request that isn't offered, and so
        ///   couldn't be unticked, stays in the request: only unticking takes one out.
        func requestSeries(_ details: DiscoverDetails, seasons: [Int], is4K: Bool) async throws {
            if let pending = details.requests.first(where: {
                $0.status == .pending && $0.requestedBy == user.id && $0.is4K == is4K
            }) {
                let offered = (is4K ? details.seasons4K : details.seasons).filter(\.isRequestable).map(\.number)
                let kept = Set(pending.seasons.keys).subtracting(offered)
                let body = Operations.PutRequestRequestId.Input.Body.JsonPayload(
                    mediaType: .tv,
                    seasons: kept.union(seasons).sorted(),
                    is4k: is4K,
                )
                let output = try await client.putRequestRequestId(
                    path: .init(requestId: String(pending.id)),
                    body: .json(body),
                )
                if case let .undocumented(status, _) = output {
                    throw SeerrError(statusCode: status)
                }
            } else {
                let body = Operations.PostRequest.Input.Body.JsonPayload(
                    mediaType: .tv,
                    mediaId: details.item.tmdbID,
                    seasons: seasons,
                    is4k: is4K,
                )
                let output = try await client.postRequest(body: .json(body))
                if case let .undocumented(status, _) = output {
                    throw SeerrError(statusCode: status)
                }
            }
        }

        /// Withdraws a request.
        func cancelRequest(_ request: SeerrRequest) async throws {
            let output = try await client.deleteRequestRequestId(path: .init(requestId: String(request.id)))
            if case let .undocumented(status, _) = output {
                throw SeerrError(statusCode: status)
            }
        }

        /// The request the user may withdraw on a title's page, as Wholphin's
        /// `canUserCancelRequest` decides whether to offer Cancel.
        ///
        /// Fixed while porting: Wholphin then deletes the title's first request, whoever made it;
        /// this is the user's own request that hasn't been approved yet, or, for a user who
        /// manages requests, the first.
        func requestToCancel(in details: DiscoverDetails) -> SeerrRequest? {
            let permissions = user.permissions
            if permissions.contains(.request),
               let own = details.requests.first(where: { $0.requestedBy == user.id && $0.status < .approved })
            {
                return own
            }
            if permissions.contains(.manageRequests) {
                return details.requests.first
            }
            return nil
        }
    }

    extension SeerrRequest {
        init(_ request: Components.Schemas.MediaRequest) {
            var seasons: [Int: SeerrRequestStatus] = [:]
            for season in request.seasons ?? [] {
                if let number = season.seasonNumber {
                    seasons[number] = SeerrRequestStatus(status: season.status)
                }
            }
            self.init(
                id: request.id,
                status: SeerrRequestStatus(status: request.status),
                is4K: request.is4k ?? false,
                requestedBy: request.requestedBy?.id,
                seasons: seasons,
            )
        }

        /// A series' availability for the user: when Seerr knows nothing of it, their own pending
        /// request makes it pending and their approved one processing.
        static func availability(
            _ overall: SeerrAvailability,
            requests: [SeerrRequest],
            user: Int,
        ) -> SeerrAvailability {
            guard overall == .unknown else { return overall }
            let own = requests.filter { $0.requestedBy == user }
            if own.contains(where: { $0.status == .pending }) {
                return .pending
            }
            if own.contains(where: { $0.status == .approved }) {
                return .processing
            }
            return .unknown
        }
    }

    /// A season as Seerr lists it: its number, and what the server has of it.
    struct SeasonFacts {
        var number: Int
        var name: String?
        var episodeCount: Int?
        var status: Int?
        var status4K: Int?

        init?(_ season: Components.Schemas.Season) {
            guard let number = season.seasonNumber else { return nil }
            self.number = number
            name = season.name
            episodeCount = season.episodeCount
            status = season.status
            status4K = season.status4k
        }

        init(number: Int, name: String? = nil, episodeCount: Int? = nil, status: Int? = nil, status4K: Int? = nil) {
            self.number = number
            self.name = name
            self.episodeCount = episodeCount
            self.status = status
            self.status4K = status4K
        }
    }

    extension SeerrSeason {
        /// Each season's availability, request status and whether it can be requested, at one
        /// quality. Ported from Wholphin's `updateSeasonStatus`.
        ///
        /// Fixed while porting: in Wholphin, whichever request for a season comes last decides
        /// whether the user may change it, so another user's request, or a declined one, listed
        /// after the user's own pending request locks that season, and changing the request then
        /// drops it. The user's own pending request wins for its seasons, wherever it's listed;
        /// for other seasons, anyone else's request holds the season unless the user's own was
        /// declined, whatever the order.
        ///
        /// - Parameters:
        ///   - seasons: the series' seasons from TMDB, which set the list and its order.
        ///   - known: the seasons Seerr has records of, whose availability wins when higher.
        static func seasons(
            _ seasons: [SeasonFacts],
            known: [SeasonFacts],
            requests: [SeerrRequest],
            user: Int,
            is4K: Bool,
        ) -> [SeerrSeason] {
            var availability: [Int: SeerrAvailability] = [:]
            for season in seasons {
                availability[season.number] = SeerrAvailability(status: is4K ? season.status4K : season.status)
            }
            for season in known {
                let status = SeerrAvailability(status: is4K ? season.status4K : season.status)
                if status > availability[season.number, default: .unknown] {
                    availability[season.number] = status
                }
            }
            let requested = Requested(requests.filter { $0.is4K == is4K }, user: user)
            return seasons.map { season in
                let status = requested.status[season.number, default: .unknown]
                let shown: SeerrAvailability = switch status {
                case .pending: .pending
                case .approved: .processing
                case .declined, .failed: .unknown
                case .unknown, .completed: availability[season.number, default: .unknown]
                }
                let requestable = ![.available, .partiallyAvailable, .processing, .blocklisted].contains(shown)
                return SeerrSeason(
                    number: season.number,
                    name: season.name,
                    episodeCount: season.episodeCount,
                    availability: shown,
                    requestStatus: status,
                    isRequestable: requested.own.contains(season.number)
                        || (requested.mayAskAgain[season.number] ?? requestable),
                    isInOwnRequest: requested.own.contains(season.number),
                )
            }
        }

        /// What a series' requests at one quality say of each season.
        private struct Requested {
            /// The furthest any request for it has got.
            var status: [Int: SeerrRequestStatus] = [:]
            /// The seasons of the user's own pending request.
            var own: Set<Int> = []
            /// For seasons in other requests, whether the user may ask for them again.
            var mayAskAgain: [Int: Bool] = [:]

            init(_ requests: [SeerrRequest], user: Int) {
                for request in requests {
                    let isOwn = request.requestedBy == user
                    for (number, status) in request.seasons {
                        if status > self.status[number, default: .unknown] {
                            self.status[number] = status
                        }
                        if isOwn, request.status == .pending {
                            own.insert(number)
                        } else {
                            mayAskAgain[number] = mayAskAgain[number, default: true]
                                && isOwn && request.status == .declined
                        }
                    }
                }
            }
        }
    }
#endif
