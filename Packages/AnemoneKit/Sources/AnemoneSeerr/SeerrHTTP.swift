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

    /// Adds what each request to Seerr needs to be signed in: the API key, or the session cookie
    /// Seerr set when signing in with a password. Like Wholphin's `SeerrApiClient` with its
    /// cookie jar, it keeps only Seerr's `connect.sid` cookie, in memory, never on disk.
    final class SeerrSigning: ClientMiddleware {
        private let apiKey: String?
        private let cookie = Mutex<String?>(nil)

        init(apiKey: String?) {
            self.apiKey = apiKey
        }

        func intercept(
            _ request: HTTPRequest,
            body: HTTPBody?,
            baseURL: URL,
            operationID _: String,
            next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?),
        ) async throws -> (HTTPResponse, HTTPBody?) {
            var request = request
            if let apiKey, !apiKey.isEmpty, let name = HTTPField.Name("X-Api-Key") {
                request.headerFields[name] = apiKey
            }
            if let cookie = cookie.withLock(\.self) {
                request.headerFields[.cookie] = cookie
            }
            let (response, responseBody) = try await next(request, body, baseURL)
            noteCookies(in: response, from: baseURL)
            return (response, responseBody)
        }

        private func noteCookies(in response: HTTPResponse, from url: URL) {
            let values = response.headerFields[values: .setCookie]
            guard !values.isEmpty else { return }
            var cookies: [HTTPCookie] = []
            for value in values {
                cookies += HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": value], for: url)
            }
            if let session = cookies.last(where: { $0.name == "connect.sid" }) {
                cookie.withLock { $0 = "\(session.name)=\(session.value)" }
            }
        }
    }

    extension Client {
        /// A client for the Seerr server at `serverURL` (its own address; the API's is derived).
        ///
        /// The session handles no cookies itself, so the session cookie only ever lives in
        /// `SeerrSigning`.
        init(serverURL: URL, signing: SeerrSigning, configuration: URLSessionConfiguration) {
            configuration.httpCookieStorage = nil
            configuration.httpShouldSetCookies = false
            configuration.httpCookieAcceptPolicy = .never
            configuration.urlCache = nil
            let session = URLSession(configuration: configuration)
            self.init(
                serverURL: SeerrAddress.apiURL(for: serverURL),
                transport: URLSessionTransport(configuration: .init(
                    session: session,
                    httpBodyProcessingMode: .buffered,
                )),
                middlewares: [signing],
            )
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
