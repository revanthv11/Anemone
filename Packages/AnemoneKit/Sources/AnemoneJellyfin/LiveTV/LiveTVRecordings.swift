import Foundation
import JellyfinAPI
import os

extension LiveTVRecording {
    static let log = Logger(subsystem: "com.revanthv11.anemone", category: "LiveTV")

    /// The server adds its timer's times, IDs and programme details to a recording under way,
    /// which it reads as a programme would be. Only watching the channel would need the channel,
    /// so a recording without one is still listed.
    ///
    /// Jellyfin sends the times with every recording under way, but should one come without
    /// them, its `timer`'s stand in, or else its start and its own length. One with neither is
    /// left out, and the log says so.
    init?(_ dto: BaseItemDto, timer: LiveTVTimer? = nil) {
        guard let id = dto.id else { return nil }
        var programDto = dto
        programDto.id = dto.programID ?? id
        programDto.channelID = dto.channelID ?? timer?.program.channelID ?? ""
        programDto.startDate = dto.startDate ?? timer?.program.start
        programDto.endDate = dto.endDate ?? timer?.program.end ?? programDto.startDate.flatMap { start in
            // Ticks are 100 ns.
            dto.runTimeTicks.map { start.addingTimeInterval(TimeInterval($0) / 10_000_000) }
        }
        guard var program = LiveTVProgram(programDto) else {
            Self.log.warning("Recording \(id, privacy: .public) is left out: it came without times or a timer's.")
            return nil
        }
        // The artwork is the recording's.
        program.image = ItemImage(itemID: id, kind: .primary, tag: dto.imageTags?[ImageType.primary.rawValue])
        self.init(id: id, program: program)
    }
}

extension JellyfinSession {
    /// The recordings under way in `dtos`. The server gives each its timer's times; should one
    /// come without them, its timer is asked for, so it's listed with the timer's times rather
    /// than left out.
    func recordingsWithTimes(_ dtos: [BaseItemDto]) async -> [LiveTVRecording] {
        var timers: [String: LiveTVTimer] = [:]
        let timerIDs = dtos.filter { $0.startDate == nil || $0.endDate == nil }.compactMap(\.timerID)
        for timerID in Set(timerIDs) {
            timers[timerID] = try? await LiveTVTimer(send(Paths.getTimer(timerID: timerID)))
        }
        return dtos.compactMap { LiveTVRecording($0, timer: $0.timerID.flatMap { timers[$0] }) }
    }
}
