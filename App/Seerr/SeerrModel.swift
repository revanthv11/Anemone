#if ANEMONE_SEERR
    import AnemoneCore
    import AnemoneJellyfin
    import AnemoneSeerr
    import Foundation
    import Observation
    import SwiftUI

    /// The signed-in profile's Seerr connection, for the Discover tab, Settings › Seerr and the
    /// Discover rows on item pages. One per profile session, like `BrowseModel`; it signs in when
    /// the profile does, as Wholphin's `UserSwitchListener`.
    @Observable
    final class SeerrModel {
        /// `nil` while signing in.
        private(set) var status: SeerrStatus?
        /// The companion plugin's Seerr address, for the add-server page to fill in, once known.
        private(set) var suggestedAddress: String?

        @ObservationIgnored let browse: BrowseModel
        @ObservationIgnored private let signIn: SeerrSignIn
        @ObservationIgnored private var hasStarted = false
        /// Counts sign-ins, adding and removing, so only the latest sets `status`: a Retry while
        /// the first sign-in is still under way wins even when the first ends last.
        @ObservationIgnored private var attempt = 0

        init(browse: BrowseModel) {
            self.browse = browse
            let profile = SeerrAccountStore.Profile(serverID: browse.server.id, userID: browse.session.userID)
            signIn = SeerrSignIn(
                // A service of its own, so the sign-ins item's move into the Top Shelf's shared
                // group (`SharedStorage`) leaves Seerr's accounts alone.
                accounts: SeerrAccountStore(store: KeychainStore(service: "com.revanthv11.anemone.seerr")),
                profile: profile,
                configuration: Self.configuration,
            )
        }

        var connection: SeerrConnection? {
            status?.connection
        }

        /// Signs in the first time it's called.
        func start() async {
            guard !hasStarted else { return }
            hasStarted = true
            await connect()
        }

        /// Signs in with the plugin's server, then the profile's own account. Settings' Retry
        /// calls it again, which also reads the plugin's settings again, as Wholphin's
        /// `retryServerFromPlugin` does.
        func connect() async {
            let attempt = nextAttempt()
            status = nil
            // Read here rather than inside `connect`, which treats any failure as no settings
            // too, so the add-server page can offer the plugin's address.
            let settings: SeerrPluginSettings?
            do {
                settings = try await Self.pluginSettings(browse.session)
            } catch SessionError.signedOut {
                browse.noteSignedOut()
                settings = nil
            } catch {
                settings = nil
            }
            guard attempt == self.attempt else { return }
            suggestedAddress = settings?.address
            let status = await signIn.connect { settings }
            guard attempt == self.attempt else { return }
            show(status, attempt: attempt)
        }

        /// Signs in at what the user typed and keeps it as the profile's account.
        func add(address: String, method: SeerrAccount.Method, username: String?, secret: String) async throws {
            let connection = try await signIn.add(address: address, method: method, username: username, secret: secret)
            show(.connected(connection, isManagedByServer: false), attempt: nextAttempt())
        }

        /// Forgets the profile's own account. A server the plugin set up can't be removed.
        func remove() throws {
            try signIn.remove()
            _ = nextAttempt()
            status = .notConfigured(suggestedAddress: suggestedAddress)
        }

        private func nextAttempt() -> Int {
            attempt += 1
            return attempt
        }

        /// Shows `status`, then a failure in its place should Seerr sign its connection out for
        /// good: the session went and signing in again, with the plugin's login or the Keychain's
        /// password, didn't work. Settings then offers Retry.
        private func show(_ status: SeerrStatus, attempt: Int) {
            self.status = status
            guard case let .connected(connection, isManagedByServer) = status else { return }
            let failure = SeerrFailure(
                address: connection.serverURL.absoluteString,
                error: SeerrError.invalidCredentials,
                isManagedByServer: isManagedByServer,
            )
            connection.onSignedOut { [weak self] in
                Task { @MainActor in
                    guard let self, attempt == self.attempt else { return }
                    self.status = .failed(failure)
                }
            }
        }

        /// The plugin's Seerr settings, or made-up ones in DEBUG builds launched with
        /// `-seerrMock YES`.
        private static func pluginSettings(_ session: JellyfinSession) async throws -> SeerrPluginSettings? {
            #if DEBUG
                if let settings = SeerrDebugServer.pluginSettings {
                    return settings
                }
            #endif
            return try await session.serverPluginSeerrSettings()
        }

        private static let configuration: @Sendable () -> URLSessionConfiguration = {
            let configuration = URLSessionConfiguration.ephemeral
            #if DEBUG
                SeerrDebugServer.install(in: configuration)
            #endif
            return configuration
        }
    }

    extension View {
        /// Makes the profile's `SeerrModel` and signs it in, for everything below.
        func seerr(_ browse: BrowseModel) -> some View {
            modifier(SeerrProvider(browse: browse))
        }
    }

    private struct SeerrProvider: ViewModifier {
        let browse: BrowseModel
        @State private var model: SeerrModel?

        func body(content: Content) -> some View {
            content
                .environment(model)
                .task {
                    let model = model ?? SeerrModel(browse: browse)
                    self.model = model
                    await model.start()
                }
        }
    }
#endif
