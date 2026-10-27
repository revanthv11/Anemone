import AnemoneJellyfin
import AnemonePlayback
import SwiftUI

extension View {
    /// Plays the item's theme music while its page shows, as Wholphin's movie, series, season,
    /// episode and collection pages do; `ThemeMusic` has the details. Settings › Interface sets
    /// the volume or turns it off.
    func themeMusic(for details: ItemDetails?) -> some View {
        modifier(ThemeMusicModifier(itemID: details?.themeMusicItemID))
    }
}

/// Tells `ThemeMusic` when the page shows and when it stops: Back, another page pushed on top,
/// or the app leaving the foreground. Like `pageTask`, it watches the page's stack, since tvOS
/// doesn't tell a covered page when it's back on top.
private struct ThemeMusicModifier: ViewModifier {
    let itemID: MediaItem.ID?

    @Environment(BrowseModel.self) private var browse
    @Environment(\.pageStack) private var stack
    @Environment(\.scenePhase) private var scenePhase
    @State private var page = UUID()
    /// The stack's depth when the page opened, which it's back to whenever the page is on top.
    @State private var depth: Int?

    private struct Wanted: Equatable {
        let itemID: MediaItem.ID?
        let isShowing: Bool
    }

    func body(content: Content) -> some View {
        content
            .task(id: Wanted(itemID: itemID, isShowing: isShowing)) {
                if depth == nil {
                    depth = stack?.path.count
                }
                update()
            }
            .onDisappear {
                ThemeMusic.shared.hide(page)
            }
    }

    private var isShowing: Bool {
        let count = stack?.path.count
        return (depth ?? count) == count && scenePhase == .active
    }

    private func update() {
        guard isShowing, let itemID else {
            ThemeMusic.shared.hide(page)
            return
        }
        let session = browse.session
        ThemeMusic.shared.show(itemID, for: page) { id in
            try await session.randomThemeSongURL(of: id)
        }
    }
}

extension ItemDetails {
    /// Whose theme music the page plays, as Wholphin's pages pick it: a movie's, video's,
    /// series' or collection's own, and a season's or episode's series'. Other pages have none.
    var themeMusicItemID: MediaItem.ID? {
        switch item.kind {
        case .movie, .video, .musicVideo, .series, .collection:
            id
        case .season, .episode:
            item.episode?.seriesID
        default:
            nil
        }
    }
}
