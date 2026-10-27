import AnemoneCore
import AnemoneJellyfin
import SwiftUI
import TVServices

extension View {
    /// Keeps the Top Shelf current: tvOS loads it again when the profile changes, and when the
    /// app goes to the background, since something may have been watched. Before that, the Next
    /// Up settings it follows go to the App Group, where the extension reads them.
    func topShelfSync(screen: AppModel.Screen) -> some View {
        modifier(TopShelfSync(screen: screen))
    }
}

private struct TopShelfSync: ViewModifier {
    let screen: AppModel.Screen

    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onChange(of: screen) {
                reloadTopShelf()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    reloadTopShelf()
                }
            }
    }

    private func reloadTopShelf() {
        if let defaults = SharedStorage.defaults {
            TopShelfOptions(
                enableRewatchingNextUp: Preferences.enableRewatchingNextUp.value(),
                maxDaysNextUp: Preferences.maxDaysNextUp.value(),
            )
            .write(to: defaults)
        }
        TVTopShelfContentProvider.topShelfContentDidChange()
    }
}
