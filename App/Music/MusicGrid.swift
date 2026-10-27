import AnemoneJellyfin
import AnemonePlayback
import AnemoneUI
import SwiftUI

/// A music library tab's grid of albums, artists or songs, Wholphin's `CollectionFolderView`
/// with its music sorts and square cards, six to a row. Albums and songs get Wholphin's Play
/// and Shuffle for everything in the list; a song card plays with the remote's Play/Pause.
struct MusicGrid: View {
    let list: MusicList
    /// What Play and Shuffle queue; no buttons when `nil`.
    var playSource: MusicSource?
    @Binding var path: NavigationPath
    @Binding var showsNowPlaying: Bool

    @Environment(BrowseModel.self) private var browse
    @Environment(MusicPlayer.self) private var player
    @State private var sort: MusicSort?
    @State private var pager: MusicPager?
    @State private var problem: String?
    @State private var alert: ItemAlert?

    private static let columns = 6
    private static let spacing: CGFloat = 40

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 30) {
                    header
                        .focusSection()
                    if let pager {
                        grid(pager, width: geometry.size.width - 2 * GridLayout.horizontalInset)
                    } else if let problem {
                        Text(problem)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, GridLayout.horizontalInset)
                .padding(.vertical, GridLayout.focusPadding)
            }
        }
        .task {
            if sort == nil {
                sort = MusicSortStore.sort(for: list)
            }
        }
        .task(id: sort) {
            await load()
        }
        .itemAlert($alert)
    }

    /// Play, Shuffle and the sort on the left, over the first cards, so moving down from them
    /// lands in the grid however few cards it has.
    private var header: some View {
        HStack(spacing: 24) {
            if let playSource {
                Button("Play", systemImage: "play.fill") {
                    play(playSource, shuffled: false)
                }
                .accessibilityIdentifier("music.play")
                Button("Shuffle", systemImage: "shuffle") {
                    play(playSource, shuffled: true)
                }
                .accessibilityIdentifier("music.shuffle")
            }
            MusicSortMenu(fields: list.sortFields, sort: sortBinding)
            Spacer()
            if let count = pager?.count {
                Text(count == 1 ? "1 item" : "\(count.formatted()) items")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("music.count")
            }
        }
        .font(.callout)
    }

    private func grid(_ pager: MusicPager, width: CGFloat) -> some View {
        let cardWidth = (width - CGFloat(Self.columns - 1) * Self.spacing) / CGFloat(Self.columns)
        let columns = Array(
            repeating: GridItem(.fixed(max(cardWidth, 1)), spacing: Self.spacing, alignment: .top),
            count: Self.columns,
        )
        return LazyVGrid(columns: columns, alignment: .leading, spacing: Self.spacing) {
            ForEach(0 ..< (width > 0 ? pager.count : 0), id: \.self) { index in
                MusicGridCard(index: index, pager: pager, width: cardWidth, open: open, play: play(song:))
            }
        }
    }

    private var sortBinding: Binding<MusicSort> {
        Binding { sort ?? .default } set: { newSort in
            sort = newSort
            MusicSortStore.save(newSort, for: list)
        }
    }

    private func open(_ item: MusicItem) {
        if item.item.kind == .audio, let albumID = item.albumID {
            path.append(AlbumSongLink(albumID: albumID, songID: item.id))
        } else {
            path.append(item.item)
        }
    }

    private func play(song: MusicItem) {
        player.play([song])
        showsNowPlaying = true
    }

    private func play(_ source: MusicSource, shuffled: Bool) {
        player.play(source, shuffled: shuffled, browse: browse) { alert = .failed($0) }
        showsNowPlaying = true
    }

    private func load() async {
        guard let sort else { return }
        let session = browse.session
        let list = list
        let pager = MusicPager { startIndex, limit, includeTotalCount in
            try await session.musicPage(
                list,
                sort: sort,
                startIndex: startIndex,
                limit: limit,
                includeTotalCount: includeTotalCount,
            )
        }
        do {
            try await pager.start()
            guard !Task.isCancelled else { return }
            self.pager = pager
            problem = nil
        } catch {
            guard !Task.isCancelled, self.pager == nil else { return }
            problem = browse.problem(with: error, doing: "load this list from \(browse.server.name)")
        }
    }
}

