import Foundation
import JellyfinAPI

/// A Live TV channel, as the guide and the channel list show it. Ported from Wholphin's
/// `TvChannel`.
public struct LiveTVChannel: Hashable, Identifiable, Sendable {
    public let id: String
    public var name: String
    /// The tuner's number for it, such as "4" or "4.1"; text, since tuners number channels their
    /// own way.
    public var number: String?
    /// The channel's logo.
    public var image: ItemImage?
    public var isFavorite: Bool
    /// What's on now, when the channels were asked for with it.
    public var currentProgram: LiveTVProgram?

    public init(
        id: String,
        name: String,
        number: String? = nil,
        image: ItemImage? = nil,
        isFavorite: Bool = false,
        currentProgram: LiveTVProgram? = nil,
    ) {
        self.id = id
        self.name = name
        self.number = number
        self.image = image
        self.isFavorite = isFavorite
        self.currentProgram = currentProgram
    }

    /// The number and the name, such as "4 Anemone Kids".
    public var title: String {
        [number, name].compactMap(\.self).joined(separator: " ")
    }
}

/// A programme in the guide, or a stretch of it with nothing listed. Ported from Wholphin's
/// `TvProgram`.
public struct LiveTVProgram: Hashable, Identifiable, Sendable {
    /// The categories Wholphin colours programmes by, in the order it checks them.
    public enum Category: Hashable, Sendable {
        case kids
        case movie
        case news
        case sports
    }

    public let id: String
    public let channelID: String
    public var channelName: String?
    /// The series' name for episodes, as Wholphin's guide shows it.
    public var name: String
    /// An episode's own title.
    public var episodeTitle: String?
    public var overview: String?
    public var start: Date
    public var end: Date
    public var seasonNumber: Int?
    public var episodeNumber: Int?
    /// The age rating, such as "TV-PG".
    public var officialRating: String?
    public var category: Category?
    public var isSeries: Bool
    public var isRepeat: Bool
    /// Set while a recording of the programme is scheduled or under way.
    public var timerID: String?
    /// Set when the programme's series is set to record.
    public var seriesTimerID: String?
    public var image: ItemImage?
    /// A stretch of the guide with nothing listed, which Wholphin shows as "No data".
    public var isPlaceholder: Bool

    public init(
        id: String,
        channelID: String,
        name: String,
        start: Date,
        end: Date,
        episodeTitle: String? = nil,
        overview: String? = nil,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        category: Category? = nil,
        isSeries: Bool = false,
        timerID: String? = nil,
        seriesTimerID: String? = nil,
        isPlaceholder: Bool = false,
    ) {
        self.id = id
        self.channelID = channelID
        self.name = name
        self.start = start
        self.end = end
        self.episodeTitle = episodeTitle
        self.overview = overview
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.category = category
        self.isSeries = isSeries
        isRepeat = false
        self.timerID = timerID
        self.seriesTimerID = seriesTimerID
        self.isPlaceholder = isPlaceholder
    }

    public var duration: Duration {
        .seconds(end.timeIntervalSince(start))
    }

    public func isAiring(at date: Date) -> Bool {
        start <= date && date < end
    }

    /// "S1:E3" when both numbers are known.
    public var episodeLabel: String? {
        guard let seasonNumber, let episodeNumber else { return nil }
        return "S\(seasonNumber):E\(episodeNumber)"
    }

    /// The episode label and title, as under a programme's name in Wholphin's guide.
    public var subtitle: String? {
        let parts = [episodeLabel, episodeTitle].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " - ")
    }
}

/// A recording the server has scheduled or is making.
public struct LiveTVTimer: Hashable, Identifiable, Sendable {
    public let id: String
    /// What it records, with `timerID` set to this timer.
    public var program: LiveTVProgram
    public var isInProgress: Bool

    public init(id: String, program: LiveTVProgram, isInProgress: Bool = false) {
        self.id = id
        self.program = program
        self.isInProgress = isInProgress
    }
}

/// A recording under way. Wholphin's schedule lists these from the server's recordings rather
/// than its timers, so each is an item that plays what has been recorded so far.
public struct LiveTVRecording: Hashable, Identifiable, Sendable {
    /// The recording's own item, which plays it.
    public let id: String
    /// What's being recorded: its name, channel and times, and the timers recording it.
    public var program: LiveTVProgram

    public init(id: String, program: LiveTVProgram) {
        self.id = id
        self.program = program
    }
}

/// A series the server records whenever it airs.
public struct LiveTVSeriesTimer: Hashable, Identifiable, Sendable {
    public let id: String
    public var name: String
    public var channelName: String?
    public var recordsAnyChannel: Bool
    public var recordsAnyTime: Bool
    public var recordsNewOnly: Bool

    public init(
        id: String,
        name: String,
        channelName: String? = nil,
        recordsAnyChannel: Bool = false,
        recordsAnyTime: Bool = false,
        recordsNewOnly: Bool = false,
    ) {
        self.id = id
        self.name = name
        self.channelName = channelName
        self.recordsAnyChannel = recordsAnyChannel
        self.recordsAnyTime = recordsAnyTime
        self.recordsNewOnly = recordsNewOnly
    }
}

/// The DVR schedule: what's recording, what will record, and the series set to record. Wholphin's
/// `DvrSchedule` shows the first two; the series are listed here so they can be cancelled too.
public struct LiveTVSchedule: Hashable, Sendable {
    public var active: [LiveTVRecording]
    public var scheduled: [LiveTVTimer]
    public var series: [LiveTVSeriesTimer]

