#if ANEMONE_SEERR
    import AnemoneSeerr
    import Testing

    /// Ported from Wholphin's `TestSeerrPermission`.
    struct SeerrPermissionTests {
        @Test func `an admin may do anything`() {
            let user = SeerrPermissions(rawValue: 2)
            #expect(user.contains(.admin))
            #expect(user.contains(.request4KMovie))
            #expect(user.contains(.request4KTV))
            #expect(user.contains(.request4K))
        }

        @Test func `requesting anything in 4K includes 4K movies and series`() {
            let user = SeerrPermissions(rawValue: 1024)
            #expect(!user.contains(.admin))
            #expect(user.contains(.request4KMovie))
            #expect(user.contains(.request4KTV))
            #expect(user.contains(.request4K))
        }

        @Test func `4K movies alone don't include 4K series`() {
            let user = SeerrPermissions(rawValue: 2048)
            #expect(!user.contains(.admin))
            #expect(user.contains(.request4KMovie))
            #expect(!user.contains(.request4KTV))
            #expect(!user.contains(.request4K))
        }

        @Test func `4K with both its parts includes each`() {
            let user = SeerrPermissions(rawValue: 7168)
            #expect(!user.contains(.admin))
            #expect(user.contains(.request4KMovie))
            #expect(user.contains(.request4KTV))
            #expect(user.contains(.request4K))
        }

        @Test func `both parts of 4K don't make the whole`() {
            let user = SeerrPermissions(rawValue: 6144)
            #expect(!user.contains(.admin))
            #expect(user.contains(.request4KMovie))
            #expect(user.contains(.request4KTV))
            #expect(!user.contains(.request4K))
        }

        @Test func `the request permission lets a user request movies and series`() {
            let user = SeerrPermissions(rawValue: 32)
            #expect(user.canRequestMovies)
            #expect(user.canRequestSeries)
            #expect(!SeerrPermissions(rawValue: 0).canRequestMovies)
        }
    }
#endif
