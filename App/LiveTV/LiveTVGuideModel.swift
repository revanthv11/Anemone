import AnemoneCore
import AnemoneJellyfin
import Foundation
import Observation

/// The guide's channels, listings and the stretch of time showing, ported from Wholphin's
/// `LiveTvViewModel`. Listings load a page of channels at a time: the first page with the
/// channels, the rest as their rows come on screen, as Wholphin loads more around focus.
@MainActor
@Observable
final class LiveTVGuideModel {
    enum State: Equatable {
        case loading
        case loaded
        /// Live TV is on, but the server has no channels.
        case noChannels
        case failed(String)
    }

    /// Channels whose listings one request asks for. Wholphin asks for 10 first, then 100.
    static let pageSize = 20

    private(set) var state = State.loading
    private(set) var guide = LiveTVGuide()
    private(set) var channels: [LiveTVChannel] = []
    /// Each channel's row from the guide's start to its end, once its listings have loaded.
    private(set) var rows: [LiveTVChannel.ID: [LiveTVProgram]] = [:]
    /// The stretch of the guide on screen.
    var window = DateInterval()

    @ObservationIgnored private let browse: BrowseModel
    /// The pages asked for, and which answer for each is the newest. Listings asked for under an
    /// earlier channel list or guide, whose pages held other channels, are dropped when they
    /// arrive, and so is an answer older than the one its page shows.
    @ObservationIgnored private var pages = LiveTVListingPages(pageSize: LiveTVGuideModel.pageSize)
    /// Counts calls to `load()`, so only the latest one puts up what it loaded.
    @ObservationIgnored private var loads = 0

    init(browse: BrowseModel) {
        self.browse = browse
    }

    /// Loads the channels and the first page of listings, starting the guide at the half hour
    /// before now. Reloading keeps what's showing until the new guide is ready.
    func load() async {
        let session = browse.session
        let guide = LiveTVGuide()
        loads += 1
        let load = loads
        let firstPage = pages.start(0)
        do {
            let channels = try await session.liveTVChannels(order: Preferences.liveTVChannelOrder)
            let first = Array(channels.prefix(Self.pageSize))
            let programs = try await listings(for: first, in: guide)
            guard !Task.isCancelled, load == loads else { return }
            self.guide = guide
            self.channels = channels
            rows.merge(Self.rows(for: first, programs: programs, in: guide)) { $1 }
            // Rows already on screen won't ask again, so the pages they asked for reload now.
            for again in pages.startOver(showing: firstPage) {
                Task {
                    await loadListings(again)
                }
            }
            if window.duration == 0 || window.start < guide.start {
                window = guide.window(from: guide.start, length: LiveTVLayout.windowLength)
            }
            state = channels.isEmpty ? .noChannels : .loaded
        } catch {
            guard load == loads,
                  let problem = browse.problem(
                      with: error,
                      failure: "Couldn't load the guide from \(browse.server.name).",
                  )
            else { return }
            if state != .loaded {
                state = .failed(problem)
            }
        }
    }

    /// Loads the listings for the page of channels holding `index`, if they haven't been asked
    /// for; rows call it as they come on screen.
    func loadListings(forRow index: Int) {
        guard state == .loaded, let load = pages.firstLoad(forRow: index) else { return }
        Task {
            await loadListings(load)
        }
    }

    /// Loads listings again after a recording was set or cancelled, so their markers change. A
    /// single programme's recording marks only that programme, so only the page holding its
    /// `channel` loads again; a series recording (`channel` `nil`) marks its programmes on every
    /// channel it airs on, so every page asked for so far does.
    func reloadListings(channel: LiveTVChannel.ID? = nil) async {
        let index = channel.flatMap { id in channels.firstIndex { $0.id == id } }
        let loads = pages.reloads(channelIndex: index)
        await withTaskGroup(of: Void.self) { group in
            for load in loads {
                group.addTask {
                    await self.loadListings(load)
                }
            }
        }
    }

    func channel(_ id: LiveTVChannel.ID) -> LiveTVChannel? {
        channels.first { $0.id == id }
    }

    func program(_ id: LiveTVProgram.ID, on channelID: LiveTVChannel.ID) -> LiveTVProgram? {
        rows[channelID]?.first { $0.id == id }
    }

    /// What's on now, or the first cell showing when now is off screen.
    func currentProgram(on channelID: LiveTVChannel.ID, now: Date = .now) -> LiveTVProgram? {
        let cells = cells(on: channelID)
        return cells.first { $0.program.isAiring(at: now) }?.program ?? cells.first?.program
    }

    func cells(on channelID: LiveTVChannel.ID) -> [LiveTVGuideCell] {
        guide.cells(in: rows[channelID] ?? [], window: window)
    }

    // MARK: Moving past the edges

    /// Focus pressed right from the last programme showing: moves the window on to the next
    /// programme and returns it, or `nil` when there's nothing further.
    func moveForward(from program: LiveTVProgram) -> LiveTVProgram? {
        guard let row = rows[program.channelID], window.end < guide.end,
              cells(on: program.channelID).last?.program.id == program.id
        else { return nil }
        guard let next = guide.program(after: window, in: row) else {
            window = guide.window(from: guide.end, length: LiveTVLayout.windowLength)
            return program
        }
        window = guide.window(movingForwardTo: next, length: LiveTVLayout.windowLength)
        return next
    }

    /// Focus pressed left from the first programme showing, while the window is later than the
    /// guide's start: moves the window back to the programme before and returns it.
    func moveBack(from program: LiveTVProgram) -> LiveTVProgram? {
        guard let row = rows[program.channelID], window.start > guide.start else { return nil }
        guard let previous = guide.program(before: window, in: row) else {
            window = guide.window(from: guide.start, length: LiveTVLayout.windowLength)
            return program
        }
        window = guide.window(movingBackTo: previous, length: LiveTVLayout.windowLength)
        return previous
    }

    /// Back to now, as Wholphin's Back does when the guide has scrolled ahead.
    func showNow() {
        window = guide.window(from: guide.start, length: LiveTVLayout.windowLength)
    }

    /// Puts up the page's listings, unless a reload put up other channels or another guide
    /// meanwhile (it asks for its own pages), or a later load of the page has already landed.
    private func loadListings(_ load: LiveTVListingPages.Load) async {
        let channels = Array(channels.dropFirst(load.page * Self.pageSize).prefix(Self.pageSize))
        guard !channels.isEmpty else { return }
        let guide = guide
        do {
            let programs = try await listings(for: channels, in: guide)
            guard pages.accept(load) else { return }
            rows.merge(Self.rows(for: channels, programs: programs, in: guide)) { $1 }
        } catch {
            // Rows that show no data ask again when they next come on screen.
            pages.failed(load)
        }
    }

    private func listings(for channels: [LiveTVChannel], in guide: LiveTVGuide) async throws -> [LiveTVProgram] {
        #if DEBUG
            if LiveTVDebugData.isOn {
                return LiveTVDebugData.programs(for: channels, in: guide)
            }
        #endif
        return try await browse.session.liveTVPrograms(channelIDs: channels.map(\.id), in: guide)
    }

    private static func rows(
        for channels: [LiveTVChannel],
        programs: [LiveTVProgram],
        in guide: LiveTVGuide,
    ) -> [LiveTVChannel.ID: [LiveTVProgram]] {
        let byChannel = Dictionary(grouping: programs, by: \.channelID)
        return Dictionary(uniqueKeysWithValues: channels.map { channel in
            (channel.id, guide.row(channelID: channel.id, programs: byChannel[channel.id] ?? []))
        })
    }
}
