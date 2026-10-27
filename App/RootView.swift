import AnemoneUI
import SwiftUI

/// Routes between setup, sign-in and the signed-in app. It also opens `anemone://` links, keeps
/// the Top Shelf current and runs the in-app screensaver.
///
/// Passing `-homeSpike <variant>` opens one of the Phase 0 home-screen prototypes instead, and
/// `-libraryGridSpike <count>` the Phase 2b grid on a synthetic library (see
/// docs/spikes/home-focus.md).
struct RootView: View {
    @State private var model = AppModel()
    @State private var deepLinks = DeepLinkRouter()
    @State private var screensaver = Screensaver()
    private let spike = UserDefaults.standard.string(forKey: "homeSpike")
    private let gridSpikeCount = UserDefaults.standard.integer(forKey: "libraryGridSpike")

    var body: some View {
        if let spike {
            spikeView(spike)
        } else if gridSpikeCount > 0 {
            LibraryGridSpike(count: gridSpikeCount)
        } else {
            Group {
                switch model.screen {
                case .loading:
                    ProgressView()
                case .servers:
                    ServerListView()
                case let .users(server):
                    UserListView(server: server)
                        .id(server.id)
                case let .home(server, user):
                    if let session = model.session {
                        // Keyed by profile, so changing its lock keeps the loaded home page.
                        SignedInView(server: server, user: user, session: session)
                            .id("\(server.id)/\(user.id)")
                    }
                }
            }
            .environment(model)
            .environment(deepLinks)
            .environment(screensaver)
            .themeBackground()
            .task {
                await model.start()
            }
            // anemone:// links from the Top Shelf and elsewhere (App/DeepLinks).
            .onOpenURL { url in
                guard deepLinks.open(url) else { return }
                screensaver.stop()
                Task { await deepLinks.resolve(with: model) }
            }
            .onChange(of: model.screen) {
                Task { await deepLinks.resolve(with: model) }
            }
            .topShelfSync(screen: model.screen)
            .screensaver(screensaver, session: model.session)
            .appTheme()
        }
    }

    @ViewBuilder
    private func spikeView(_ variant: String) -> some View {
        switch variant {
        case "swiftui-scroll":
            SwiftUIHomeSpike(strategy: .rememberScroll)
        case "swiftui-naive":
            SwiftUIHomeSpike(strategy: .naive)
        case "uikit":
            UIKitHomeSpike()
                .ignoresSafeArea()
        default:
            SwiftUIHomeSpike(strategy: .eagerRows)
        }
    }
}
