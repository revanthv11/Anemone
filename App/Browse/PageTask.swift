import SwiftUI

/// A navigation stack's path, which the pages pushed on it watch to tell when they're back on top.
@Observable
final class PageStack {
    var path = NavigationPath()
}

extension EnvironmentValues {
    /// The navigation stack this page was pushed on. `itemPages(in:)` sets it.
    @Entry var pageStack: PageStack?
}

extension View {
    /// `task(id:)` for a page, which also runs again whenever the page comes back into view, like
    /// Wholphin's refresh on resume: after Back from a page pushed on top of it, and when the app
    /// returns to the foreground. tvOS doesn't restart a covered page's tasks after Back, so this
    /// watches the page's stack instead. Opening another page or leaving the app cancels a run
    /// still under way.
    func pageTask(id: some Equatable, _ action: @escaping @MainActor () async -> Void) -> some View {
        modifier(PageTask(id: id, action: action))
    }
}

private struct PageTask<ID: Equatable>: ViewModifier {
    let id: ID
    let action: @MainActor () async -> Void

    @Environment(\.pageStack) private var stack
    @Environment(\.scenePhase) private var scenePhase
    /// The stack's depth when the page opened, which it's back to whenever the page is on top.
    @State private var depth: Int?

    private struct Run: Equatable {
        let id: ID
        let isShowing: Bool
    }

    func body(content: Content) -> some View {
        content
            .task(id: Run(id: id, isShowing: isShowing)) {
                if depth == nil {
                    depth = stack?.path.count
                }
                guard isShowing else { return }
                await action()
            }
    }

    private var isShowing: Bool {
        let count = stack?.path.count
        return (depth ?? count) == count && scenePhase == .active
    }
}
