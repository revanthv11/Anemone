import AnemoneCore
import AnemoneJellyfin

/// The menus.
extension TrackSelection {
    func showMenus(in controller: PlaybackController) {
        guard let entry else { return }
        let rendering = Self.rendering(in: controller.engine)
        let audio = entry.tracks.of(.audio).filter { offers($0, in: entry, rendering: rendering) }
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
        let subtitles = entry.tracks.of(.subtitle).filter { offers($0, in: entry, rendering: rendering) }
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
    private func offers(_ track: MediaTrack, in entry: Entry, rendering: SubtitleRendering) -> Bool {
        guard entry.isLive else { return true }
        guard let stream = entry.stream else { return false }
        return TrackSwitching.switchesInPlace(to: track, in: stream, rendering: rendering)
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
            picks += 1
            let pick = picks
            remember(entry, previous: previous)
            showMenus(in: controller)
            Task { await self.switchTracks(from: previous, pick: pick, in: controller) }
        }
    }
}
