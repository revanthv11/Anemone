import AnemoneJellyfin
import AnemoneUI
import SwiftUI

/// Wholphin's filter menu as a sheet: each kind of filter with its current value, opening a list
/// of choices. Changes apply as they're made.
struct FilterSheet: View {
    let library: Library
    @Binding var filter: LibraryFilter
    let cache: FilterChoiceCache
    /// The kinds of filter to offer, when not all of the library's, such as on a genre's page.
    var kinds: [LibraryFilter.Kind]?

    var body: some View {
        NavigationStack {
            List {
                if !filter.isEmpty {
                    Button("Clear all filters", role: .destructive) {
                        filter = LibraryFilter()
                    }
                }
                ForEach(kinds ?? library.filterKinds, id: \.self) { kind in
                    NavigationLink(value: kind) {
                        LabeledContent(kind.title, value: summary(of: kind))
                    }
                }
            }
            .navigationTitle("Filter")
            .navigationDestination(for: LibraryFilter.Kind.self) { kind in
                FilterChoices(library: library, kind: kind, filter: $filter, cache: cache)
            }
        }
    }

    private func summary(of kind: LibraryFilter.Kind) -> String {
        let any = String(localized: "Any")
        return switch kind {
        case .played: filter.played.map { $0 ? String(localized: "Played") : String(localized: "Unplayed") } ?? any
        case .favorite:
            filter.favorite.map { $0 ? String(localized: "Favorites") : String(localized: "Not favorites") } ?? any
        case .communityRating: filter.minCommunityRating.map { String(localized: "\($0) or higher") } ?? any
        case .genres: count(filter.genres)
        case .studios: count(filter.studios)
        case .officialRating: list(filter.officialRatings.sorted())
        case .videoType: list(LibraryFilter.VideoType.allCases.filter(filter.videoTypes.contains).map(\.title))
        case .year: list(filter.years.sorted().map(String.init))
        case .decade: list(filter.decades.sorted().map { "\($0)s" })
        }
    }

    private func count(_ values: Set<String>) -> String {
        values.isEmpty ? String(localized: "Any") : String(localized: "\(values.count) selected")
    }

    private func list(_ values: [String]) -> String {
        values.isEmpty ? String(localized: "Any") : values.joined(separator: ", ")
    }
}

/// The choices for one kind of filter. Genres, studios, ratings and years come from the server;
/// the rest are fixed, as in Wholphin's `FilterOptionCache`.
private struct FilterChoices: View {
    let library: Library
    let kind: LibraryFilter.Kind
    @Binding var filter: LibraryFilter
    let cache: FilterChoiceCache

    @Environment(BrowseModel.self) private var browse
    @State private var options: [FilterOption]?
    @State private var failed = false

