import AnemoneCore
import AnemoneJellyfin
import AnemoneUI
import SwiftUI

/// Settings › Home: which rows Home shows and in what order, and how each looks, like Wholphin's
/// home settings. Changes show on Home when it next appears, and are saved on the server for the
/// user, so they follow them to other Apple TVs.
struct HomeSettingsPage: View {
    @Environment(BrowseModel.self) private var browse
    @AppStorage(Preferences.maxItemsPerRow) private var itemsPerRow: Int
    @AppStorage(Preferences.enableRewatchingNextUp) private var rewatchesNextUp: Bool
    @AppStorage(Preferences.maxDaysNextUp) private var maxDaysNextUp: Int
    /// Names of the collections and playlists rows show, which aren't libraries.
    @State private var names: [String: String] = [:]
    @State private var notice: String?
    @State private var isWorking = false
    @State private var confirmsReset = false
    /// The row whose options are open, by its place in the list.
    @State private var editing: Int?

    var body: some View {
        List {
            if let rows = browse.homeRows {
                rowsSection(rows)
            } else {
                Text("Your rows appear here once Home has loaded.")
                    .foregroundStyle(.secondary)
                    .focusable()
            }
            Section("Every row") {
                Picker("Max items on home page rows", selection: $itemsPerRow) {
                    ForEach(HomePreferenceChoices.itemsPerRow, id: \.self) { Text("\($0)").tag($0) }
                }
                Toggle("Enable rewatching in Next Up", isOn: $rewatchesNextUp)
                Picker("Max days in Next Up", selection: $maxDaysNextUp) {
                    ForEach(HomePreferenceChoices.maxDaysNextUp, id: \.self) { days in
                        Text(days > 0 ? "\(days) days" : "No limit").tag(days)
                    }
                }
                NavigationLink("Series removed from Next Up") {
                    HomeRemovedNextUpPage()
                }
            }
            serverSection
        }
        .navigationTitle("Home")
        .navigationDestination(item: $editing) { index in
            HomeRowOptionsPage(index: index)
        }
        .disabled(isWorking)
        .task(id: browse.homeRows) {
            await loadNames()
        }
        .confirmationDialog("Reset Home's rows?", isPresented: $confirmsReset) {
            Button("Reset", role: .destructive) {
                run { try await browse.resetHomeRows() }
            }
        } message: {
            Text("This forgets the rows saved for you on \(browse.server.name).")
        }
    }

    private func rowsSection(_ rows: [HomeRowConfig]) -> some View {
        let ids = HomeRowConfig.rowIDs(for: rows)
        return Section {
            Toggle("Combine Continue Watching & Next Up", isOn: combinedBinding(rows))
                .accessibilityIdentifier("settings.home.combine")
            ForEach(Array(zip(ids, rows).enumerated()), id: \.element.0) { index, entry in
                HomeRowListEntry(
                    id: entry.0,
                    title: entry.1.title(libraries: browse.libraries, names: names),
                    index: index,
                    rows: rows,
                ) {
                    editing = index
                }
            }
            NavigationLink {
                HomeAddRowPage()
            } label: {
                Label("Add row", systemImage: "plus")
            }
            .accessibilityIdentifier("settings.home.addRow")
        } header: {
            Text("Home rows (\(rows.count))")
        } footer: {
            Text(notice ?? browse.homeSaveProblem ?? sourceDescription)
        }
    }

    private var serverSection: some View {
        Section {
            Button("Import from Wholphin") {
                run {
                    let imported = try await browse.importHomeRowsFromWholphin()
                    notice = imported
                        ? String(localized: "Imported the rows Wholphin saved for you.")
                        : String(localized: "Wholphin hasn't saved rows for you on \(browse.server.name).")
                }
            }
            .accessibilityIdentifier("settings.home.importWholphin")
            Button("Reset to default") {
                confirmsReset = true
            }
            .accessibilityIdentifier("settings.home.reset")
        } header: {
            Text("Saved rows")
        } footer: {
            Text("Wholphin's rows are copied once; changes in either app afterwards stay in that app.")
        }
    }

