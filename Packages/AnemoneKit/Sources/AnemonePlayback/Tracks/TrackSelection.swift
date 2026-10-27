import AnemoneCore
import AnemoneJellyfin
import Foundation

/// Chooses each entry's audio and subtitles before the server is asked for a stream, offers
/// Audio and Subtitles menus in the player, and remembers what the user picks for the item and,
/// for episodes, its season and series. Ported from Wholphin's `StreamChoiceService` and the
/// track parts of its `PlaybackViewModel` and `ItemPlaybackRepository`.
///
/// A switch the stream can make on its own happens at once: audio in a file that plays
/// directly, and text subtitles, which the server sends AVPlayer as files of their own for
/// Anemone to draw (`DrawnSubtitles`). MPV shows such files itself (`MPVExternalSubtitles`), so
/// while it plays they're its tracks, as they were before Anemone drew any. Anything else asks
/// the server for another stream and goes on from the same position, as Wholphin's
/// `changeStreams` does.
///
/// Live TV is left to the server, as Wholphin and Swiftfin leave it: the request names no
/// version or tracks, and the menus offer what the live stream can switch to by itself.
@MainActor
public final class TrackSelection: PlaybackFeature {
    /// What the feature asks the server; tests stand in for it.
    struct Server: Sendable {
        var itemTracks: @Sendable (MediaItem.ID) async throws -> ItemTracks
        var profileSettings: @Sendable () async throws -> ProfileTrackSettings
        /// The version picked on the item's page, if any.
        var pickedVersion: @Sendable (MediaItem.ID) -> String? = { _ in nil }
    }

    /// The entry playing: its tracks and what plays.
    struct Entry {
        let itemID: MediaItem.ID
        var seriesID: String?
        var seasonID: String?
        var mediaSourceID: String?
        var tracks: [MediaTrack]
        var audio: MediaTrack?
        /// What the Subtitles menu shows as picked.
        var subtitleChoice: SubtitleChoice
        /// The subtitles that show; for "Only forced", the track it stands for now.
        var subtitle: MediaTrack?
        var stream: PlaybackStream?
        /// A live channel, whose tracks are what its live stream reports.
        var isLive = false
    }

    /// AVPlayer shows ASS and SSA subtitles as plain text, so the server burns them in. An engine
    /// that draws them itself, as MPV will (Phase 4), turns this off.
    public var burnsInStyledSubtitles = true

    private let server: Server
    let store: TrackChoiceStore
    private let defaults: UserDefaults
    /// The Jellyfin profile's settings, fetched once per player.
    private var profile: ProfileTrackSettings?
    var entry: Entry?
    /// Counts fetches of tracks, so one a newer fetch replaced doesn't leave its item as the entry.
    private var fetches = 0
    /// Selecting the chosen tracks in a stream that just loaded.
    var applying: Task<Void, Never>?

    public convenience init(session: JellyfinSession, defaults: UserDefaults = .standard) {
        self.init(
            server: Server(
                itemTracks: { try await session.itemTracks(for: $0) },
                profileSettings: { try await session.profileTrackSettings() },
                // The choices playback goes by, as `playbackStream(forPickedVersionOf:)` reads them.
                pickedVersion: { MediaVersionChoices.current.choice(for: $0, userID: session.userID) },
            ),
            store: TrackChoiceStore(userID: session.userID, defaults: defaults),
            defaults: defaults,
        )
    }

    init(server: Server, store: TrackChoiceStore, defaults: UserDefaults) {
        self.server = server
        self.store = store
        self.defaults = defaults
    }

    /// Asks the server for the tracks chosen for the entry, with each request for a stream.
    public func prepare(_ request: inout StreamRequest) async {
        guard let tracks = await self.request(for: request.itemID, mediaSourceID: request.mediaSourceID) else {
            return
        }
        tracks.apply(to: &request)
    }

