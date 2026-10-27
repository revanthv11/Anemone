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
                // The stack's root, which `itemPages(in:)` doesn't reach. Card menus open the
                // series' or season's page on it.
                .libraryRootStack(stack, for: library)
                .itemPages(in: stack)
        }
    }
}

extension EnvironmentValues {
    /// The navigation stack of the library a page is on, which library pages pass on to their
    /// cards' menus as `pageStack`. Unlike `pageStack`, it's there on Live TV's page too.
    @Entry var libraryPageStack: PageStack?
}

extension View {
    /// Puts a library's navigation stack in the environment of its first page, from the sidebar
    /// or More. Live TV's page doesn't get it as `pageStack`: its `pageTask` reloads the guide
    /// whenever it runs, which with the stack would also be after Back from every recording
    /// opened over it. Its recordings folders still get it, through `libraryPageStack`.
    func libraryRootStack(_ stack: PageStack, for library: Library) -> some View {
        environment(\.pageStack, library.kind == .liveTV ? nil : stack)
            .environment(\.libraryPageStack, stack)
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
        // Jellyfin's "Home Videos and Photos" libraries too, as in Wholphin.
        case .photos, .homeVideos:
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
///
/// Each tab is kept once opened, while the page is, as Wholphin keeps a view model per tab: going
/// back to one finds it as it was left, without loading it again, scrolled and with focus where
/// it was.
struct LibraryScreen: View {
    let library: Library
    @Binding var path: NavigationPath

    @Environment(BrowseModel.self) private var browse
    @Environment(\.pageStack) private var pageStack
    @Environment(\.libraryPageStack) private var libraryPageStack
    @AppStorage(Preferences.rememberSelectedTab) private var remembersTab: Bool
    @State private var section: LibrarySection?
    /// The tabs opened so far, in the order they were opened.
    @State private var openedSections: [LibrarySection] = []
    /// Wholphin tucks the tabs away while focus is past the first row, giving the grid the room.
    @State private var tabsHidden = false
    /// The tab with focus, so a page can send focus up to the tabs.
    @FocusState private var focusedTab: LibrarySection?
    /// Where tvOS put the top of the page on screen; see `tabRowPadding`.
    @State private var pageTop: CGFloat?

    var body: some View {
        let sections = library.sections
        let current = section ?? startingSection
        VStack(alignment: .leading, spacing: 0) {
            if sections.count > 1, !tabsHidden {
                LibraryTabRow(sections: sections, selection: selection(current), focus: $focusedTab)
                    .padding(.horizontal, GridLayout.horizontalInset)
                    .padding(.top, tabRowPadding)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            ZStack(alignment: .topLeading) {
                ForEach(shownSections(current: current), id: \.self) { opened in
                    let isShowing = opened == current
                    // The others stay, hidden, and out of reach of focus and VoiceOver.
                    tab(opened)
                        .opacity(isShowing ? 1 : 0)
                        .disabled(!isShowing)
                        .accessibilityHidden(!isShowing)
                        .zIndex(isShowing ? 1 : 0)
                }
            }
        }
        // Each tab fills the page under the tabs, whatever its content's own size.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // For the cards' menus, here and in Live TV's recordings folders, whose page leaves it out.
        .environment(\.pageStack, stack)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { pageTop = $0 }
        .animation(.easeInOut(duration: 0.2), value: tabsHidden)
        .navigationDestination(for: LibraryCategoryPage.self) { page in
            LibraryItemsPage(library: page.library, scope: page.scope, title: page.title, path: $path)
                // tvOS doesn't pass the stack's environment on to the pages pushed on it.
                .environment(\.pageStack, stack)
        }
        .onAppear {
            if section == nil {
                section = startingSection
            }
            if let section, !openedSections.contains(section) {
                openedSections.append(section)
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
        // Up from the top of the alphabet bar finds nothing above it on its own: tvOS goes to the
        // sidebar's title instead, or nowhere while the tabs are tucked away.
        let onExitTop: (() -> Void)? = library.sections.count > 1 ? { focusTabs(on: section) } : nil
        switch section {
        case .recommended:
            LibraryRecommendedTab(library: library, path: $path, onPastFirstRow: onPastFirstRow)
        case .library:
            LibraryItemsPage(library: library, path: $path, onPastFirstRow: onPastFirstRow, onExitTop: onExitTop)
        case .collections:
            LibraryItemsPage(
                library: library,
                scope: .collections,
                title: "Collections",
                path: $path,
                onPastFirstRow: onPastFirstRow,
                onExitTop: onExitTop,
            )
        case .genres:
            LibraryCategoryTab(
                library: library,
                kind: .genres,
                path: $path,
                onPastFirstRow: onPastFirstRow,
                onExitTop: onExitTop,
            )
        case .studios:
            LibraryCategoryTab(
                library: library,
                kind: .studios,
                path: $path,
                onPastFirstRow: onPastFirstRow,
                onExitTop: onExitTop,
            )
        }
    }

    /// Brings the tabs back and moves focus to the one showing.
    private func focusTabs(on section: LibrarySection) {
        tabsHidden = false
        // The row may only now be coming back; focus it once it's there.
        Task { @MainActor in
            focusedTab = section
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

    /// The library's navigation stack.
    private var stack: PageStack? {
        pageStack ?? libraryPageStack
    }

    /// The tabs to keep: those opened so far, and the one showing.
    private func shownSections(current: LibrarySection) -> [LibrarySection] {
        openedSections.contains(current) ? openedSections : openedSections + [current]
    }

    private var startingSection: LibrarySection {
        library.startingSection(
            remembered: remembersTab ? browse.libraryPreferences.rememberedSection(for: library) : nil,
        )
    }

    /// Choosing a tab shows it as it was left, and remembers it when that's switched on, as
    /// Wholphin's `TabViewModel` does.
    private func selection(_ current: LibrarySection) -> Binding<LibrarySection> {
        Binding { current } set: { chosen in
            guard chosen != current else { return }
            section = chosen
            if !openedSections.contains(chosen) {
                openedSections.append(chosen)
            }
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
