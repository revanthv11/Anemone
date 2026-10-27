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
    /// them, its `timer`'s own start and end stand in, widened by the timer's padding: that's
    /// when the server records, so the recording reads as under way, and can be cancelled, until
    /// the server stops it. The programme's times stand in only for a timer without its own.
    /// A recording's length counts only for a finished one: one under way has the length recorded
    /// so far, which would make it end about now. One with none of these is left out, and the
    /// log says so.
    init?(_ dto: BaseItemDto, timer: TimerInfoDto? = nil) {
        guard let id = dto.id else { return nil }
        var programDto = dto
        programDto.id = dto.programID ?? id
        programDto.channelID = dto.channelID ?? timer?.channelID ?? timer?.programInfo?.channelID ?? ""
        let start = dto.startDate ?? timer?.recordingStart
        programDto.startDate = start
        programDto.endDate = dto.endDate ?? timer?.recordingEnd ?? Self.finishedEnd(of: dto, start: start)
        guard var program = LiveTVProgram(programDto) else {
            Self.log.warning("Recording \(id, privacy: .public) is left out: it came without times or a timer's.")
            return nil
        }
        // The artwork is the recording's.
        program.image = ItemImage(itemID: id, kind: .primary, tag: dto.imageTags?[ImageType.primary.rawValue])
        self.init(id: id, program: program)
    }

    /// A finished recording's start plus its length.
    private static func finishedEnd(of dto: BaseItemDto, start: Date?) -> Date? {
        guard dto.status == RecordingStatus.completed.rawValue, let start, let ticks = dto.runTimeTicks else {
            return nil
        }
        // Ticks are 100 ns.
        return start.addingTimeInterval(TimeInterval(ticks) / 10_000_000)
    }
}

private extension TimerInfoDto {
    /// When the server starts recording: the timer's start less its pre-padding.
    var recordingStart: Date? {
        (startDate ?? programInfo?.startDate)?.addingTimeInterval(-TimeInterval(prePaddingSeconds ?? 0))
    }

    /// When the server stops recording: the timer's end plus its post-padding.
    var recordingEnd: Date? {
        (endDate ?? programInfo?.endDate)?.addingTimeInterval(TimeInterval(postPaddingSeconds ?? 0))
    }
}

extension JellyfinSession {
    /// The recordings under way in `dtos`. The server gives each its timer's times; should one
    /// come without them, its timer is asked for, so it's listed with the timer's times rather
    /// than left out.
    func recordingsWithTimes(_ dtos: [BaseItemDto]) async -> [LiveTVRecording] {
        await LiveTVRecording.withTimes(dtos) { [self] timerID in
            try? await send(Paths.getTimer(timerID: timerID))
        }
    }
}

extension LiveTVRecording {
    /// How many timers are asked for at once.
    static let timerRequestWidth = 4

    /// `dtos` as recordings, asking `timer` for the timers of those without times: each once,
    /// a few at a time.
    static func withTimes(
        _ dtos: [BaseItemDto],
        timer: @escaping @Sendable (String) async -> TimerInfoDto?,
    ) async -> [LiveTVRecording] {
        let untimed = dtos.filter { $0.startDate == nil || $0.endDate == nil }
        // In the order they came, without repeats.
        let timerIDs = untimed.compactMap(\.timerID).reduce(into: [String]()) { ids, id in
            if !ids.contains(id) {
                ids.append(id)
            }
        }
        let found = await boundedMap(timerIDs.count, width: timerRequestWidth) { index in
            await (timerIDs[index], timer(timerIDs[index]))
        }
        let timers = Dictionary(found.compactMap { id, timer in timer.map { (id, $0) } }) { first, _ in first }
        return dtos.compactMap { LiveTVRecording($0, timer: $0.timerID.flatMap { timers[$0] }) }
    }
}
