import AnemoneCore
import AnemoneJellyfin
import AnemoneUI
import SwiftUI

/// One row's settings, Wholphin's `HomeRowSettings`: card size, image and titles; for episodes,
/// their own image; and for the watching rows, combining or splitting them.
struct HomeRowOptionsPage: View {
    /// The row's place in Home's rows.
    let index: Int

    @Environment(BrowseModel.self) private var browse
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    var body: some View {
        if let rows = browse.homeRows, rows.indices.contains(index) {
            form(rows[index], rows: rows)
                .navigationTitle(rows[index].title(libraries: browse.libraries))
        } else {
            // The row went, for example after Reset.
            Text("This row is no longer on Home.")
                .foregroundStyle(theme.secondaryText)
                .focusable()
        }
    }

    private func form(_ row: HomeRowConfig, rows: [HomeRowConfig]) -> some View {
        let isCategory = Self.isCategory(row)
        return List {
            Section("Cards") {
                Picker("Height", selection: binding(\.heightDp, row)) {
                    ForEach(Self.heights(including: row.viewOptions.heightDp), id: \.self) { Text("\($0)").tag($0) }
                }
                .accessibilityIdentifier("settings.home.options.height")
                Picker("Spacing", selection: binding(\.spacing, row)) {
                    ForEach(Self.spacings(including: row.viewOptions.spacing), id: \.self) { Text("\($0)").tag($0) }
                }
                if !isCategory {
                    imagePickers(row, type: \.imageType, ratio: \.aspectRatio)
                    Toggle("Show titles", isOn: binding(\.showTitles, row))
                        .accessibilityIdentifier("settings.home.options.showTitles")
                    Toggle("Use series image", isOn: binding(\.useSeries, row))
                }
            }
            if row.isWatchingRow {
                Section("For episodes") {
                    imagePickers(row, type: \.episodeImageType, ratio: \.episodeAspectRatio)
                }
            }
            if case let .byParent(parentID, recursive, sort) = row.kind {
                sortSection(row, parentID: parentID, recursive: recursive, sort: sort)
            }
            Section {
                actions(row, rows: rows, isCategory: isCategory)
            }
        }
    }

    /// Wholphin's image type and aspect ratio. Picking an image type picks its usual shape too.
    @ViewBuilder
    private func imagePickers(
        _ row: HomeRowConfig,
        type: WritableKeyPath<HomeRowViewOptions, HomeRowViewOptions.ImageType>,
        ratio: WritableKeyPath<HomeRowViewOptions, HomeRowViewOptions.AspectRatio>,
    ) -> some View {
        Picker("Image type", selection: Binding {
            row.viewOptions[keyPath: type]
        } set: { value in
            update(row) {
                $0[keyPath: type] = value
                $0[keyPath: ratio] = value == .thumb ? .wide : .tall
            }
        }) {
            Text("Primary").tag(HomeRowViewOptions.ImageType.primary)
            Text("Thumb").tag(HomeRowViewOptions.ImageType.thumb)
        }
        Picker("Aspect ratio", selection: binding(ratio, row)) {
            Text("Tall (2:3)").tag(HomeRowViewOptions.AspectRatio.tall)
            Text("Wide (16:9)").tag(HomeRowViewOptions.AspectRatio.wide)
            Text("4:3").tag(HomeRowViewOptions.AspectRatio.fourThree)
            Text("Square").tag(HomeRowViewOptions.AspectRatio.square)
        }
    }

    private func sortSection(_ row: HomeRowConfig, parentID: String, recursive: Bool, sort: HomeRowSort?) -> some View {
        Section("Sort") {
            Picker("Sort by", selection: Binding {
                sort?.field ?? "Default"
            } set: { field in
                let newSort = field == "Default" ? nil : HomeRowSort(
                    field: field,
                    direction: sort?.direction ?? .ascending,
                )
                replace(row, with: HomeRowConfig(
                    .byParent(parentID: parentID, recursive: recursive, sort: newSort),
                    viewOptions: row.viewOptions,
                ))
            }) {
                ForEach(Self.sortFields, id: \.0) { Text($0.1).tag($0.0) }
            }
            if let sort {
                Toggle("Descending", isOn: Binding {
                    sort.direction == .descending
                } set: { descending in
                    let flipped = HomeRowSort(field: sort.field, direction: descending ? .descending : .ascending)
                    replace(row, with: HomeRowConfig(
                        .byParent(parentID: parentID, recursive: recursive, sort: flipped),
                        viewOptions: row.viewOptions,
                    ))
                })
            }
        }
    }

    @ViewBuilder
    private func actions(_ row: HomeRowConfig, rows: [HomeRowConfig], isCategory: Bool) -> some View {
        switch row.kind {
        case .continueWatching, .nextUp:
            Button("Combine Continue Watching & Next Up") {
                browse.setHomeRows(rows.combiningWatchingRows())
                dismiss()
            }
        case .continueWatchingCombined:
            Button("Split into separate rows") {
                browse.setHomeRows(rows.splittingWatchingRows())
                dismiss()
            }
        default:
            EmptyView()
        }
        if !isCategory {
            Button("Use thumb images") {
                update(row) { $0 = $0.usingThumbs }
            }
        }
        Button("Reset") {
            update(row) { $0 = row.kind.defaultViewOptions }
        }
    }

    private func binding<Value>(
        _ keyPath: WritableKeyPath<HomeRowViewOptions, Value>,
        _ row: HomeRowConfig,
    ) -> Binding<Value> {
        Binding {
            row.viewOptions[keyPath: keyPath]
        } set: { value in
            update(row) { $0[keyPath: keyPath] = value }
        }
    }

    private func update(_ row: HomeRowConfig, _ change: (inout HomeRowViewOptions) -> Void) {
        var changed = row
        change(&changed.viewOptions)
        replace(row, with: changed)
    }

    private func replace(_ row: HomeRowConfig, with changed: HomeRowConfig) {
        guard var rows = browse.homeRows, rows.indices.contains(index), changed != row else { return }
        rows[index] = changed
        browse.setHomeRows(rows)
    }

    /// Genre and studio rows have only size options in Wholphin (`GENRE_OPTIONS`).
    private static func isCategory(_ row: HomeRowConfig) -> Bool {
        switch row.kind {
        case .genres, .studios: true
        default: false
        }
    }

    /// Wholphin's height slider runs from 64 to 236 dp; these are steps along it.
    private static func heights(including current: Int) -> [Int] {
        Array(Set([64, 80, 96, 112, 128, 148, 172, 200, 236, current])).sorted()
    }

    private static func spacings(including current: Int) -> [Int] {
        Array(Set([0, 4, 8, 12, 16, 20, 24, 32, current])).sorted()
    }

    /// Wholphin's `BoxSetSortOptions`, by Jellyfin's names.
    private static let sortFields = [
        ("Default", "Default"), ("SortName", "Name"), ("PremiereDate", "Date Released"),
        ("DateCreated", "Date Added"), ("CommunityRating", "Community Rating"), ("CriticRating", "Critic Rating"),
        ("Random", "Random"),
    ]
}