    private var sourceDescription: String {
        switch browse.homeRowsSource {
        case .server: String(localized: "Saved for you on \(browse.server.name).")
        case .plugin: String(localized: "Set for everyone by \(browse.server.name)'s Wholphin plugin.")
        case .default: String(localized: "Anemone's default rows.")
        }
    }

    /// On: Wholphin's Combine; off: its Split. Combining with neither row there adds the
    /// combined row at the top.
    private func combinedBinding(_ rows: [HomeRowConfig]) -> Binding<Bool> {
        Binding {
            rows.contains { $0.kind == .continueWatchingCombined }
        } set: { combine in
            var changed = combine ? rows.combiningWatchingRows() : rows.splittingWatchingRows()
            if combine, !changed.contains(where: { $0.kind == .continueWatchingCombined }) {
                changed.insert(HomeRowConfig(.continueWatchingCombined), at: 0)
            }
            browse.setHomeRows(changed)
        }
    }

    private func run(_ action: @escaping () async throws -> Void) {
        isWorking = true
        notice = nil
        Task {
            do {
                try await action()
            } catch {
                notice = browse.problem(with: error, failure: "Couldn't update your rows on \(browse.server.name).")
            }
            isWorking = false
        }
    }

    /// Names for rows of collections and playlists, which the library list doesn't have.
    private func loadNames() async {
        let libraryIDs = Set(browse.libraries.map(\.id))
        let ids = (browse.homeRows ?? []).compactMap { row -> String? in
            guard case let .byParent(id, _, _) = row.kind, !libraryIDs.contains(id), names[id] == nil else {
                return nil
            }
            return id
        }
        guard let items = try? await browse.session.mediaItems(ids: ids) else { return }
        for item in items {
            names[item.id] = item.name
        }
    }
}

/// A row in the list: its options, and buttons to move or remove it, as in Wholphin's row list.
///
/// A list row on tvOS is one focus target unless its buttons are borderless, so they are; and a
/// `NavigationLink` would make it one again, so the options open from a button. Moving up or
/// down into the row lands on its title, not on whichever button is nearest.
private struct HomeRowListEntry: View {
    let id: String
    let title: String
    let index: Int
    let rows: [HomeRowConfig]
    let openOptions: () -> Void

    @Environment(BrowseModel.self) private var browse
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        HStack(spacing: 24) {
            Button(action: openOptions) {
                HStack {
                    Text(title)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(RowTitleButtonStyle())
            .focused($isTitleFocused)
            // Where the row is on Home; the buttons beside it move it.
            .accessibilityValue(Text("Row \(index + 1) of \(rows.count)"))
            .accessibilityIdentifier("settings.home.row.\(id)")
            Button("Move up", systemImage: "chevron.up") {
                move(by: -1)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .disabled(index == 0)
            .accessibilityIdentifier("settings.home.row.\(id).up")
            Button("Move down", systemImage: "chevron.down") {
                move(by: 1)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .disabled(index == rows.count - 1)
            .accessibilityIdentifier("settings.home.row.\(id).down")
            Button("Remove", systemImage: "trash") {
                var changed = rows
                changed.remove(at: index)
                browse.setHomeRows(changed)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            // Wholphin keeps at least one row.
            .disabled(rows.count == 1)
            .accessibilityIdentifier("settings.home.row.\(id).remove")
        }
        .focusSection()
        .defaultFocus($isTitleFocused, true, priority: .userInitiated)
    }

    private func move(by offset: Int) {
        var changed = rows
        changed.swapAt(index, index + offset)
        browse.setHomeRows(changed)
    }
}

/// A row title that highlights like a list row when focused, on the theme's light platter. A
/// borderless button, which the row needs, would only lift its chevron.
private struct RowTitleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RowTitle(label: configuration.label, isPressed: configuration.isPressed)
    }

    private struct RowTitle<Label: View>: View {
        let label: Label
        let isPressed: Bool

        @Environment(\.isFocused) private var isFocused
        @Environment(\.theme) private var theme

        var body: some View {
            label
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .foregroundStyle(isFocused ? theme.onFocusedPlatter : theme.onBackground)
                .background(isFocused ? theme.focusedPlatter.color : .clear, in: .rect(cornerRadius: 12))
                .scaleEffect(isPressed ? 0.98 : 1)
                .animation(.easeOut(duration: 0.15), value: isFocused)
        }
    }
}
