import AnemoneCore
import AnemoneJellyfin
import AnemonePlayback
import SwiftUI
import UIKit

extension View {
    /// Opens the tab for a link that's ready (`DeepLinkRouter`). For the signed-in app's tabs.
    func deepLinkTabs(selection: Binding<SignedInView.Destination>) -> some View {
        modifier(DeepLinkTabs(selection: selection))
    }

    /// Opens item pages from links on `stack`, replacing what was there, so Back goes to the
    /// stack's root. For Home.
    func deepLinkPages(in stack: PageStack) -> some View {
        modifier(DeepLinkPages(stack: stack))
    }

    /// Runs searches from links through `search`, back on the stack's root. For Search.
    func deepLinkSearch(_ search: @escaping (String) -> Void) -> some View {
        modifier(DeepLinkSearch(search: search))
    }
}

private struct DeepLinkTabs: ViewModifier {
    @Binding var selection: SignedInView.Destination

    @Environment(DeepLinkRouter.self) private var router: DeepLinkRouter?

    func body(content: Content) -> some View {
        content
            .onChange(of: router?.ready, initial: true) {
                guard router?.ready != nil else { return }
                Task {
                    // Wholphin clears its back stack for a link, so a player closes, as does
                    // anything else shown over the app, rather than the link opening unseen
                    // under it, or failing to show its own player.
                    await PresentedScreens.close()
                    if let tab = router?.take() {
                        selection = tab
                    }
                }
            }
    }
}

/// What's shown over the app: players, Now Playing, sheets.
private enum PresentedScreens {
    /// Closes everything shown over the app, and returns once it has gone and SwiftUI has heard,
    /// so a player has started ending its play session.
    static func close() async {
        // Each pass closes what's shown, or waits for what's coming or going.
        for _ in 0 ..< 30 {
            guard let root = keyWindow?.rootViewController, let shown = root.presentedViewController else { return }
            if shown.isBeingPresented || shown.isBeingDismissed {
                try? await Task.sleep(for: .milliseconds(100))
            } else {
                await dismiss(from: root)
            }
        }
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }

    /// Dismisses everything `root` presents. UIKit calls back once it's gone; that's waited
    /// for at most 2 s, in case it never does.
    private static func dismiss(from root: UIViewController) async {
        await withCheckedContinuation { continuation in
            let resume = Once { continuation.resume() }
            root.dismiss(animated: true) {
                resume()
            }
            Task {
                try? await Task.sleep(for: .seconds(2))
                resume()
            }
        }
        // Lets SwiftUI run the cover's `onDismiss`, which ends a player's session, before the
        // link replaces the pages under it.
        try? await Task.sleep(for: .milliseconds(100))
    }

    /// Runs its action the first time it's called.
    private final class Once {
        private var action: (() -> Void)?

        init(_ action: @escaping () -> Void) {
            self.action = action
        }

        func callAsFunction() {
            let action = action
            self.action = nil
            action?()
        }
    }
}

private struct DeepLinkPages: ViewModifier {
    let stack: PageStack

    @Environment(DeepLinkRouter.self) private var router: DeepLinkRouter?

    func body(content: Content) -> some View {
        content
            .navigationDestination(for: DeepLinkTarget.self) { target in
                DeepLinkPage(target: target)
                    // A link that replaces another's page gets a page of its own, rather than
                    // SwiftUI keeping the one in the same place on the stack, with its item.
                    .id(target)
                    .environment(\.pageStack, stack)
            }
            .onChange(of: router?.page, initial: true) {
                guard let router, let target = router.page else { return }
                router.page = nil
                stack.path = NavigationPath([target])
            }
    }
}

private struct DeepLinkSearch: ViewModifier {
    let search: (String) -> Void

    @Environment(DeepLinkRouter.self) private var router: DeepLinkRouter?
    @Environment(\.pageStack) private var stack

    func body(content: Content) -> some View {
        content
            .onChange(of: router?.search, initial: true) {
                guard let router, let request = router.search else { return }
                router.search = nil
                stack?.path = NavigationPath()
                search(request.term)
            }
    }
}

/// An item's page opened from a link: loads the item, then shows its page, as a card would open
/// it. A play link then plays it, as Wholphin's play intent opens the item's page with the
/// player over it, so Back from the player lands on the page.
private struct DeepLinkPage: View {
    let target: DeepLinkTarget

    @Environment(BrowseModel.self) private var browse
    @State private var item: MediaItem?
    @State private var problem: String?
    @State private var playback: PlaybackRequest?
    /// Counts finished playbacks, so the page loads again and shows the new resume position.
    @State private var plays = 0

    var body: some View {
        Group {
            if let item {
                ItemDetailView(item: item)
                    .id(plays)
            } else if let problem {
                PageMessage(message: problem)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            await open()
        }
        .player($playback) {
            plays += 1
        }
    }

    private func open() async {
        guard item == nil, problem == nil else { return }
        let session = browse.session
        let id = target.itemID
        do {
            guard let start = target.start else {
                item = try await session.item(id: id)
                return
            }
            let details = try await session.itemDetails(id: id)
            item = details.item
            // Music has its own player later (Phase 5b); its page says so on Play.
            guard details.isPlayable, details.item.kind != .audio else { return }
            let from: Duration? = switch start {
            case .resume: details.userState.resumePosition
            case let .position(position): position
            }
            playback = browse.playback(of: details, from: from)
        } catch {
            problem = browse.problem(with: error, doing: "open this item on \(browse.server.name)")
        }
    }
}