    public init(active: [LiveTVRecording] = [], scheduled: [LiveTVTimer] = [], series: [LiveTVSeriesTimer] = []) {
        self.active = active
        self.scheduled = scheduled
        self.series = series
    }

    public var isEmpty: Bool {
        active.isEmpty && scheduled.isEmpty && series.isEmpty
    }

    /// Scheduled recordings by the day they start, earliest first, as Wholphin lists them.
    public func scheduledByDay(calendar: Calendar = .current) -> [(day: Date, timers: [LiveTVTimer])] {
        let days = Dictionary(grouping: scheduled) { calendar.startOfDay(for: $0.program.start) }
        return days.keys.sorted().map { day in
            (day, days[day, default: []].sorted { $0.program.start < $1.program.start })
        }
    }
}

// MARK: From the server's types

extension LiveTVChannel {
    init?(_ dto: BaseItemDto) {
        guard let id = dto.id else { return nil }
        self.init(
            id: id,
            name: dto.channelName ?? dto.name ?? "",
            number: dto.channelNumber ?? dto.number,
            image: ItemImage(itemID: id, kind: .primary, tag: dto.imageTags?[ImageType.primary.rawValue]),
            isFavorite: dto.userData?.isFavorite == true,
            currentProgram: dto.currentProgram.flatMap(LiveTVProgram.init),
        )
    }
}

extension LiveTVProgram {
    /// Like Wholphin, a programme's name is its series' name when it has one, with runs of
    /// whitespace (newlines included) collapsed, and the episode title shows only for series.
    init?(_ dto: BaseItemDto) {
        guard let id = dto.id, let channelID = dto.channelID, let start = dto.startDate, let end = dto.endDate else {
            return nil
        }
        let isSeries = dto.isSeries == true
        self.init(
            id: id,
            channelID: channelID,
            name: (dto.seriesName ?? dto.name).map(Self.collapsingWhitespace) ?? "",
            start: start,
            end: end,
            episodeTitle: isSeries ? dto.episodeTitle.map(Self.collapsingWhitespace) : nil,
            overview: dto.overview,
            seasonNumber: dto.parentIndexNumber,
            episodeNumber: dto.indexNumber,
            category: Category(dto),
            isSeries: isSeries,
            timerID: dto.timerID.nonBlank,
            seriesTimerID: dto.seriesTimerID.nonBlank,
        )
        channelName = dto.channelName
        officialRating = dto.officialRating
        isRepeat = dto.isRepeat == true
        image = ItemImage(itemID: id, kind: .primary, tag: dto.imageTags?[ImageType.primary.rawValue])
        // Wholphin's guide needs both numbers to show either.
        if dto.indexNumber == nil || dto.parentIndexNumber == nil {
            seasonNumber = nil
            episodeNumber = nil
        }
    }

    static func collapsingWhitespace(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

extension LiveTVProgram.Category {
    init?(_ dto: BaseItemDto) {
        if dto.isKids == true {
            self = .kids
        } else if dto.isMovie == true {
            self = .movie
        } else if dto.isNews == true {
            self = .news
        } else if dto.isSports == true {
            self = .sports
        } else {
            return nil
        }
    }
}

extension LiveTVTimer {
    /// Built from the programme the timer records when the server sends it; a timer set by time
    /// alone has none, which Wholphin's schedule crashes on (`programInfo!!`), so its own name and
    /// times stand in.
    init?(_ dto: TimerInfoDto) {
        guard let id = dto.id else { return nil }
        var program = dto.programInfo.flatMap(LiveTVProgram.init)
        if program == nil, let channelID = dto.channelID, let start = dto.startDate, let end = dto.endDate {
            program = LiveTVProgram(
                id: dto.programID ?? id,
                channelID: channelID,
                name: dto.name ?? "",
                start: start,
                end: end,
                overview: dto.overview,
            )
        }
        guard var program else { return nil }
        program.timerID = id
        program.seriesTimerID = dto.seriesTimerID.nonBlank ?? program.seriesTimerID
        program.channelName = program.channelName ?? dto.channelName
        self.init(id: id, program: program, isInProgress: dto.status == .inProgress)
    }
}

extension LiveTVRecording {
    /// The server adds its timer's times, IDs and programme details to a recording under way,
    /// which it reads as a programme would be. Only watching the channel would need the channel,
    /// so a recording without one is still listed.
    init?(_ dto: BaseItemDto) {
        guard let id = dto.id else { return nil }
        var programDto = dto
        programDto.id = dto.programID ?? id
        programDto.channelID = dto.channelID ?? ""
        guard var program = LiveTVProgram(programDto) else { return nil }
        // The artwork is the recording's.
        program.image = ItemImage(itemID: id, kind: .primary, tag: dto.imageTags?[ImageType.primary.rawValue])
        self.init(id: id, program: program)
    }
}

extension LiveTVSeriesTimer {
    init?(_ dto: SeriesTimerInfoDto) {
        guard let id = dto.id else { return nil }
        self.init(
            id: id,
            name: dto.name ?? "",
            channelName: dto.channelName,
            recordsAnyChannel: dto.isRecordAnyChannel == true,
            recordsAnyTime: dto.isRecordAnyTime == true,
            recordsNewOnly: dto.isRecordNewOnly == true,
        )
    }
}

private extension String? {
    /// `nil` for empty or blank text, as Wholphin's `isNotNullOrBlank` checks timer IDs.
    var nonBlank: String? {
        guard let self, !self.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return self
    }
}
