import AnemoneCore
import Foundation
import Observation

/// Opens `anemone://` links (`DeepLink`) through the app's own navigation, as Wholphin's
/// `handleIntent` does: item and play links open Home with the item's page on top, and search
/// links open Search with the term.
///
/// A link waits until someone is signed in. One that names a profile other than the current
/// one switches to it first when it's saved and unlocked, as Wholphin's `prepare` does; it's
/// dropped when that profile is locked or not on this Apple TV, since its item IDs belong to
/// that profile's server.
///
/// The signed-in app takes a ready link and picks the tab (`deepLinkTabs`), which hands it on to
/// Home's stack (`deepLinkPages`) or to Search (`deepLinkSearch`).
@Observable
final class DeepLinkRouter {
    /// A search to run, told apart from the same term searched before.
    struct Search: Equatable {
        let term: String
        let id = UUID()
    }

    /// The link to show, once it's ready for the signed-in profile.
    private(set) var ready: DeepLink?
    /// The item page for Home to open.
    var page: DeepLinkTarget?
    /// The search for Search to run.
    var search: Search?
    /// A link that arrived and still needs a signed-in profile.
    @ObservationIgnored private var incoming: DeepLink?

    /// Accepts a link. Returns `false` when it isn't an `anemone://` link Anemone knows.
    @discardableResult
    func open(_ url: URL) -> Bool {
        guard let link = DeepLink(url: url) else { return false }
        incoming = link
        return true
    }

    /// Makes the waiting link ready once the app is signed in to the profile it's for. Called
    /// when a link arrives and whenever the screen changes.
    func resolve(with model: AppModel) async {
        guard let link = incoming, model.screen != .loading else { return }
        guard let serverID = link.serverID, let userID = link.userID else {
            // For whoever is signed in; it waits on the server and user lists.
            if case .home = model.screen {
                incoming = nil
                ready = link
            }
            return
        }
        incoming = nil
        if case let .home(server, user) = model.screen, server.id == serverID, user.id == userID {
            ready = link
            return
        }
        guard let server = model.accounts.server(id: serverID),
              let user = model.accounts.user(id: userID, on: serverID),
              user.lock == .unlocked, user.accessToken != nil
        else { return }
        if await model.switchTo(user, on: server) == .signedIn {
            ready = link
        }
    }

    /// Hands the ready link on to the page that shows it, and says which tab that is.
    func take() -> SignedInView.Destination? {
        guard let link = ready else { return nil }
        ready = nil
        switch link.action {
        case let .item(id):
            page = DeepLinkTarget(itemID: id, start: nil)
            return .home
        case let .play(id, position):
            page = DeepLinkTarget(itemID: id, start: position.map(DeepLinkTarget.Start.position) ?? .resume)
            return .home
        case let .search(term):
            search = Search(term: term)
            return .search
        }
    }
}

/// An item page opened from a link, pushed on Home's stack.
struct DeepLinkTarget: Hashable {
    enum Start: Hashable {
        /// From where it was left off.
        case resume
        case position(Duration)
    }

    let itemID: String
    /// Where to start playing once the page is open; `nil` to just open it.
    let start: Start?
    /// Tells two openings of the same link apart, so the page opens afresh.
    let opening = UUID()
}