    /// The tracks to ask for, with their version: `mediaSourceID`, else the one picked on the item's
    /// page while the item has it, else the first. `nil` leaves them to the server, as when the
    /// tracks can't be fetched or for live TV. A retry or a switch for the same item asks for
    /// what's chosen now.
    func request(for itemID: MediaItem.ID, mediaSourceID: String?) async -> TrackRequest? {
        if let entry, entry.itemID == itemID {
            return entry.isLive ? nil : request(for: entry)
        }
        entry = nil
        fetches += 1
        let fetch = fetches
        async let fetchedProfile = Self.profile(profile, from: server)
        let picked = mediaSourceID == nil ? server.pickedVersion(itemID) : nil
        guard let item = try? await server.itemTracks(itemID) else { return nil }
        // A channel's version is a placeholder until the server opens its live stream, and the
        // server reads track indices only with the version.
        guard !item.isLive else {
            if fetch == fetches {
                entry = Entry(itemID: itemID, tracks: [], subtitleChoice: .off, isLive: true)
            }
            return nil
        }
        guard let source = picked.flatMap({ item.source($0) }) ?? item.source(mediaSourceID) else { return nil }
        profile = await fetchedProfile
        let entry = choose(in: item, source: source)
        if fetch == fetches {
            self.entry = entry
        }
        return request(for: entry)
    }

    public func handle(_ event: PlaybackEvent, in controller: PlaybackController) async {
        switch event {
        case let .loaded(stream, queued):
            loaded(stream, itemID: queued.itemID, in: controller)
        case let .reloaded(stream):
            loaded(stream, itemID: controller.queue.current.itemID, in: controller)
        case .started:
            await reselectSubtitles(in: controller.engine)
        default:
            break
        }
    }

    // MARK: Choosing

    private var preferences: TrackPreferences {
        TrackPreferences.current(profile: profile ?? ProfileTrackSettings(), in: defaults)
    }

    private nonisolated static func profile(
        _ known: ProfileTrackSettings?,
        from server: Server,
    ) async -> ProfileTrackSettings? {
        if let known {
            return known
        }
        return try? await server.profileSettings()
    }

    private func choose(in item: ItemTracks, source: ItemTracks.Source) -> Entry {
        let tracks = source.tracks
        let picked = store.itemChoice(for: item.itemID).flatMap { $0.mediaSourceID == source.id ? $0 : nil }
        let preferences = preferences
        let audio = StreamChoice.audio(
            in: tracks,
            item: picked,
            remembered: store.seriesChoices(.audio, seriesID: item.seriesID, seasonID: item.seasonID),
            preferences: preferences,
        )
        // Wholphin loads these with the audio type (`PlaybackViewModel.kt` 499-503), so a
        // subtitle choice never carries over to the next episode. These are the subtitle ones.
        let subtitle = StreamChoice.subtitle(
            in: tracks,
            audioLanguage: audio.track?.language,
            item: picked,
            remembered: store.seriesChoices(.subtitle, seriesID: item.seriesID, seasonID: item.seasonID),
            preferences: preferences,
        )
        return Entry(
            itemID: item.itemID,
            seriesID: item.seriesID,
            seasonID: item.seasonID,
            mediaSourceID: source.id,
            tracks: tracks,
            audio: audio.track,
            // "Only forced" stays a choice of its own, so it's found again when the audio changes.
            subtitleChoice: subtitle.isOnlyForced ? .onlyForced : subtitle.track.choice,
            subtitle: subtitle.track,
        )
    }

    private func request(for entry: Entry) -> TrackRequest {
        TrackRequest(
            mediaSourceID: entry.mediaSourceID,
            audioIndex: entry.audio?.index,
            subtitleIndex: entry.subtitle?.index,
            burnsInSubtitles: burnsInStyledSubtitles && entry.subtitle?.isStyledText == true,
        )
    }

