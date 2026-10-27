#if ANEMONE_SEERR
    /// What a Seerr user may do, from the bit flags of their `permissions`. Ported from Wholphin's
    /// `SeerrPermission`, whose values come from Seerr's `server/lib/permissions.ts`.
    public enum SeerrPermission: CaseIterable, Sendable {
        case admin
        case manageSettings
        case manageUsers
        case manageRequests
        case request
        case vote
        case autoApprove
        case autoApproveMovie
        case autoApproveTV
        case request4K
        case request4KMovie
        case request4KTV
        case requestAdvanced
        case requestView
        case autoApprove4K
        case autoApprove4KMovie
        case autoApprove4KTV
        case requestMovie
        case requestTV
        case manageIssues
        case viewIssues
        case createIssues
        case autoRequest
        case autoRequestMovie
        case autoRequestTV
        case recentView
        case watchlistView
        case manageBlocklist
        case viewBlocklist

        var flag: Int {
            switch self {
            case .admin: 2
            case .manageSettings: 4
            case .manageUsers: 8
            case .manageRequests: 16
            case .request: 32
            case .vote: 64
            case .autoApprove: 128
            case .autoApproveMovie: 256
            case .autoApproveTV: 512
            case .request4K: 1024
            case .request4KMovie: 2048
            case .request4KTV: 4096
            case .requestAdvanced: 8192
            case .requestView: 16384
            case .autoApprove4K: 32768
            case .autoApprove4KMovie: 65536
            case .autoApprove4KTV: 131_072
            case .requestMovie: 262_144
            case .requestTV: 524_288
            case .manageIssues: 1_048_576
            case .viewIssues: 2_097_152
            case .createIssues: 4_194_304
            case .autoRequest: 8_388_608
            case .autoRequestMovie: 16_777_216
            case .autoRequestTV: 33_554_432
            case .recentView: 67_108_864
            case .watchlistView: 134_217_728
            case .manageBlocklist: 268_435_456
            case .viewBlocklist: 1_073_741_824
            }
        }

        /// The broader permissions that include this one, as in Seerr: "request" includes
        /// "request movies", for example.
        var parents: [SeerrPermission] {
            switch self {
            case .autoApproveMovie, .autoApproveTV: [.autoApprove]
            case .request4KMovie, .request4KTV: [.request4K]
            case .requestAdvanced, .requestView, .recentView, .watchlistView: [.manageRequests]
            case .autoApprove4KMovie, .autoApprove4KTV: [.autoApprove4K]
            case .requestMovie, .requestTV: [.request]
            case .viewIssues, .createIssues: [.manageIssues]
            case .autoRequestMovie, .autoRequestTV: [.autoRequest]
            case .viewBlocklist: [.manageBlocklist]
            default: []
            }
        }
    }

    /// A Seerr user's permission flags.
    public struct SeerrPermissions: Hashable, Sendable {
        public var rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        /// Whether the user has the permission, one that includes it, or is an admin, as
        /// Wholphin's `hasPermission`.
        public func contains(_ permission: SeerrPermission) -> Bool {
            hasFlag(of: permission)
                || permission.parents.contains { contains($0) }
                || hasFlag(of: .admin)
        }

        public var canRequestMovies: Bool {
            contains(.requestMovie) || contains(.request4KMovie)
        }

        public var canRequestSeries: Bool {
            contains(.requestTV) || contains(.request4KTV)
        }

        private func hasFlag(of permission: SeerrPermission) -> Bool {
            rawValue & permission.flag == permission.flag
        }
    }
#endif
