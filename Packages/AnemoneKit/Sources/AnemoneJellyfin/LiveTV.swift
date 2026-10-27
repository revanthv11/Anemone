import Foundation
import JellyfinAPI

/// How the guide and channel list order channels: Wholphin's "Favorite channels at beginning" and
/// "Sort channels by recently watched" options.
public struct LiveTVChannelOrder: Hashable, Sendable {
    public var favoritesFirst: Bool
    public var recentlyWatchedFirst: Bool

    public init(favoritesFirst: Bool = true, recentlyWatchedFirst: Bool = false) {
        self.favoritesFirst = favoritesFirst
        self.recentlyWatchedFirst = recentlyWatchedFirst
    }
}

/// Live TV: channels, the guide, recording and the DVR schedule. Ported from Wholphin's
/// `LiveTvService`, `LiveTvViewModel`, `DvrScheduleViewModel` and `LiveTvCollectionViewModel`.
public extension JellyfinSession {
    /// The user's channels, in the guide's order, as Wholphin's guide asks for them.
    ///
    /// - Parameter includesCurrentProgram: also sends what each channel has on now, for the
    ///   channel list.
    func liveTVChannels(
        order: LiveTVChannelOrder = LiveTVChannelOrder(),
        includesCurrentProgram: Bool = false,
        limit: Int? = nil,
    ) async throws -> [LiveTVChannel] {
        let parameters = Paths.GetLiveTvChannelsParameters(
            userID: userID,
            startIndex: 0,
            limit: limit,
            enableImages: true,
            imageTypeLimit: 1,
            enableImageTypes: [.primary],
            enableUserData: true,
            sortBy: order.recentlyWatchedFirst ? [.datePlayed] : nil,
            sortOrder: order.recentlyWatchedFirst ? .descending : nil,
            enableFavoriteSorting: order.favoritesFirst,
            isAddCurrentProgram: includesCurrentProgram,
        )
        let result = try await send(Paths.getLiveTvChannels(parameters: parameters))
        return (result.items ?? []).compactMap(LiveTVChannel.init)
    }

    /// The listings for `channelIDs` that overlap `guide`, earliest first: Wholphin's
    /// `fetchPrograms` request, which asks for programmes starting before the guide's last minute
    /// and ending after its first.
    func liveTVPrograms(channelIDs: [LiveTVChannel.ID], in guide: LiveTVGuide) async throws -> [LiveTVProgram] {
        let request = GetProgramsDto(
            channelIDs: channelIDs,
            enableImageTypes: [.primary],
            enableImages: true,
            enableTotalRecordCount: false,
            fields: [.overview],
            imageTypeLimit: 1,
            maxStartDate: guide.end.addingTimeInterval(-60),
            minEndDate: guide.start.addingTimeInterval(60),
            sortBy: [.startDate],
            userID: userID,
        )
        let result = try await send(Paths.getPrograms(request))
        return (result.items ?? []).compactMap(LiveTVProgram.init).filter { $0.end > guide.start }
    }

    /// One programme, with whether it's set to record: what Wholphin's programme dialog loads.
    func liveTVProgram(id: LiveTVProgram.ID) async throws -> LiveTVProgram {
        guard let program = try await LiveTVProgram(send(Paths.getProgram(programID: id, userID: userID))) else {
            throw SessionError.unexpectedResponse
        }
        return program
    }

    /// Records a programme, or every episode of its series, ported from Wholphin's
    /// `LiveTvService.record`. Starts from the server's default timer for the programme, so the
    /// padding and keep-until settings from the server's DVR settings apply.
    func record(programID: LiveTVProgram.ID, series: Bool) async throws {
        let defaults = try await send(Paths.getDefaultTimer(programID: programID))
        if series {
            try await send(Paths.createSeriesTimer(defaults))
        } else {
            try await send(Paths.createTimer(TimerInfoDto(defaults)))
        }
    }

    /// Cancels a recording, or a series' recordings, ported from Wholphin's
    /// `LiveTvService.cancelRecording`.
    func cancelRecording(timerID: String, series: Bool) async throws {
        try await send(series ? Paths.cancelSeriesTimer(timerID: timerID) : Paths.cancelTimer(timerID: timerID))
    }

