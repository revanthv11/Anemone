import AnemoneCore
import AnemoneJellyfin
import SwiftUI

/// Saved servers, most recently used first, plus "Add server".
struct ServerListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 32) {
                Text("Servers")
                    .font(.largeTitle.bold())
                if let notice = model.notice {
                    NoticeText(notice)
                }
                if model.accounts.servers.isEmpty {
                    Text("Add your Jellyfin server to get started.")
                        .foregroundStyle(.secondary)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        NavigationLink {
                            AddServerView()
                        } label: {
                            Label("Add server", systemImage: "plus")
                        }
                        .accessibilityIdentifier("servers.add")

                        ForEach(model.accounts.serversByRecentUse) { server in
                            Button {
                                model.showUsers(on: server)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(server.name)
                                    Text("\(server.url.absoluteString) · Jellyfin \(server.version)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contextMenu {
                                Button("Remove server", role: .destructive) {
                                    model.removeServer(server)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 20)
                }
                .scrollClipDisabled()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(80)
        }
    }
}

struct AddServerView: View {
    @Environment(AppModel.self) private var model
    @State private var address = ""
    @State private var isConnecting = false
    @State private var error: ServerConnectionError?

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            Text("Add a server")
                .font(.largeTitle.bold())
            TextField("Server address", text: $address)
                .textContentType(.URL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit(connect)
                .accessibilityIdentifier("addServer.address")
            Text("For example 192.168.1.20:8096 or https://jellyfin.example.com")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button(isConnecting ? "Connecting…" : "Connect", action: connect)
                .disabled(isConnecting || address.isEmpty)
                .accessibilityIdentifier("addServer.connect")
            if let error {
                NoticeText(error.message)
            }
        }
        .frame(maxWidth: 1100, maxHeight: .infinity, alignment: .topLeading)
        .padding(80)
    }

    private func connect() {
        guard !isConnecting else { return }
        Task {
            isConnecting = true
            defer { isConnecting = false }
            do throws(ServerConnectionError) {
                try await model.addServer(address: address)
            } catch {
                self.error = error
            }
        }
    }
}

struct NoticeText: View {
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Label(text, systemImage: "exclamationmark.circle")
            .foregroundStyle(.orange)
            .accessibilityIdentifier("notice")
    }
}
