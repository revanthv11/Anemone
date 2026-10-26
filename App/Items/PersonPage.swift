import AnemoneJellyfin
import AnemoneUI
import SwiftUI

/// Wholphin's person page (`PersonPage`): photo, name, birth and death, overview and favourite,
/// then the person's movies, series and episodes in this library.
struct PersonPage: View {
    @Binding var person: ItemDetails

    @Environment(BrowseModel.self) private var browse
    @Environment(\.displayScale) private var displayScale
    @FocusState private var focus: ItemFocus?
    @State private var memory = RowMemory()
    @State private var filmography: [FilmographyRow: [ItemDetails]] = [:]
    @State private var alert: ItemAlert?

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: ItemLayout.sectionSpacing) {
                    header
                        .padding(.bottom, 40)
                    ForEach(FilmographyRow.allCases, id: \.self) { row in
                        if let items = filmography[row], !items.isEmpty {
                            ItemRow(
                                id: "\(row)",
                                title: "\(row.title) (\(items.count))",
                                items: items,
                                shape: row == .episodes ? .thumb : .poster,
                                focus: $focus,
                                memory: memory,
                            )
                        }
                    }
                }
                .padding(.horizontal, ItemLayout.horizontalInset)
                .padding(.top, ItemLayout.topInset)
                .padding(.bottom, ItemLayout.focusPadding)
                // Scrolling here shows the header with its top margin.
                .id(ItemLayout.headerID)
            }
            .onChange(of: focus) { _, focus in
                memory.note(focus)
                if focus?.isInHeader == true {
                    withAnimation { scroller.scrollTo(ItemLayout.headerID, anchor: .top) }
                }
            }
        }
        .initialFocus($focus, person.item.overview == nil ? .action(.favorite) : .overview)
        .itemAlert($alert)
        .task(id: person.id) {
            // A person's credits don't change between visits, so coming back doesn't reload them.
            guard filmography.isEmpty else { return }
            let session = browse.session
            let id = person.id
            let rows = FilmographyRow.allCases.filter(person.creditCounts.mayHave)
            // Loaded together, then shown in Wholphin's order.
            let results = await withTaskGroup(of: (FilmographyRow, Result<[ItemDetails], any Error>).self) { group in
                for row in rows {
                    group.addTask { await (row, attempt { try await session.filmography(ofPerson: id, row: row) }) }
                }
                var results: [(FilmographyRow, Result<[ItemDetails], any Error>)] = []
                for await result in group {
                    results.append(result)
                }
                return results
            }
            for (row, result) in results {
                if let items = browse.optional(result) {
                    filmography[row] = items
                }
            }
        }
    }

    /// Wholphin's `PersonHeader`.
    private var header: some View {
        HStack(alignment: .top, spacing: 48) {
            ShapedArtwork(
                url: browse.imageURL(person.ownPrimaryImage, width: Self.photoWidth * displayScale),
                shape: .poster,
                width: Self.photoWidth,
                cornerRadius: 24,
                placeholderSymbol: "person.fill",
            )
            VStack(alignment: .leading, spacing: 12) {
                Text(person.item.name)
                    .font(.title.bold())
                    .lineLimit(2)
                    .accessibilityIdentifier("detail.title")
                    .padding(.bottom, 8)
                if let born = person.premiereDate {
                    if person.endDate == nil, let age = person.age() {
                        Text("Born: \(born.longDayText) (\(age) years old)")
                    } else {
                        Text("Born: \(born.longDayText)")
                    }
                }
                if let birthPlace = person.birthPlace {
                    Text("Birthplace: \(birthPlace)")
                }
                if let died = person.endDate {
                    if let age = person.age() {
                        Text("Died: \(died.longDayText) (\(age) years old)")
                    } else {
                        Text("Died: \(died.longDayText)")
                    }
                }
                if let overview = person.item.overview {
                    OverviewButton(title: person.item.name, overview: overview)
                        .focused($focus, equals: .overview)
                        .padding(.top, 8)
                }
                FavoriteButton(isFavorite: person.userState.isFavorite) {
                    Task { await setFavorite(!person.userState.isFavorite) }
                }
                .focused($focus, equals: .action(.favorite))
                .padding(.top, 8)
            }
            .font(.callout)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(32)
            .background(.white.opacity(0.06), in: .rect(cornerRadius: 24))
        }
        .focusSection()
    }

    private static let photoWidth: CGFloat = 300

    private func setFavorite(_ isFavorite: Bool) async {
        if let state = await browse.save(.favorite(isFavorite), for: person, failed: { alert = $0 }) {
            person.apply(state)
        }
    }
}

private extension FilmographyRow {
    var title: String {
        switch self {
        case .movies: "Movies"
        case .series: "TV Shows"
        case .episodes: "Episodes"
        }
    }
}

private extension Date {
    /// Like `dayText`, in full: "June 15, 1950".
    var longDayText: String {
        formatted(Date.FormatStyle(date: .long, time: .omitted, timeZone: .gmt))
    }
}