    /// What's recording, what's scheduled, and the series set to record. As in Wholphin's
    /// `DvrScheduleViewModel`, what's recording comes from the recordings under way (the first
    /// 100), which play, and what's scheduled from the timers.
    func liveTVSchedule() async throws -> LiveTVSchedule {
        let recordings = Paths.GetRecordingsParameters(
            userID: userID,
            limit: 100,
            isInProgress: true,
            fields: [.overview, .sortName, .mediaSourceCount, .canDelete],
        )
        async let active = send(Paths.getRecordings(parameters: recordings))
        async let scheduled = send(Paths.getTimers(parameters: .init(isActive: false, isScheduled: true)))
        async let series = send(Paths.getSeriesTimers())
        return try await LiveTVSchedule(
            active: (active.items ?? []).compactMap(LiveTVRecording.init),
            scheduled: (scheduled.items ?? []).compactMap(LiveTVTimer.init),
            series: (series.items ?? []).compactMap(LiveTVSeriesTimer.init),
        )
    }

    /// The folders recordings are kept in, each a tab of the Live TV page as in Wholphin.
    func liveTVRecordingFolders() async throws -> [Library] {
        try await (send(Paths.getRecordingFolders(userID: userID)).items ?? []).compactMap { dto in
            var folder = Library(dto)
            folder?.isRecordingFolder = true
            return folder
        }
    }

    /// Releases a live stream the server opened for playback (`isAutoOpenLiveStream`), so the
    /// tuner is free again.
    func closeLiveStream(id: String) async throws {
        try await send(Paths.closeLiveStream(liveStreamID: id))
    }

    /// Home's Live TV rows for this user.
    var liveTVHomeRows: any HomeLiveTVSource {
        LiveTVHomeRows(session: self)
    }
}

/// Home's Watch Live, Channels and Active Recordings rows, with the requests Wholphin's
/// `HomeDataService` makes for them.
struct LiveTVHomeRows: HomeLiveTVSource {
    let session: JellyfinSession

    func recordingsInProgress(limit: Int) async throws -> [MediaItem] {
        let parameters = Paths.GetRecordingsParameters(
            userID: session.userID,
            limit: limit,
            isInProgress: true,
            enableImages: true,
            imageTypeLimit: 1,
            fields: Self.fields,
            enableUserData: true,
        )
        return try await (session.send(Paths.getRecordings(parameters: parameters)).items ?? [])
            .compactMap(MediaItem.init)
    }

    func programsOnNow(limit: Int) async throws -> [MediaItem] {
        let request = GetProgramsDto(
            enableImageTypes: [.primary, .logo],
            enableImages: true,
            enableUserData: true,
            fields: Self.fields + [.channelInfo],
            imageTypeLimit: 1,
            isAiring: true,
            limit: limit,
            minEndDate: Date.now.addingTimeInterval(60),
            userID: session.userID,
        )
        return try await (session.send(Paths.getPrograms(request)).items ?? []).compactMap(MediaItem.init)
    }

    func channels(limit: Int) async throws -> [MediaItem] {
        let parameters = Paths.GetLiveTvChannelsParameters(
            userID: session.userID,
            limit: limit,
            enableImages: true,
            fields: Self.fields,
        )
        return try await (session.send(Paths.getLiveTvChannels(parameters: parameters)).items ?? [])
            .compactMap(MediaItem.init)
    }

    /// Wholphin's `HomeItemFields`.
    private static let fields: [ItemFields] = [.overview, .canDelete]
}

private extension TimerInfoDto {
    /// A timer for one programme from the server's defaults, field for field as Wholphin copies
    /// them.
    init(_ defaults: SeriesTimerInfoDto) {
        self.init(
            channelID: defaults.channelID,
            channelName: defaults.channelName,
            endDate: defaults.endDate,
            externalChannelID: defaults.externalChannelID,
            externalID: defaults.externalID,
            externalProgramID: defaults.externalProgramID,
            id: defaults.id,
            isPostPaddingRequired: defaults.isPostPaddingRequired,
            isPrePaddingRequired: defaults.isPrePaddingRequired,
            keepUntil: defaults.keepUntil,
            name: defaults.name,
            overview: defaults.overview,
            postPaddingSeconds: defaults.postPaddingSeconds,
            prePaddingSeconds: defaults.prePaddingSeconds,
            priority: defaults.priority,
            programID: defaults.programID,
            serverID: defaults.serverID,
            serviceName: defaults.serviceName,
            startDate: defaults.startDate,
            type: defaults.type,
        )
    }
}
