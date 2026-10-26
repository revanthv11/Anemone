import AnemoneUI
import SwiftUI

@main
struct AnemoneApp: App {
    init() {
        ArtworkImage.configureCache()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
