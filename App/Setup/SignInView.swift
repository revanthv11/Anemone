import AnemoneCore
import AnemoneJellyfin
import AnemoneUI
import SwiftUI

/// Password sign-in, with Quick Connect alongside when the server allows it.
struct SignInView: View {
    let server: SavedServer

    @Environment(AppModel.self) private var model
    @State private var username: String
    private let usernameIsFixed: Bool
    @State private var password = ""
    @State private var isSigningIn = false
    @State private var errorMessage: String?
    @State private var isQuickConnectAvailable = false
    @State private var quickConnectCode: String?
    @State private var quickConnectTask: Task<Void, Never>?
    @Environment(\.theme) private var theme

    init(server: SavedServer, username: String?) {
        self.server = server
        _username = State(initialValue: username ?? "")
        usernameIsFixed = username != nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: 120) {
            VStack(alignment: .leading, spacing: 32) {
                Text(usernameIsFixed ? "Sign in as \(username)" : "Sign in")
                    .font(.largeTitle.bold())
                    .foregroundStyle(theme.onBackground)
                    .accessibilityAddTraits(.isHeader)
                Text(server.name)
                    .foregroundStyle(theme.secondaryText)
                if !usernameIsFixed {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("signIn.username")
                }
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .onSubmit(signIn)
                    .accessibilityIdentifier("signIn.password")
                Button(isSigningIn ? "Signing in…" : "Sign in", action: signIn)
                    .disabled(isSigningIn || username.isEmpty)
                    .accessibilityIdentifier("signIn.submit")
                if let errorMessage {
                    NoticeText(errorMessage)
                }
            }
            .frame(maxWidth: 800, alignment: .leading)

            if isQuickConnectAvailable {
                quickConnect
                    .frame(maxWidth: 700, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(80)
        .task {
            isQuickConnectAvailable = await (try? model.authenticator.isQuickConnectEnabled(on: server.url)) ?? false
        }
        .onDisappear {
            quickConnectTask?.cancel()
        }
    }

    private var quickConnect: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Quick Connect")
                .font(.title2.bold())
                .foregroundStyle(theme.onBackground)
                .accessibilityAddTraits(.isHeader)
            if let quickConnectCode {
                Text(quickConnectCode)
                    .font(.system(size: 96, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.onBackground)
                    // Read a character at a time, as it's typed.
                    .accessibilityLabel(Text(verbatim: quickConnectCode).speechSpellsOutCharacters())
                    .accessibilityIdentifier("quickConnect.code")
                Text("""
                On a phone or computer that's signed in to \(server.name), \
                open Quick Connect and enter this code.
                """)
                .foregroundStyle(theme.secondaryText)
            } else {
                Text("Sign in by approving a code from a phone or computer that's already signed in.")
                    .foregroundStyle(theme.secondaryText)
                Button("Use Quick Connect", action: startQuickConnect)
                    .accessibilityIdentifier("quickConnect.start")
            }
        }
    }

    private func signIn() {
        guard !isSigningIn, !username.isEmpty else { return }
        Task {
            isSigningIn = true
            defer { isSigningIn = false }
            do {
                try await model.signIn(to: server, username: username, password: password)
            } catch AuthenticationError.invalidCredentials {
                errorMessage = String(localized: "Wrong username or password.")
            } catch {
                errorMessage = String(localized: "Couldn't sign in: \(error.localizedDescription)")
            }
        }
    }

    private func startQuickConnect() {
        quickConnectTask?.cancel()
        errorMessage = nil
        quickConnectTask = Task {
            do {
                for try await step in model.authenticator.quickConnect(to: server.url) {
                    switch step {
                    case let .code(code):
                        quickConnectCode = code
                    case let .signedIn(user):
                        model.finishSignIn(to: server, as: user)
                    }
                }
            } catch is CancellationError {
                // Left the screen.
            } catch {
                quickConnectCode = nil
                errorMessage = String(localized: "Quick Connect stopped. Try again.")
            }
        }
    }
}