    var body: some View {
        List {
            if let options {
                if options.isEmpty {
                    Text("Nothing to filter by in \(library.name).")
                        .foregroundStyle(.secondary)
                }
                ForEach(options) { option in
                    Button {
                        toggle(option.id)
                    } label: {
                        HStack {
                            Text(option.name)
                            Spacer()
                            if isSelected(option.id) {
                                Image(systemName: "checkmark")
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    // VoiceOver hears the check as the row being selected.
                    .accessibilityAddTraits(isSelected(option.id) ? .isSelected : [])
                }
            } else if failed {
                Text("Couldn't load the choices from \(browse.server.name).")
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(kind.title)
        .task {
            await load()
        }
    }

    private func load() async {
        if let cached = cache.options[kind] {
            options = cached
            return
        }
        do {
            let loaded = try await choices()
            cache.options[kind] = loaded
            options = loaded
        } catch SessionError.signedOut {
            browse.noteSignedOut()
            failed = true
        } catch {
            failed = true
        }
    }

    private func choices() async throws -> [FilterOption] {
        let session = browse.session
        return switch kind {
        case .played:
            [
                FilterOption(id: "true", name: String(localized: "Played")),
                FilterOption(id: "false", name: String(localized: "Unplayed")),
            ]
        case .favorite:
            [
                FilterOption(id: "true", name: String(localized: "Favorites")),
                FilterOption(id: "false", name: String(localized: "Not favorites")),
            ]
        case .communityRating:
            (1 ... 10).map { FilterOption(id: "\($0)", name: String(localized: "\($0) or higher")) }
        case .videoType:
            LibraryFilter.VideoType.allCases.map { FilterOption(id: $0.rawValue, name: $0.title) }
        case .genres:
            try await session.genres(in: library)
        case .studios:
            try await session.studios(in: library)
        case .officialRating:
            try await session.officialRatings(in: library).map { FilterOption(id: $0, name: $0) }
        case .year:
            try await session.years(in: library).map { FilterOption(id: "\($0)", name: "\($0)") }
        case .decade:
            try await LibraryFilter.decades(of: session.years(in: library))
                .map { FilterOption(id: "\($0)", name: "\($0)s") }
        }
    }

    private func isSelected(_ id: String) -> Bool {
        switch kind {
        case .played: filter.played.map(String.init) == id
        case .favorite: filter.favorite.map(String.init) == id
        case .communityRating: filter.minCommunityRating.map(String.init) == id
        case .genres: filter.genres.contains(id)
        case .studios: filter.studios.contains(id)
        case .officialRating: filter.officialRatings.contains(id)
        case .videoType: LibraryFilter.VideoType(rawValue: id).map(filter.videoTypes.contains) ?? false
        case .year: Int(id).map(filter.years.contains) ?? false
        case .decade: Int(id).map(filter.decades.contains) ?? false
        }
    }

    /// Single-choice filters switch off when their choice is picked again; the rest add or remove it.
    private func toggle(_ id: String) {
        let selected = isSelected(id)
        switch kind {
        case .played: filter.played = selected ? nil : Bool(id)
        case .favorite: filter.favorite = selected ? nil : Bool(id)
        case .communityRating: filter.minCommunityRating = selected ? nil : Int(id)
        case .genres: filter.genres.formSymmetricDifference([id])
        case .studios: filter.studios.formSymmetricDifference([id])
        case .officialRating: filter.officialRatings.formSymmetricDifference([id])
        case .videoType: LibraryFilter.VideoType(rawValue: id).map { filter.videoTypes.formSymmetricDifference([$0]) }
        case .year: Int(id).map { filter.years.formSymmetricDifference([$0]) }
        case .decade: Int(id).map { filter.decades.formSymmetricDifference([$0]) }
        }
    }
}

/// A library's filter choices, fetched once while its page is open, as Wholphin's
/// `FilterOptionCache` keeps them.
final class FilterChoiceCache {
    var options: [LibraryFilter.Kind: [FilterOption]] = [:]
}

/// Wholphin's view options, the ones that fit a TV grid: card shape, columns and titles; on
/// library pages also the layout, the details header and the backdrop. Changes apply as they're
/// made.
struct ViewOptionsSheet: View {
    @Binding var options: GridViewOptions
    let defaults: GridViewOptions
    /// Whether to offer the list layouts, details and backdrop, which only library pages draw.
    var showsPageOptions = false

    var body: some View {
        NavigationStack {
            List {
                if showsPageOptions {
                    Picker("Layout", selection: $options.layout) {
                        ForEach(GridViewOptions.Layout.allCases, id: \.self) { layout in
                            Text(layout.title)
                        }
                    }
                    .accessibilityIdentifier("viewOptions.layout")
                }
                // Wholphin's list layouts have no cards to size.
                if options.layout == .grid || !showsPageOptions {
                    Picker("Card shape", selection: $options.shape) {
                        ForEach(CardShape.allCases, id: \.self) { shape in
                            Text(shape.title)
                        }
                    }
                    // Eleven choices don't fit side by side, a menu picker hides the label, and a
                    // navigation-link picker shows an empty page inside a sheet on tvOS 27.
                    NavigationLink(value: ColumnsPage()) {
                        LabeledContent("Columns", value: "\(options.columns)")
                    }
                    Toggle("Show titles", isOn: $options.showTitles)
                }
                if showsPageOptions {
                    Toggle("Show details", isOn: $options.showsDetails)
                        .accessibilityIdentifier("viewOptions.details")
                    Toggle("Show backdrop", isOn: $options.showsBackdrop)
                        .accessibilityIdentifier("viewOptions.backdrop")
                }
                Button("Reset to defaults") {
                    options = defaults
                }
                .disabled(options == defaults)
            }
            .navigationTitle("View Options")
            .navigationDestination(for: ColumnsPage.self) { _ in
                List(GridViewOptions.columnChoices, id: \.self) { columns in
                    Button {
                        options.columns = columns
                    } label: {
                        HStack {
                            Text("\(columns)")
                            Spacer()
                            if columns == options.columns {
                                Image(systemName: "checkmark")
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .accessibilityAddTraits(columns == options.columns ? .isSelected : [])
                }
                .navigationTitle("Columns")
            }
        }
    }

    private struct ColumnsPage: Hashable {}
}

extension LibraryFilter.Kind {
    /// Wholphin's names for its filters.
    var title: String {
        switch self {
        case .played: String(localized: "Played")
        case .favorite: String(localized: "Favorites")
        case .genres: String(localized: "Genres")
        case .studios: String(localized: "Studios")
        case .communityRating: String(localized: "Community Rating")
        case .officialRating: String(localized: "Parental Rating")
        case .videoType: String(localized: "Video")
        case .year: String(localized: "Year")
        case .decade: String(localized: "Decade")
        }
    }
}

extension LibraryFilter.VideoType {
    var title: String {
        switch self {
        case .fourK: "4K"
        case .highDefinition: String(localized: "HD")
        case .standardDefinition: String(localized: "SD")
        case .threeD: "3D"
        case .bluRay: String(localized: "Blu-ray")
        case .dvd: String(localized: "DVD")
        }
    }
}

extension GridViewOptions.Layout {
    /// Wholphin's names for its layouts.
    var title: String {
        switch self {
        case .grid: String(localized: "Grid")
        case .list: String(localized: "List")
        case .denseList: String(localized: "Dense list")
        }
    }
}

extension CardShape {
    var title: String {
        switch self {
        case .poster: String(localized: "Poster")
        case .thumb: String(localized: "Landscape")
        case .square: String(localized: "Square")
        }
    }
}
