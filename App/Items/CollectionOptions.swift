import AnemoneJellyfin
import AnemoneUI
import SwiftUI

/// A collection page's sort, filter and view options, Wholphin's `CollectionState` sort and
/// filter with its `CollectionViewOptions`. Kept per collection, like a library's.
struct CollectionDisplay: Codable, Hashable {
    /// Wholphin's default: the collection's own order.
    var sort = LibrarySort(.default)
    var filter = LibraryFilter()
    /// Wholphin's "Separate types": a row for each type of item, or every item in one grid.
    var separateTypes = true
    /// Wholphin's "Show details" for collections (`CollectionViewOptions.cardViewOptions`): while
    /// a card has focus, the header describes that card rather than the collection. On, as in
    /// Wholphin.
    var showsDetails = true
    /// The grid's options when types aren't separated; `nil` until changed, for the defaults.
    var grid: GridViewOptions?

    /// What the page asks the server for. Changing the view doesn't need a new request.
    var query: Query {
        Query(sort: sort, filter: filter)
    }

    /// Setting them keeps them for the collection, even when they're the defaults.
    var gridOptions: GridViewOptions {
        get { grid ?? .defaults(for: .collections) }
        set { grid = newValue }
    }

    struct Query: Hashable {
        let sort: LibrarySort
        let filter: LibraryFilter
    }
}

extension CollectionDisplay {
    /// Field by field, so one part that no longer decodes doesn't throw away the others.
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        sort = (try? values.decodeIfPresent(LibrarySort.self, forKey: .sort)) ?? LibrarySort(.default)
        filter = (try? values.decodeIfPresent(LibraryFilter.self, forKey: .filter)) ?? LibraryFilter()
        separateTypes = (try? values.decodeIfPresent(Bool.self, forKey: .separateTypes)) ?? true
        showsDetails = (try? values.decodeIfPresent(Bool.self, forKey: .showsDetails)) ?? true
        grid = try? values.decodeIfPresent(GridViewOptions.self, forKey: .grid)
    }
}

extension View {
    /// Reads a collection's display options when its page opens, and saves them when the user
    /// changes them. Kept in UserDefaults per profile, as library options are.
    func collectionDisplay(_ display: Binding<CollectionDisplay?>, for collectionID: MediaItem.ID) -> some View {
        modifier(CollectionDisplayStorage(display: display, collectionID: collectionID))
    }
}

private struct CollectionDisplayStorage: ViewModifier {
    @Binding var display: CollectionDisplay?
    let collectionID: MediaItem.ID

    @Environment(BrowseModel.self) private var browse
    /// What storage holds for the collection, or the defaults shown when it holds nothing. Only a
    /// change from this is the user's, so reading the options doesn't write them back.
    @State private var stored: CollectionDisplay?

    func body(content: Content) -> some View {
        content
            .task(id: collectionID) {
                let data = UserDefaults.standard.data(forKey: key)
                let read = data.flatMap { try? JSONDecoder().decode(CollectionDisplay.self, from: $0) }
                    ?? CollectionDisplay()
                stored = read
                display = read
            }
            .onChange(of: display) { _, display in
                guard let display, let stored, display != stored else { return }
                UserDefaults.standard.set(try? JSONEncoder().encode(display), forKey: key)
                self.stored = display
            }
    }

    private var key: String {
        "collections.\(browse.server.id).\(browse.session.userID).display.\(collectionID)"
    }
}

/// Wholphin's sort, filter and view buttons, at the end of the collection page's actions. The
/// filter list and grid options are the library page's.
struct CollectionOptionsButtons: View {
    let collection: ItemDetails
    @Binding var display: CollectionDisplay?
    let focus: FocusState<ItemFocus?>.Binding

    @State private var showsFilters = false
    @State private var showsGridOptions = false
    @State private var filterChoices = FilterChoiceCache()

