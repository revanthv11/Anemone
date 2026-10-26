import AnemoneCore
import SwiftUI

/// Placeholder until the server and user setup flow lands in Phase 1.
///
/// On the home-focus spike branch it also launches the two prototypes: pick one on screen, or
/// pass `-homeSpike swiftui` / `-homeSpike uikit` as a launch argument.
struct RootView: View {
    @State private var spike = UserDefaults.standard.string(forKey: "homeSpike")

    var body: some View {
        switch spike {
        case "swiftui":
            SwiftUIHomeSpike(strategy: .eagerRows)
        case "swiftui-scroll":
            SwiftUIHomeSpike(strategy: .rememberScroll)
        case "swiftui-naive":
            SwiftUIHomeSpike(strategy: .naive)
        case "uikit":
            UIKitHomeSpike()
                .ignoresSafeArea()
        default:
            placeholder
        }
    }

    private var placeholder: some View {
        VStack(spacing: 24) {
            Text("Anemone")
                .font(.largeTitle.bold())
            Text("Apple TV client for Jellyfin")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Requires Jellyfin \(ServerVersion.minimumSupported.major) or later")
                .font(.callout)
                .foregroundStyle(.tertiary)
            HStack(spacing: 40) {
                Button("SwiftUI rows") { spike = "swiftui" }
                Button("UIKit rows") { spike = "uikit" }
            }
            .padding(.top, 40)
        }
    }
}

#Preview {
    RootView()
}
