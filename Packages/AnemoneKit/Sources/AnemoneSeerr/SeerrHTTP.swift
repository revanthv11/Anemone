#if ANEMONE_SEERR
    import Foundation
    import HTTPTypes
    import OpenAPIRuntime
    import OpenAPIURLSession
    import Synchronization

    /// Why a Seerr request failed.
    public enum SeerrError: Error, Equatable, Sendable {
        /// What was typed isn't an address.
        case invalidAddress
        /// Seerr turned down the username and password or API key (401 or 403 on sign-in).
        case invalidCredentials
        /// The user may not do this (403).
        case forbidden
        /// Seerr answered with another error status.
        case status(Int)
        /// Seerr answered with something the client couldn't read, or no server answered.
        case unexpectedResponse
    }

    /// How to sign in to Seerr, as Wholphin's `SeerrAuthMethod` with its credentials.
    public enum SeerrCredentials: Sendable {
        case apiKey(String)
        /// A Seerr account: Seerr calls the username an email.
        case local(username: String, password: String)
        /// The user's Jellyfin account, which Seerr checks with the Jellyfin server.
        case jellyfin(username: String, password: String)

        var apiKey: String? {
            if case let .apiKey(key) = self {
                return key
            }
            return nil
        }
    }

    extension SeerrCredentials: CustomStringConvertible, CustomDebugStringConvertible {
        /// Names the kind of sign-in but never the password or key, should it reach a log.
        public var description: String {
            switch self {
            case .apiKey: "apiKey(<hidden>)"
            case .local: "local(<hidden>)"
            case .jellyfin: "jellyfin(<hidden>)"
            }
        }

        public var debugDescription: String {
            description
        }
    }

    /// Adds what each request to Seerr needs to be signed in: the API key, or the session cookie
    /// Seerr set when signing in with a password. Like Wholphin's `SeerrApiClient` with its
    /// cookie jar, it keeps only Seerr's `connect.sid` cookie, in memory, never on disk.
    ///
    /// It also keeps the connection signed in, which Wholphin leaves to its cookie jar. Seerr
    /// turns requests down (401 or 403) once its session has gone, as when the server restarts or
    /// the cookie expires, so the first request turned down asks `renew` to sign in again, once,
    /// and is sent again; requests turned down at the same time wait for that sign-in rather than
    /// make their own. When signing in again fails, the connection stays signed out and
    /// `onSignedOut`'s action runs, so the app can offer Retry.
    final class SeerrSigning: ClientMiddleware {
        /// What trying to sign in again found.
        enum Renewal: Sendable {
            /// The session still works: the request was turned down for something else, such as
            /// a permission the user doesn't have.
            case stillSignedIn
            case renewed
            /// The server couldn't say, such as when it didn't answer; nothing changes.
            case unknown
            /// The session has gone and signing in again didn't work.
            case signedOut
        }

        private struct State {
            var cookie: String?
            /// Goes up with each renewal, so a request turned down with an older session is just
            /// sent again.
            var session = 0
            var renewal: Task<Renewal, Never>?
            var renew: (@Sendable (SeerrSigning) async -> Renewal)?
            var onSignedOut: (@Sendable () -> Void)?
            var isSignedOut = false
        }

        /// What signing in or checking the session sends, which are never renewed themselves.
        private static let signInOperations: Set<String> = [
            Operations.GetAuthMe.id,
            Operations.PostAuthLocal.id,
            Operations.PostAuthJellyfin.id,
        ]

        private let apiKey: String?
        private let state = Mutex(State())

        init(apiKey: String?) {
            self.apiKey = apiKey
        }

        /// How to sign in again, once signed in; it's given this middleware to send through.
        func renew(with renew: @escaping @Sendable (SeerrSigning) async -> Renewal) {
            state.withLock { $0.renew = renew }
        }

        /// Runs `action` once Seerr has signed the connection out and signing in again failed;
        /// right away when that has already happened.
        func onSignedOut(_ action: @escaping @Sendable () -> Void) {
            let isSignedOut = state.withLock { state in
                state.onSignedOut = action
                return state.isSignedOut
            }
            if isSignedOut {
                action()
            }
        }

        func intercept(
            _ request: HTTPRequest,
            body: HTTPBody?,
            baseURL: URL,
            operationID: String,
            next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?),
        ) async throws -> (HTTPResponse, HTTPBody?) {
            var session = 0
            let (response, responseBody) = try await send(request, body, baseURL, next, session: &session)
            guard response.status.code == 401 || response.status.code == 403,
                  !Self.signInOperations.contains(operationID),
                  // A body that can only be read once has gone with the first try.
                  body.map({ $0.iterationBehavior == .multiple }) ?? true,
                  await renewed(since: session)
            else {
                return (response, responseBody)
            }
            return try await send(request, body, baseURL, next, session: &session)
        }

        /// Sends `request` signed in, and notes in `session` which session it went with.
        private func send(
            _ request: HTTPRequest,
            _ body: HTTPBody?,
            _ baseURL: URL,
            _ next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?),
            session: inout Int,
        ) async throws -> (HTTPResponse, HTTPBody?) {
            var request = request
            if let apiKey, !apiKey.isEmpty, let name = HTTPField.Name("X-Api-Key") {
                request.headerFields[name] = apiKey
            }
            let (current, cookie) = state.withLock { ($0.session, $0.cookie) }
            session = current
            if let cookie {
                request.headerFields[.cookie] = cookie
            }
            let (response, responseBody) = try await next(request, body, baseURL)
            noteCookies(in: response, from: baseURL)
            return (response, responseBody)
        }

        /// Whether the session has been renewed since `session`, signing in again unless another
        /// request already is.
        private func renewed(since session: Int) async -> Bool {
            enum Step {
                case resend
                case giveUp
                case wait(Task<Renewal, Never>)
            }
            let step: Step = state.withLock { state in
                if state.session != session {
                    return .resend
                }
                if state.isSignedOut {
                    return .giveUp
                }
                if let renewal = state.renewal {
                    return .wait(renewal)
                }
                guard let renew = state.renew else { return .giveUp }
                let renewal = Task {
                    let result = await renew(self)
                    return self.finish(result)
                }
                state.renewal = renewal
                return .wait(renewal)
            }
            switch step {
            case .resend:
                return true
            case .giveUp:
                return false
            case let .wait(renewal):
                return await renewal.value == .renewed
            }
        }

        private func finish(_ renewal: Renewal) -> Renewal {
            let onSignedOut = state.withLock { state -> (@Sendable () -> Void)? in
                state.renewal = nil
                switch renewal {
                case .renewed:
                    state.session += 1
                case .signedOut:
                    state.isSignedOut = true
                    return state.onSignedOut
                case .stillSignedIn, .unknown:
                    break
                }
                return nil
            }
            onSignedOut?()
            return renewal
        }

        private func noteCookies(in response: HTTPResponse, from url: URL) {
            let values = response.headerFields[values: .setCookie]
            guard !values.isEmpty else { return }
            var cookies: [HTTPCookie] = []
            for value in values {
                cookies += HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": value], for: url)
            }
            if let session = cookies.last(where: { $0.name == "connect.sid" }) {
                state.withLock { $0.cookie = "\(session.name)=\(session.value)" }
            }
        }
    }

    extension Client {
        /// A client for the Seerr server at `serverURL` (its own address; the API's is derived).
        init(serverURL: URL, signing: SeerrSigning, transport: URLSessionTransport) {
            self.init(serverURL: SeerrAddress.apiURL(for: serverURL), transport: transport, middlewares: [signing])
        }
    }

    extension URLSessionTransport {
        /// A transport for Seerr that waits at most `timeout` for each request and handles no
        /// cookies itself, so the session cookie only ever lives in `SeerrSigning`. It works on a
        /// copy of `configuration`, leaving the caller's as it was.
        static func seerr(_ configuration: URLSessionConfiguration, timeout: TimeInterval) -> URLSessionTransport {
            // A configuration's copy is always a configuration.
            let configuration = configuration.copy() as? URLSessionConfiguration ?? .ephemeral
            configuration.timeoutIntervalForRequest = min(configuration.timeoutIntervalForRequest, timeout)
            configuration.httpCookieStorage = nil
            configuration.httpShouldSetCookies = false
            configuration.httpCookieAcceptPolicy = .never
            configuration.urlCache = nil
            return URLSessionTransport(configuration: .init(
                session: URLSession(configuration: configuration),
                httpBodyProcessingMode: .buffered,
            ))
        }
    }

    extension SeerrError {
        /// The error for a status the API description doesn't list for the request.
        init(statusCode: Int) {
            switch statusCode {
            case 401: self = .invalidCredentials
            case 403: self = .forbidden
            default: self = .status(statusCode)
            }
        }

        /// The error for a status while signing in, where Seerr answers 401 or 403 to a wrong
        /// password or API key.
        init(signInStatus statusCode: Int) {
            self = statusCode == 401 || statusCode == 403 ? .invalidCredentials : .status(statusCode)
        }
    }
#endif
