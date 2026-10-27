import AnemoneJellyfin
import SwiftUI

/// A Live TV library, which gets Wholphin's guide, channels and recordings in Phase 5
/// (`CollectionFolderLiveTv`). A placeholder until then.
struct LiveTVLibraryView: View {
    let library: Library
    @Binding var path: NavigationPath

    var body: some View {
        Text("The Live TV guide arrives in Phase 5.")
            .foregroundStyle(.secondary)
            // Gives focus somewhere to rest, so pressing left opens the sidebar again.
            .focusable()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
