import AnemoneCore
import AnemoneJellyfin
import Foundation

/// Chooses each entry's audio and subtitles before the server is asked for a stream, offers
/// Audio and Subtitles menus in the player, and remembers what the user picks for the item and,
/// for episodes, its season and series. Ported from Wholphin's `StreamChoiceService` and the
/// track parts of its `PlaybackViewModel` and `ItemPlaybackRepository`.
///
/// A switch the stream can make on its own happens at once: audio in a file that plays
/// directly, and text subtitles. Anything else asks the server for another stream and goes on
/// from the same position, as Wholphin's `changeStreams` does.
@MainActor
public final class TrackSelection: PlaybackFeature {
    /// What the feature asks the server; tests stand in for it.
    struct Server: Sendable {
        var itemTracks: @Sendable (MediaItem.ID) async throws -> ItemTracks
        var profileSettings: @Sendable () async throws -> ProfileTrackSettings
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
    }

    /// AVPlayer shows ASS and SSA subtitles as plain text, so the server burns them in. An engine
    /// that draws them itself, as MPV will (Phase 4), turns this off.
    public var burnsInStyledSubtitles = true

    private let server: Server
    private let store: TrackChoiceStore
    private let defaults: UserDefaults
    /// The Jellyfin profile's settings, fetched once per player.
    private var profile: ProfileTrackSettings?
    private(set) var entry: Entry?
    /// Counts fetches of an item's tracks, so one that a newer fetch replaced, as when the
    /// player moves on twice in quick succession, doesn't leave its item as the entry.
    private var fetches = 0
    /// Selecting the chosen tracks in a stream that just loaded.
    private var applying: Task<Void, Never>?

