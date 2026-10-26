import AnemoneCore
import SwiftUI

/// Placeholder until the server and user setup flow lands in Phase 1.
struct RootView: View {
    var body: some View {
        VStack(spacing: 24) {
            Text("Anemone")
                .font(.largeTitle.bold())
            Text("Apple TV client for Jellyfin")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Requires Jellyfin \(ServerVersion.minimumSupported.major) or later")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
    }
}

#Preview {
    RootView()
}
