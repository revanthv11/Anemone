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
    @ObservationIgnored private var requestedPages: Set<Int> = []

    init(browse: BrowseModel) {
        self.browse = browse
    }

    /// Loads the channels and the first page of listings, starting the guide at the half hour
    /// before now. Reloading keeps what's showing until the new guide is ready.
    func load() async {
        let session = browse.session
        let guide = LiveTVGuide()
        do {
            let channels = try await session.liveTVChannels(order: Preferences.liveTVChannelOrder)
            let first = Array(channels.prefix(Self.pageSize))
            let programs = try await listings(for: first, in: guide)
            guard !Task.isCancelled else { return }
            self.guide = guide
            self.channels = channels
            rows.merge(Self.rows(for: first, programs: programs, in: guide)) { $1 }
            // Rows already on screen won't ask again, so the pages they asked for reload now.
            let shown = requestedPages.subtracting([0])
            requestedPages = [0]
            for page in shown {
                loadListings(forRow: page * Self.pageSize)
            }
            if window.duration == 0 || window.start < guide.start {
                window = guide.window(from: guide.start, length: LiveTVLayout.windowLength)
            }
            state = channels.isEmpty ? .noChannels : .loaded
        } catch {
            guard let problem = browse.problem(with: error, doing: "load the guide from \(browse.server.name)")
            else { return }
            if state != .loaded {
                state = .failed(problem)
            }
        }
    }

    /// Loads the listings for the page of channels holding `index`, if they haven't been asked
    /// for; rows call it as they come on screen.
    func loadListings(forRow index: Int) {
        let page = index / Self.pageSize
        guard state == .loaded, !requestedPages.contains(page) else { return }
        requestedPages.insert(page)
        Task {
            await loadListings(page: page)
        }
    }

    /// Loads one channel's listings again, after a recording was set or cancelled, so its
    /// markers change.
    func reloadListings(forChannel channelID: LiveTVChannel.ID) async {
        guard let channel = channels.first(where: { $0.id == channelID }) else { return }
        if let programs = try? await listings(for: [channel], in: guide) {
            rows.merge(Self.rows(for: [channel], programs: programs, in: guide)) { $1 }
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

    private func loadListings(page: Int) async {
        let channels = Array(channels.dropFirst(page * Self.pageSize).prefix(Self.pageSize))
        guard !channels.isEmpty else { return }
        do {
            let programs = try await listings(for: channels, in: guide)
            rows.merge(Self.rows(for: channels, programs: programs, in: guide)) { $1 }
        } catch {
            // Rows show no data; the page is asked for again when the guide next loads.
            requestedPages.remove(page)
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
