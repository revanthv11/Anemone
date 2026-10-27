import AnemoneCore
import AnemoneJellyfin
import OSLog
import TVServices
import UIKit

private let log = Logger(subsystem: "com.revanthv11.anemone.topshelf", category: "TopShelf")

/// Supplies the Top Shelf shown above Anemone when it's in the top row of the Apple TV home
/// screen: Continue Watching and Next Up for the profile the app opens on, as Wholphin fills
/// Android TV's Watch Next row. Selecting an item opens its page; Play plays it from where it
/// was left off (`anemone://` links, handled in `App/DeepLinks`).
///
/// It reads the sign-ins the app shares through a Keychain access group (`SharedStorage`) and
/// changes nothing on the server. It shows nothing when nobody is signed in, the profile is
/// locked, or the server can't be reached; the app asks tvOS to load it again when that changes.
final class ContentProvider: TVTopShelfContentProvider {
    /// The completion-handler form: the content isn't `Sendable`, so the async override can't
    /// return it under strict concurrency. The task only carries `Sendable` rows; the content is
    /// built from them where the handler is called.
    override func loadTopShelfContent(completionHandler: @escaping ((any TVTopShelfContent)?) -> Void) {
        let reply = Reply(completionHandler)
        Task {
            let rows = await Self.loadRows()
            reply.send(rows)
        }
    }

    /// The rows for the profile the app opens on, or `nil` when there's nothing to show.
    private static func loadRows() async -> LoadedRows? {
        guard let profile = await SignedInProfile.current() else { return nil }
        do {
            let rows = try await profile.session.topShelfRows(options: profile.options)
            return rows.isEmpty ? nil : LoadedRows(profile: profile, rows: rows)
        } catch {
            log.error("Couldn't load the rows: \(error, privacy: .public)")
            return nil
        }
    }
}

/// What the Top Shelf shows, before it's turned into TVServices' types.
private struct LoadedRows: Sendable {
    let profile: SignedInProfile
    let rows: [TopShelfRow]

    var content: any TVTopShelfContent {
        TVTopShelfSectionedContent(sections: rows.map(section))
    }

    private func section(for row: TopShelfRow) -> TVTopShelfItemCollection<TVTopShelfSectionedItem> {
        let collection = TVTopShelfItemCollection(items: row.items.map(item))
        collection.title = row.title
        return collection
    }

    private func item(for media: MediaItem) -> TVTopShelfSectionedItem {
        let shelfItem = TVTopShelfSectionedItem(identifier: media.id)
        shelfItem.title = media.topShelfTitle
        // 16:9 art, as Wholphin's Watch Next row uses.
        shelfItem.imageShape = .hdtv
        if let image = media.thumbImage {
            shelfItem.setImageURL(profile.session.imageURL(for: image, maxWidth: 640), for: .screenScale1x)
            shelfItem.setImageURL(profile.session.imageURL(for: image, maxWidth: 1280), for: .screenScale2x)
        }
        shelfItem.playbackProgress = media.progress ?? 0
        shelfItem.displayAction = TVTopShelfAction(url: profile.link(.item(id: media.id)))
        shelfItem.playAction = TVTopShelfAction(url: profile.link(.play(id: media.id, position: nil)))
        return shelfItem
    }
}

/// The system's completion handler, which may be called from any thread once, carried into the
/// task that loads the rows.
private final class Reply: @unchecked Sendable {
    private let handler: ((any TVTopShelfContent)?) -> Void

    init(_ handler: @escaping ((any TVTopShelfContent)?) -> Void) {
        self.handler = handler
    }

    func send(_ rows: LoadedRows?) {
        handler(rows?.content)
    }
}

/// The profile the app restores on launch, with a connection to its server.
private struct SignedInProfile: Sendable {
    let serverID: String
    let userID: String
    let session: JellyfinSession
    let options: TopShelfOptions

    /// `nil` unless the app's last profile is still signed in and not locked: the app wouldn't
    /// open on a locked profile, so neither does the Top Shelf show its rows.
    static func current() async -> SignedInProfile? {
        guard let store = SharedStorage.extensionKeychain() else {
            log.error("The build has no shared Keychain access group")
            return nil
        }
        guard let accounts = AccountRepository(store: store).loadReadOnly() else {
            log.info("No sign-ins shared by the app")
            return nil
        }
        guard let last = accounts.lastSession,
              let server = accounts.server(id: last.serverID),
              let user = accounts.user(id: last.userID, on: server.id),
              user.lock == .unlocked,
              let token = user.accessToken
        else {
            log.info("Nobody the app would open on is signed in")
            return nil
        }
        // The app's own identity, so the server sees one device.
        let deviceName = await MainActor.run { UIDevice.current.name }
        let identity = ClientIdentity(
            deviceName: deviceName,
            deviceID: accounts.deviceID,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
        )
        return SignedInProfile(
            serverID: server.id,
            userID: user.id,
            session: JellyfinSession(serverURL: server.url, userID: user.id, accessToken: token, identity: identity),
            options: SharedStorage.defaults.map(TopShelfOptions.init(defaults:)) ?? TopShelfOptions(),
        )
    }

    /// A link that opens on this profile, even if the app has switched to another since.
    func link(_ action: DeepLink.Action) -> URL {
        DeepLink(action, serverID: serverID, userID: userID).url
    }
}

private extension MediaItem {
    /// The series and episode for episodes ("Pioneer One · S1:E3"), otherwise the name.
    var topShelfTitle: String {
        [displayTitle, episodeLabel].compactMap(\.self).joined(separator: " · ")
    }
}