    public convenience init(session: JellyfinSession, defaults: UserDefaults = .standard) {
        self.init(
            server: Server(
                itemTracks: { try await session.itemTracks(for: $0) },
                profileSettings: { try await session.profileTrackSettings() },
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

    /// The tracks to ask the server for; `nil` leaves them to the server, such as when the
    /// item's tracks can't be fetched. A retry or a switch for the same item asks for what's
    /// chosen now.
    func request(for itemID: MediaItem.ID, mediaSourceID: String?) async -> TrackRequest? {
        if let entry, entry.itemID == itemID {
            return request(for: entry)
        }
        entry = nil
        fetches += 1
        let fetch = fetches
        async let fetchedProfile = Self.profile(profile, from: server)
        guard let item = try? await server.itemTracks(itemID), let source = item.source(mediaSourceID) else {
            return nil
        }
        profile = await fetchedProfile
        let entry = choose(in: item, source: source)
        // The stream asked for with a stale request isn't played, so its entry isn't kept.
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
        if !stream.tracks.isEmpty {
            entry.tracks = stream.tracks
            entry.audio = entry.audio.flatMap { stream.tracks.of(.audio).first(id: $0.id) }
            entry.subtitle = entry.subtitle.flatMap { stream.tracks.of(.subtitle).first(id: $0.id) }
        }
        entry.stream = stream
        self.entry = entry
        showMenus(in: controller)
        applying?.cancel()
        applying = Task { [weak self, engine = controller.engine] in
            await self?.select(in: engine, for: stream)
        }
    }

    /// When the tracks couldn't be chosen beforehand: what the server picked.
    private static func entry(for stream: PlaybackStream) -> Entry {
        let subtitle = stream.subtitleStreamIndex.flatMap { stream.tracks.of(.subtitle).first(id: $0) }
        return Entry(
            itemID: stream.itemID,
            mediaSourceID: stream.mediaSourceID,
            tracks: stream.tracks,
            audio: stream.audioStreamIndex.flatMap { stream.tracks.of(.audio).first(id: $0) },
            subtitleChoice: subtitle.choice,
            subtitle: subtitle,
        )
    }

    /// Selects the chosen tracks in the engine, where the stream carries them as tracks of
    /// its own, and turns off subtitles the player would otherwise pick by itself.
    private func select(in engine: any PlayerEngine, for stream: PlaybackStream) async {
        guard let entry, entry.stream == stream else { return }
        if stream.method == .directPlay, let audio = entry.audio {
            let options = await engine.tracks(.audio)
            if let option = TrackSwitching.playerTrack(for: audio, in: stream, options: options), !option.isSelected {
                await engine.select(option, .audio)
            }
        }
        let options = await engine.tracks(.subtitle)
        guard !Task.isCancelled, self.entry?.stream == stream else { return }
        let wanted = entry.subtitle.flatMap { TrackSwitching.playerTrack(for: $0, in: stream, options: options) }
        if wanted?.id != options.first(where: \.isSelected)?.id {
            await engine.select(wanted, .subtitle)
        }
    }

    /// AVPlayer showed no HLS subtitles that were selected before playback got under way, the
    /// server's default included, until they were selected again; so they are, once it has.
    private func reselectSubtitles(in engine: any PlayerEngine) async {
        guard let entry, let stream = entry.stream, let subtitle = entry.subtitle else { return }
        let options = await engine.tracks(.subtitle)
        guard self.entry?.stream == stream,
              let wanted = TrackSwitching.playerTrack(for: subtitle, in: stream, options: options)
        else { return }
        await engine.select(nil, .subtitle)
        await engine.select(wanted, .subtitle)
    }
}

/// The menus.
extension TrackSelection {
    private func showMenus(in controller: PlaybackController) {
        guard let entry else { return }
        let audio = entry.tracks.of(.audio)
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
        let subtitles = entry.tracks.of(.subtitle)
        guard !subtitles.isEmpty else {
            controller.accessories.removeMenu("subtitles")
            return
        }
        var options = [subtitleOption("subtitles.off", "Off", .off, controller)]
        if subtitles.contains(where: \.isForcedOrSigns) {
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

/// Switching and remembering.
extension TrackSelection {
    /// Shows the entry's tracks: in the stream that's playing when it can, else by asking the
    /// server for another stream.
    private func switchTracks(from previous: Entry, in controller: PlaybackController) async {
        guard let entry, let stream = entry.stream else { return }
        let engine = controller.engine
        var reloads = false
        if let audio = entry.audio, audio != previous.audio {
            reloads = await TrackSwitching.audio(audio, in: stream, options: engine.tracks(.audio)) == .reload
        }
        if entry.subtitle != previous.subtitle {
            let change = await TrackSwitching.subtitle(
                from: previous.subtitle,
                to: entry.subtitle,
                in: stream,
                options: engine.tracks(.subtitle),
                burnsInStyled: burnsInStyledSubtitles,
            )
            reloads = reloads || change == .reload
        }
        guard self.entry?.stream == stream else { return }
        if reloads {
            applying?.cancel()
            controller.reload()
        } else {
            await select(in: engine, for: stream)
        }
    }

    /// Saves what changed for the item and, for episodes, its season and series, as Wholphin's
    /// `saveTrackSelection` does.
    private func remember(_ entry: Entry, previous: Entry) {
        var picked = store.itemChoice(for: entry.itemID).flatMap { $0.mediaSourceID == entry.mediaSourceID ? $0 : nil }
            ?? ItemTrackChoice(itemID: entry.itemID, mediaSourceID: entry.mediaSourceID)
        var series: ((String, SeriesTrackChoice.Parent) -> SeriesTrackChoice)?
        if let audio = entry.audio, audio != previous.audio {
            picked.audioIndex = audio.index
            // A track without a language says nothing about the next episode's.
            if audio.language != nil {
                series = { .init(parentID: $0, parent: $1, itemID: entry.itemID, track: audio, among: entry.tracks) }
            }
        } else if entry.subtitleChoice != previous.subtitleChoice {
            picked.subtitle = entry.subtitleChoice
            switch entry.subtitleChoice {
            case .off:
                series = {
                    .init(parentID: $0, parent: $1, kind: .subtitle, itemID: entry.itemID, activation: .disabled)
                }
            case .onlyForced:
                series = { .init(
                    parentID: $0,
                    parent: $1,
                    kind: .subtitle,
                    itemID: entry.itemID,
                    activation: .onlyForced,
                ) }
            case .track:
                if let subtitle = entry.subtitle, subtitle.language != nil {
                    series = { .init(
                        parentID: $0,
                        parent: $1,
                        itemID: entry.itemID,
                        track: subtitle,
                        among: entry.tracks,
                    ) }
                }
            }
        }
        let parents = [(entry.seasonID, SeriesTrackChoice.Parent.season), (entry.seriesID, .series)]
        store.save(picked, series: series.map { series in
            parents.compactMap { id, parent in id.map { series($0, parent) } }
        } ?? [])
    }
}