    /// Takes in what the server sent: its tracks say how each subtitle comes.
    private func loaded(_ stream: PlaybackStream, itemID: MediaItem.ID, in controller: PlaybackController) {
        var entry = entry.flatMap { $0.itemID == itemID ? $0 : nil } ?? Self.entry(for: stream)
        if entry.isLive {
            entry = Self.entry(for: stream, isLive: true)
        } else if !stream.tracks.isEmpty {
            entry.tracks = stream.tracks
            entry.audio = entry.audio.flatMap { stream.tracks.of(.audio).first(id: $0.id) }
            entry.subtitle = entry.subtitle.flatMap { stream.tracks.of(.subtitle).first(id: $0.id) }
        }
        entry.stream = stream
        self.entry = entry
        showMenus(in: controller)
        applying?.cancel()
        applying = Task { [weak self, weak controller] in
            guard let controller else { return }
            await self?.select(in: controller, for: stream)
        }
    }

    /// When the tracks couldn't be chosen beforehand, or for live TV: what the server picked.
    private static func entry(for stream: PlaybackStream, isLive: Bool = false) -> Entry {
        let subtitle = stream.subtitleStreamIndex.flatMap { stream.tracks.of(.subtitle).first(id: $0) }
        return Entry(
            itemID: stream.itemID,
            mediaSourceID: stream.mediaSourceID,
            tracks: stream.tracks,
            audio: stream.audioStreamIndex.flatMap { stream.tracks.of(.audio).first(id: $0) },
            subtitleChoice: subtitle.choice,
            subtitle: subtitle,
            isLive: isLive,
        )
    }

    /// Whether Anemone draws the text subtitles the server sends as files of their own: over
    /// AVPlayer. MPV adds those files to its own tracks and shows them itself, so drawing them
    /// too would show every line twice.
    static func drawsFiles(in engine: any PlayerEngine) -> Bool {
        engine.mpv == nil
    }

    /// Has text subtitles that come as a file of their own drawn over AVPlayer, and selects the
    /// chosen tracks in the engine where it lists them, turning off subtitles the player would
    /// otherwise pick by itself.
    func select(in controller: PlaybackController, for stream: PlaybackStream) async {
        guard let entry, entry.stream == stream else { return }
        let engine = controller.engine
        let drawsFiles = Self.drawsFiles(in: engine)
        let drawn = entry.subtitle.flatMap { drawsFiles && TrackSwitching.isSentAsFile($0, in: stream) ? $0 : nil }
        controller.feature(DrawnSubtitles.self)?.show(drawn, in: stream)
        if stream.method == .directPlay, let audio = entry.audio {
            let options = await engine.tracks(.audio)
            guard !Task.isCancelled, self.entry?.stream == stream else { return }
            if let option = TrackSwitching.playerTrack(for: audio, in: stream, options: options), !option.isSelected {
                await engine.select(option, .audio)
            }
        }
        let options = await engine.tracks(.subtitle)
        guard !Task.isCancelled, self.entry?.stream == stream else { return }
        let wanted = drawn == nil
            ? entry.subtitle.flatMap {
                TrackSwitching.playerTrack(for: $0, in: stream, options: options, drawsFiles: drawsFiles)
            }
            : nil
        if wanted?.id != options.first(where: \.isSelected)?.id {
            await engine.select(wanted, .subtitle)
        }
    }

    /// AVPlayer showed no HLS subtitles that were selected before playback got under way, the
    /// server's default included, until they were selected again; so they are, once it has.
    private func reselectSubtitles(in engine: any PlayerEngine) async {
        let drawsFiles = Self.drawsFiles(in: engine)
        guard let entry, let stream = entry.stream, let subtitle = entry.subtitle,
              !(drawsFiles && TrackSwitching.isSentAsFile(subtitle, in: stream))
        else { return }
        let options = await engine.tracks(.subtitle)
        guard self.entry?.stream == stream,
              let wanted = TrackSwitching.playerTrack(
                  for: subtitle,
                  in: stream,
                  options: options,
                  drawsFiles: drawsFiles,
              )
        else { return }
        await engine.select(nil, .subtitle)
        await engine.select(wanted, .subtitle)
    }
}

