import AnemoneCore
import AnemoneJellyfin
import SwiftUI

/// "Who's watching?": profiles saved on this Apple TV, then the server's other public users.
struct UserListView: View {
    let server: SavedServer

    @Environment(AppModel.self) private var model
    @State private var publicUsers: [PublicUser] = []
    @State private var path: [SignInRoute] = []
    @State private var userEnteringPIN: SavedUser?

    var body: some View {
        NavigationStack(path: $path) {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Who's watching?")
                        .font(.largeTitle.bold())
                    Text("\(server.name) · Jellyfin \(server.version)")
                        .foregroundStyle(.secondary)
                }
                if let notice = model.notice {
                    NoticeText(notice)
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 48) {
                        ForEach(savedUsers) { user in
                            Button {
                                select(user)
                            } label: {
                                ProfileTile(name: user.name, imageURL: imageURL(user.id, tag: user.primaryImageTag))
                                    .overlay(alignment: .topTrailing) {
                                        if user.lock != .unlocked {
                                            Image(systemName: "lock.fill")
                                                .padding(12)
                                        }
                                    }
                            }
                            .contextMenu {
                                Button("Remove from this Apple TV", role: .destructive) {
                                    Task { await model.forget(user, on: server) }
                                }
                            }
                            .accessibilityIdentifier("user.\(user.name)")
                        }
                        ForEach(otherPublicUsers) { user in
                            NavigationLink(value: SignInRoute(username: user.name)) {
                                ProfileTile(name: user.name, imageURL: imageURL(user.id, tag: user.primaryImageTag))
                            }
                            .accessibilityIdentifier("user.\(user.name)")
                        }
                        NavigationLink(value: SignInRoute(username: nil)) {
                            ProfileTile(name: "Other user", systemImage: "person.badge.plus")
                        }
                        .accessibilityIdentifier("user.other")
                    }
                    .buttonStyle(.card)
                    .padding(.vertical, 40)
                }
                .scrollClipDisabled()
                Button("Change server") {
                    model.showServers()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(80)
            .navigationDestination(for: SignInRoute.self) { route in
                SignInView(server: server, username: route.username)
            }
            .sheet(item: $userEnteringPIN) { user in
                PINEntryView(title: "Enter the PIN for \(user.name)") { pin in
                    switch await model.unlock(user, on: server, pin: pin) {
                    case .none:
                        return false
                    case .needsSignIn:
                        path.append(SignInRoute(username: user.name))
                        return true
                    case .signedIn, .needsPIN, .unreachable:
                        return true
                    }
                }
            }
        }
        .task {
            publicUsers = await (try? model.authenticator.publicUsers(on: server.url)) ?? []
        }
    }

    private var savedUsers: [SavedUser] {
        model.accounts.users(on: server.id)
    }

    private var otherPublicUsers: [PublicUser] {
        let saved = Set(savedUsers.map(\.id))
        return publicUsers.filter { !saved.contains($0.id) }
    }

    private func select(_ user: SavedUser) {
        Task {
            switch await model.switchTo(user, on: server) {
            case .needsPIN:
                userEnteringPIN = user
            case .needsSignIn:
                path.append(SignInRoute(username: user.name))
            case .signedIn, .unreachable:
                break
            }
        }
    }

    private func imageURL(_ userID: String, tag: String?) -> URL? {
        guard let tag else { return nil }
        return server.url
            .appending(path: "Users/\(userID)/Images/Primary")
            .appending(queryItems: [.init(name: "tag", value: tag), .init(name: "maxHeight", value: "300")])
    }
}

struct SignInRoute: Hashable {
    /// Pre-filled and fixed when the profile was picked from the list.
    let username: String?
}

private struct ProfileTile: View {
    let name: String
    var imageURL: URL?
    var systemImage = "person.fill"

    var body: some View {
        VStack(spacing: 16) {
            AsyncImage(url: imageURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: systemImage)
                    .font(.system(size: 72))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 200, height: 200)
            .clipShape(.rect(cornerRadius: 16))
            Text(name)
                .lineLimit(1)
        }
        .frame(width: 240)
        .padding(.vertical, 20)
    }
}
