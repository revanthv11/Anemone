#if ANEMONE_SEERR
    @testable import AnemoneSeerr
    import Foundation
    import Testing

    /// The titles on the Requests list, the first time it's read and when it's read again.
    struct SeerrRequestTitlesTests {
        @Test func `a series Seerr has no status for shows the same after a reload as at first`() async throws {
            let host = "unknown-series.seerr.test"
            let seerr = try await connection(to: host) { request in
                switch request.path {
                case "/api/v1/request":
                    // The user's approved request, and a later one still pending, for a series
                    // Seerr has no status for.
                    .json(#"""
                    {"pageInfo":{"page":1,"pages":1,"results":2},"results":[
                      {"id":2,"status":2,"type":"tv","media":{"tmdbId":1399,"status":1},"requestedBy":{"id":7}},
                      {"id":1,"status":1,"type":"tv","media":{"tmdbId":1399,"status":1},"requestedBy":{"id":7}}
                    ]}
                    """#)
                case "/api/v1/tv/1399":
                    .json(#"""
                    {"id":1399,"name":"Thrones","mediaInfo":{"status":1,"requests":[
                      {"id":2,"status":2,"requestedBy":{"id":7}},{"id":1,"status":1,"requestedBy":{"id":7}}
                    ]}}
                    """#)
                default:
                    .status(404)
                }
            }
            func lookups() -> Int {
                SeerrMockServer.requests(to: host).count { $0.path == "/api/v1/tv/1399" }
            }

            let first = try await seerr.requests()
            let lookedUp = lookups()
            let known = Dictionary(first.items.map { ($0.item.id, $0.item) }) { title, _ in title }
            let again = try await seerr.requests(known: known)

            // Both requests show the title as its lookup has it: pending, for the user's pending
            // request, rather than the approved one's processing after a reload.
            #expect(first.items.map(\.item.availability) == [.pending, .pending])
            #expect(again.items.map(\.item.availability) == first.items.map(\.item.availability))
            #expect(again.items.map(\.request.id) == [2, 1])
            // Such a series is looked up again: only its lookup lists all of the user's requests.
            #expect(lookups() == lookedUp * 2)
        }

        @Test func `a title Seerr has a status for takes it from its request, as its lookup would`() async throws {
            let host = "known-series.seerr.test"
            let seerr = try await connection(to: host) { request in
                switch request.path {
                case "/api/v1/request":
                    .json(#"""
                    {"pageInfo":{"page":1,"pages":1,"results":2},"results":[
                      {"id":2,"status":2,"type":"tv","media":{"tmdbId":1399,"status":3},"requestedBy":{"id":7}},
                      {"id":1,"status":1,"type":"movie","media":{"tmdbId":550,"status":1},"requestedBy":{"id":7}}
                    ]}
                    """#)
                case "/api/v1/tv/1399":
                    .json(#"{"id":1399,"name":"Thrones","mediaInfo":{"status":3}}"#)
                case "/api/v1/movie/550":
                    .json(#"{"id":550,"title":"Fight Club","mediaInfo":{"status":1}}"#)
                default:
                    .status(404)
                }
            }

            let first = try await seerr.requests()
            let lookedUp = SeerrMockServer.requests(to: host).count
            let known = Dictionary(first.items.map { ($0.item.id, $0.item) }) { title, _ in title }
            let again = try await seerr.requests(known: known)

            #expect(first.items.map(\.item.availability) == [.processing, .unknown])
            #expect(again.items.map(\.item.availability) == first.items.map(\.item.availability))
            // Only the list was read again: neither title was looked up.
            #expect(SeerrMockServer.requests(to: host).count == lookedUp + 1)
        }
    }
#endif
