import AnemoneCore
import AnemoneJellyfin
import AnemonePlayback
import SwiftUI

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
                if let tab = router?.take() {
                    selection = tab
                }
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
