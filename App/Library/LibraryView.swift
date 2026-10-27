import AnemoneCore
import AnemoneJellyfin
import AnemoneUI
import SwiftUI

/// A library pinned to the sidebar, with its own navigation.
struct LibraryTab: View {
    let library: Library

    @State private var stack = PageStack()

    var body: some View {
        NavigationStack(path: $stack.path) {
            LibraryRoot(library: library, path: $stack.path)
                .itemPages(in: stack)
        }
    }
}

/// A library's first page, from the sidebar or More. Live TV, music and photo libraries get pages
/// of their own, each in its own folder; the rest share the grid.
struct LibraryRoot: View {
    let library: Library
    @Binding var path: NavigationPath

    var body: some View {
        switch library.kind {
        case .liveTV:
            LiveTVLibraryView(library: library, path: $path)
        case .music:
            MusicLibraryView(library: library, path: $path)
        case .photos:
            PhotoLibraryView(library: library, path: $path)
        default:
            LibraryScreen(library: library, path: $path)
        }
    }
}

/// Wholphin's library page: movie and TV libraries get its tabs (Recommended, Library,
/// Collections or Studios, Genres) along the top, as `CollectionFolderMovie` and
/// `CollectionFolderTv` lay them out; other libraries show their grid alone. With "Remember
/// selected tab" on, each library opens on the tab last chosen there.
struct LibraryScreen: View {
    let library: Library
    @Binding var path: NavigationPath

    @Environment(BrowseModel.self) private var browse
    @AppStorage(Preferences.rememberSelectedTab) private var remembersTab: Bool
    @State private var section: LibrarySection?
    /// Wholphin tucks the tabs away while focus is past the first row, giving the grid the room.
    @State private var tabsHidden = false
    /// Where tvOS put the top of the page on screen; see `tabRowPadding`.
    @State private var pageTop: CGFloat?

    var body: some View {
        let sections = library.sections
        let current = section ?? startingSection
        VStack(alignment: .leading, spacing: 0) {
            if sections.count > 1, !tabsHidden {
                LibraryTabRow(sections: sections, selection: selection(current))
                    .padding(.horizontal, GridLayout.horizontalInset)
                    .padding(.top, tabRowPadding)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            tab(current)
                .id(current)
        }
        // Each tab fills the page under the tabs, whatever its content's own size.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { pageTop = $0 }
        .animation(.easeInOut(duration: 0.2), value: tabsHidden)
        .navigationDestination(for: LibraryCategoryPage.self) { page in
            LibraryItemsPage(library: page.library, scope: page.scope, title: page.title, path: $path)
        }
        .onAppear {
            if section == nil {
                section = startingSection
            }
        }
    }

    @ViewBuilder
    private func tab(_ section: LibrarySection) -> some View {
        let onPastFirstRow = { (isPastFirstRow: Bool) in
            if tabsHidden != isPastFirstRow {
                tabsHidden = isPastFirstRow
            }
        }
        switch section {
        case .recommended:
            LibraryRecommendedTab(library: library, path: $path, onPastFirstRow: onPastFirstRow)
        case .library:
            LibraryItemsPage(library: library, path: $path, onPastFirstRow: onPastFirstRow)
        case .collections:
            LibraryItemsPage(
                library: library,
                scope: .collections,
                title: "Collections",
                path: $path,
                onPastFirstRow: onPastFirstRow,
            )
        case .genres:
            LibraryCategoryTab(library: library, kind: .genres, path: $path, onPastFirstRow: onPastFirstRow)
        case .studios:
            LibraryCategoryTab(library: library, kind: .studios, path: $path, onPastFirstRow: onPastFirstRow)
        }
    }

    /// tvOS puts a page lower, below the sidebar's title, when it doesn't take the page's top for
    /// a scroll view, and higher when it does, and that differs from tab to tab here (the grids
    /// are higher than Recommended). Padding the tabs down to the lower place keeps them from
    /// jumping as the user moves between tabs.
    private var tabRowPadding: CGFloat {
        let top = pageTop ?? LibraryTabLayout.lowerPageTop
        return LibraryTabLayout.topPadding + max(LibraryTabLayout.lowerPageTop - top, 0)
    }

    private var startingSection: LibrarySection {
        library.startingSection(
            remembered: remembersTab ? browse.libraryPreferences.rememberedSection(for: library) : nil,
        )
    }

    /// Choosing a tab shows it from the top, and remembers it when that's switched on, as
    /// Wholphin's `TabViewModel` does.
    private func selection(_ current: LibrarySection) -> Binding<LibrarySection> {
        Binding { current } set: { chosen in
            guard chosen != current else { return }
            section = chosen
            tabsHidden = false
            if remembersTab {
                browse.libraryPreferences.rememberSection(chosen, for: library)
            }
        }
    }
}

private enum LibraryTabLayout {
    static let topPadding: CGFloat = 20
    /// Where tvOS 26 puts the top of a page below the sidebar's title.
    static let lowerPageTop: CGFloat = 120
}