/// One card, kept separate so a page arriving redraws only the cards on screen.
private struct MusicGridCard: View {
    let index: Int
    let pager: MusicPager
    let width: CGFloat
    let open: (MusicItem) -> Void
    let play: (MusicItem) -> Void

    @Environment(BrowseModel.self) private var browse
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let item = pager.item(at: index)
        Button {
            if let item {
                open(item)
            }
        } label: {
            if let item {
                MusicCard(item: item, width: width)
            } else {
                MediaCard(title: " ", imageURL: nil, shape: .square, width: width)
            }
        }
        .buttonStyle(.borderless)
        .modifier(SongCardActions(song: item?.item.kind == .audio ? item : nil, play: play))
        .accessibilityLabel(item?.item.name ?? "Loading")
        .accessibilityIdentifier("music.card.\(index)")
        .task {
            await pager.prefetch(around: index)
        }
    }
}

/// A song card plays with the remote's Play/Pause, and has the song menu, as in Wholphin's
/// Songs tab.
private struct SongCardActions: ViewModifier {
    let song: MusicItem?
    let play: (MusicItem) -> Void

    func body(content: Content) -> some View {
        if let song {
            content
                .onPlayPauseCommand {
                    play(song)
                }
                .songMenu(song) { play(song) }
        } else {
            content
        }
    }
}

/// Wholphin's sort button for music lists: shows the current order; picking the current field
/// again reverses it.
private struct MusicSortMenu: View {
    let fields: [MusicSort.Field]
    @Binding var sort: MusicSort

    var body: some View {
        Menu {
            ForEach(fields, id: \.self) { field in
                Button {
                    sort = sort.choosing(field)
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
        .accessibilityLabel("Sort by \(sort.field.title)")
        .accessibilityIdentifier("music.sort")
    }
}

extension MusicSort.Field {
    /// Wholphin's names for its sort options.
    var title: String {
        switch self {
        case .name: "Name"
        case .premiereDate: "Date Released"
        case .album: "Album"
        case .albumArtist: "Album Artist"
        case .artist: "Artist"
        case .dateCreated: "Date Added"
        case .datePlayed: "Date Played"
        case .communityRating: "Community Rating"
        case .criticRating: "Critic Rating"
        case .playCount: "Play Count"
        case .runtime: "Runtime"
        case .random: "Random"
        }
    }
}

/// Each music list's sort, kept on the device as library sorts are.
private enum MusicSortStore {
    static func sort(for list: MusicList) -> MusicSort {
        guard let data = UserDefaults.standard.data(forKey: key(list)),
              let sort = try? JSONDecoder().decode(MusicSort.self, from: data),
              list.sortFields.contains(sort.field)
        else { return .default }
        return sort
    }

    static func save(_ sort: MusicSort, for list: MusicList) {
        UserDefaults.standard.set(try? JSONEncoder().encode(sort), forKey: key(list))
    }

    /// Genres share one sort per library, as Wholphin's genre grids share their filter.
    private static func key(_ list: MusicList) -> String {
        switch list {
        case let .albums(library): "musicSort.albums.\(library)"
        case let .genre(_, library): "musicSort.genre.\(library)"
        case let .artists(library): "musicSort.artists.\(library)"
        case let .songs(library): "musicSort.songs.\(library)"
        }
    }
}

/// A genre's albums, opened from the Genres tab.
struct MusicGridPage: View {
    let title: String
    let list: MusicList
    var playSource: MusicSource?
    @Binding var path: NavigationPath

    @State private var showsNowPlaying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.title2.bold())
                .padding(.horizontal, GridLayout.horizontalInset)
                .padding(.top, 40)
                .accessibilityIdentifier("detail.title")
            MusicGrid(list: list, playSource: playSource, path: $path, showsNowPlaying: $showsNowPlaying)
        }
        .nowPlaying(isPresented: $showsNowPlaying)
    }
}