    var body: some View {
        HStack(spacing: 24) {
            if let display = Binding($display) {
                sortMenu(display)
                let active = display.wrappedValue.filter.activeCount
                ActionButton(
                    title: active > 0 ? String(localized: "Filter (\(active))") : String(localized: "Filter"),
                    systemImage: "line.3.horizontal.decrease.circle",
                    spokenTitle: active > 0 ? Text("Filter, \(active) active") : nil,
                ) {
                    showsFilters = true
                }
                .focused(focus, equals: .action(.filter))
                .accessibilityIdentifier("collection.filter")
                viewMenu(display)
                    .sheet(isPresented: $showsFilters) {
                        FilterSheet(library: library, filter: display.filter, cache: filterChoices)
                    }
                    .sheet(isPresented: $showsGridOptions) {
                        ViewOptionsSheet(options: display.gridOptions, defaults: .defaults(for: .collections))
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    /// The collection as the library page's filter list sees it: its own genres, ratings and years.
    private var library: Library {
        Library(id: collection.id, name: collection.item.name, kind: .collections)
    }

    /// Wholphin's sort button: the collection's own order, then its `MovieSortOptions`; picking
    /// the current one again reverses it.
    private func sortMenu(_ display: Binding<CollectionDisplay>) -> some View {
        let sort = display.wrappedValue.sort
        return Menu {
            ForEach([.default] + library.sortFields, id: \.self) { field in
                Button {
                    display.wrappedValue.sort = sort.choosing(field)
                } label: {
                    if field == sort.field {
                        Label(field.title, systemImage: sort.direction.systemImage)
                    } else {
                        Text(field.title)
                    }
                }
            }
        } label: {
            Label(sort.field.title, systemImage: sort.direction.systemImage)
        }
        .focused(focus, equals: .action(.sort))
        .accessibilityLabel("Sort by \(sort.field.title), \(sort.direction == .ascending ? "ascending" : "descending")")
        .accessibilityIdentifier("collection.sort")
    }

    private func viewMenu(_ display: Binding<CollectionDisplay>) -> some View {
        Menu {
            Toggle("Separate types", isOn: display.separateTypes)
            Toggle("Show details", isOn: display.showsDetails)
            if !display.wrappedValue.separateTypes {
                Button("Grid options", systemImage: "square.grid.3x3") {
                    showsGridOptions = true
                }
            }
        } label: {
            Label("View", systemImage: "rectangle.grid.1x2")
        }
        .focused(focus, equals: .action(.viewOptions))
        .accessibilityIdentifier("collection.viewOptions")
    }
}

/// Every item in one grid, Wholphin's `CollectionMixedGrid`, drawn with the grid options.
struct CollectionGrid: View {
    let items: [ItemDetails]
    let options: GridViewOptions
    let focus: FocusState<ItemFocus?>.Binding

    @Environment(BrowseModel.self) private var browse
    @Environment(\.displayScale) private var displayScale
    /// The page's width inside its margins, which the columns share.
    @State private var availableWidth: CGFloat = 0

    static let rowID = "all"

    var body: some View {
        let width = options.cardWidth(in: availableWidth)
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.fixed(width), spacing: options.spacing, alignment: .top),
                count: options.columns,
            ),
            alignment: .leading,
            spacing: options.spacing,
        ) {
            // No cards until the width is known, so none fetch artwork at 1 pt.
            ForEach(availableWidth > 0 ? items : []) { details in
                NavigationLink(value: details.item) {
                    MediaCard(
                        title: details.cardTitle,
                        subtitle: details.cardSubtitle,
                        spokenSubtitle: details.item.spokenSubtitle,
                        imageURL: browse.imageURL(details.cardImage(for: options.shape), width: width * displayScale),
                        shape: options.shape,
                        width: width,
                        progress: details.item.progress,
                        badges: details.badges,
                        showsCaption: options.showTitles,
                    )
                }
                .buttonStyle(.borderless)
                .focused(focus, equals: .card(row: Self.rowID, item: details.id))
                .accessibilityIdentifier("card.\(Self.rowID).\(details.id)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
        .padding(.vertical, ItemLayout.focusPadding)
        .focusSection()
    }
}
