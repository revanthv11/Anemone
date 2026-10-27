import AnemoneJellyfin
import SwiftUI

extension View {
    /// Calls `drop` with the items deleted since the page last heard, so it can take them out of
    /// what it shows without loading again: Back from a deleted item's page finds it gone. The
    /// deletions come through the session's `cardMarks`, as watched and favourite changes do, and
    /// those made before the page first showed are already missing from what it loads.
    func onItemsDeleted(_ drop: @escaping @MainActor (Set<MediaItem.ID>) -> Void) -> some View {
        modifier(DeletedItemsWatcher(drop: drop))
    }
}

private struct DeletedItemsWatcher: ViewModifier {
    let drop: @MainActor (Set<MediaItem.ID>) -> Void

    @Environment(BrowseModel.self) private var browse
    /// How many of the session's deletions the page has heard of. A page covered by others may
    /// hear of several at once, when it next updates.
    @State private var seen: Int?

    func body(content: Content) -> some View {
        let marks = browse.cardMarks
        content
            .onChange(of: marks.deletedIDs.count, initial: true) { _, count in
                if let seen, count > seen {
                    drop(marks.deletions(since: seen))
                }
                seen = count
            }
    }
}