/// The menus.
extension TrackSelection {
    func showMenus(in controller: PlaybackController) {
        guard let entry else { return }
        let drawsFiles = Self.drawsFiles(in: controller.engine)
        let audio = entry.tracks.of(.audio).filter { offers($0, in: entry, drawsFiles: drawsFiles) }
        if audio.count > 1 {
            let options = audio.map { track in
                option(
                    "audio.\(track.index)",
                    track.menuTitle,
                    track.id == entry.audio?.id,
                    controller,
                ) { entry, prefs in
                    entry.audio = track
                    // "Only forced" follows the audio's language.
                    if entry.subtitleChoice == .onlyForced {
                        entry.subtitle = StreamChoice.onlyForced(
                            in: entry.tracks,
                            audioLanguage: track.language,
                            preferences: prefs,
                        )
                    }
                }
            }
            controller.accessories.show(PlayerMenu(
                id: "audio",
                title: "Audio",
                systemImage: "speaker.wave.2",
                options: options,
            ))
        } else {
            controller.accessories.removeMenu("audio")
        }
        let subtitles = entry.tracks.of(.subtitle).filter { offers($0, in: entry, drawsFiles: drawsFiles) }
        guard !subtitles.isEmpty else {
            controller.accessories.removeMenu("subtitles")
            return
        }
        var options = [subtitleOption("subtitles.off", "Off", .off, controller)]
        if !entry.isLive, subtitles.contains(where: \.isForcedOrSigns) {
            options.append(subtitleOption("subtitles.forced", "Only forced", .onlyForced, controller))
        }
        options += subtitles.map { track in
            subtitleOption("subtitles.\(track.index)", track.menuTitle, .track(index: track.index), controller)
        }
        controller.accessories.show(PlayerMenu(
            id: "subtitles",
            title: "Subtitles",
            systemImage: "captions.bubble",
            options: options,
        ))
    }

    /// Whether the menus offer `track`: every one, except in a live stream, which offers those
    /// the player can switch to by itself.
    private func offers(_ track: MediaTrack, in entry: Entry, drawsFiles: Bool) -> Bool {
        guard entry.isLive else { return true }
        guard let stream = entry.stream else { return false }
        return TrackSwitching.switchesInPlace(
            to: track,
            in: stream,
            burnsInStyled: burnsInStyledSubtitles,
            drawsFiles: drawsFiles,
        )
    }

    private func subtitleOption(
        _ id: String,
        _ title: String,
        _ choice: SubtitleChoice,
        _ controller: PlaybackController,
    ) -> PlayerMenu.Option {
        option(id, title, entry?.subtitleChoice == choice, controller) { entry, prefs in
            entry.subtitleChoice = choice
            entry.subtitle = switch choice {
            case .off:
                nil
            case .onlyForced:
                StreamChoice.onlyForced(in: entry.tracks, audioLanguage: entry.audio?.language, preferences: prefs)
            case let .track(index):
                entry.tracks.of(.subtitle).first(id: index)
            }
        }
    }

    /// A menu option that changes the entry's choice, remembers it and switches to it.
    private func option(
        _ id: String,
        _ title: String,
        _ isSelected: Bool,
        _ controller: PlaybackController,
        change: @escaping @MainActor (inout Entry, TrackPreferences) -> Void,
    ) -> PlayerMenu.Option {
        PlayerMenu.Option(id: id, title: title, isSelected: isSelected) { [weak self, weak controller] in
            guard let self, let controller, let previous = entry, previous.stream != nil else { return }
            var entry = previous
            change(&entry, preferences)
            self.entry = entry
            remember(entry, previous: previous)
            showMenus(in: controller)
            Task { await self.switchTracks(from: previous, in: controller) }
        }
    }
}
