#if ANEMONE_SEERR
    import AnemoneSeerr
    import SwiftUI

    /// Settings › Seerr: the Seerr server this profile discovers and requests with. Ported from
    /// Wholphin's Seerr preference and `SeerrDialog` at `cecfdae`.
    ///
    /// Wholphin shows a dialog for each state; here the page shows the state and its actions:
    /// Add, Remove, or Retry, which is all a server the companion plugin set up ("Managed by
    /// server") offers.
    struct SeerrSettingsPage: View {
        @Environment(SeerrModel.self) private var seerr: SeerrModel?
        @State private var isConfirmingRemove = false
        @State private var problem: String?

        var body: some View {
            List {
                Section {
                    status
                        // Somewhere for focus to rest when the page offers no action.
                        .focusable()
                }
                Section {
                    actions
                }
                if let problem {
                    Text(problem)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Seerr")
            .confirmationDialog("Remove the Seerr server?", isPresented: $isConfirmingRemove) {
                Button("Remove", role: .destructive) {
                    remove()
                }
            } message: {
                Text("Discover and the Discover rows go until a server is added again.")
            }
        }

        @ViewBuilder
        private var status: some View {
            switch seerr?.status {
            case nil:
                Text("Signing in…")
                    .foregroundStyle(.secondary)
            case .notConfigured:
                Text("No Seerr server is set up. Add one to discover movies and shows and ask for them.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("seerr.status")
            case let .connected(connection, isManagedByServer):
                VStack(alignment: .leading, spacing: 8) {
                    Text("Signed in as \(connection.user.name)")
                        .accessibilityIdentifier("seerr.status")
                    Text(connection.serverURL.absoluteString)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if isManagedByServer {
                        Text("Managed by server")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("seerr.managed")
                    }
                }
            case let .failed(failure):
                VStack(alignment: .leading, spacing: 8) {
                    Text("Couldn't sign in to \(failure.address)")
                        .accessibilityIdentifier("seerr.status")
                    Text(failure.reason)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if failure.isManagedByServer {
                        Text("Managed by server")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("seerr.managed")
                    }
                }
            }
        }

        @ViewBuilder
        private var actions: some View {
            switch seerr?.status {
            case nil:
                EmptyView()
            case .notConfigured:
                NavigationLink("Add Server") {
                    SeerrAddServerPage()
                }
                .accessibilityIdentifier("seerr.add")
            case let .connected(_, isManagedByServer):
                if !isManagedByServer {
                    removeButton
                }
            case let .failed(failure):
                Button("Retry") {
                    Task { await seerr?.connect() }
                }
                .accessibilityIdentifier("seerr.retry")
                if !failure.isManagedByServer {
                    removeButton
                }
            }
        }

        private var removeButton: some View {
            Button("Remove Server", role: .destructive) {
                isConfirmingRemove = true
            }
            .accessibilityIdentifier("seerr.remove")
        }

        private func remove() {
            do {
                try seerr?.remove()
                problem = nil
            } catch {
                problem = String(localized: "Couldn't remove the server from this Apple TV.")
            }
        }
    }

    /// Adding a Seerr server, as Wholphin's `AddSeerServerDialog`: its address, how to sign in,
    /// and the username and password or the API key. The address can be typed without its scheme
    /// or port; the likely ones are tried. The password or API key is kept in the Keychain.
    ///
    /// Fixed while porting: it doesn't wait for the companion plugin (Wholphin's waits forever
    /// on a server without it). The plugin's address fills the address field once it's known.
    private struct SeerrAddServerPage: View {
        @Environment(SeerrModel.self) private var seerr: SeerrModel?
        @Environment(\.dismiss) private var dismiss
        @State private var address = ""
        @State private var method = SeerrAccount.Method.jellyfin
        @State private var username = ""
        @State private var secret = ""
        @State private var isConnecting = false
        @State private var problem: String?

        var body: some View {
            Form {
                Section {
                    TextField("Server address", text: $address, prompt: Text("seerr.example.com"))
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("seerr.address")
                    Picker("Sign in with", selection: $method) {
                        Text("Jellyfin account").tag(SeerrAccount.Method.jellyfin)
                        Text("Seerr account").tag(SeerrAccount.Method.local)
                        Text("API key").tag(SeerrAccount.Method.apiKey)
                    }
                    .accessibilityIdentifier("seerr.method")
                }
                Section {
                    if method != .apiKey {
                        TextField(method == .local ? "Email" : "Username", text: $username)
                            .textContentType(.username)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .accessibilityIdentifier("seerr.username")
                    }
                    SecureField(method == .apiKey ? "API key" : "Password", text: $secret)
                        .textContentType(.password)
                        .accessibilityIdentifier("seerr.secret")
                }
                Section {
                    Button(isConnecting ? "Connecting…" : "Connect") {
                        Task { await connect() }
                    }
                    .disabled(!canConnect)
                    .accessibilityIdentifier("seerr.connect")
                    if let problem {
                        Text(problem)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Add Seerr Server")
            .onAppear(perform: fillAddress)
            .onChange(of: seerr?.suggestedAddress) {
                fillAddress()
            }
        }

        private var canConnect: Bool {
            !isConnecting
                && !address.trimmingCharacters(in: .whitespaces).isEmpty
                && !secret.isEmpty
                && (method == .apiKey || !username.trimmingCharacters(in: .whitespaces).isEmpty)
        }

        /// The plugin's address, if the field is still empty, as Wholphin pre-fills it.
        private func fillAddress() {
            if address.isEmpty, let suggested = seerr?.suggestedAddress {
                address = suggested
            }
        }

        private func connect() async {
            guard let seerr else { return }
            isConnecting = true
            defer { isConnecting = false }
            do {
                try await seerr.add(
                    address: address,
                    method: method,
                    username: username.trimmingCharacters(in: .whitespaces),
                    secret: secret,
                )
                dismiss()
            } catch {
                problem = String(localized: "Couldn't add the server. \(error.seerrReason)")
            }
        }
    }
#endif
