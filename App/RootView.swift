import SwiftUI

/// Routes between setup, sign-in and the signed-in app.
///
/// Passing `-homeSpike <variant>` opens one of the Phase 0 home-screen prototypes instead
/// (see docs/spikes/home-focus.md).
struct RootView: View {
    @State private var model = AppModel()
    private let spike = UserDefaults.standard.string(forKey: "homeSpike")

    var body: some View {
        if let spike {
            spikeView(spike)
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
                    HomePlaceholderView(server: server, user: user)
                }
            }
            .environment(model)
            .task {
                await model.start()
            }
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
