import AnemoneCore
import AnemoneJellyfin

/// Switching and remembering.
extension TrackSelection {
    /// Shows the entry's tracks: in the stream that's playing when it can (over AVPlayer, text
    /// subtitles that come as files of their own are drawn), else by asking the server for
    /// another stream.
    func switchTracks(from previous: Entry, in controller: PlaybackController) async {
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
                drawsFiles: Self.drawsFiles(in: engine),
            )
            reloads = reloads || change == .reload
        }
        guard self.entry?.stream == stream else { return }
        if reloads, entry.isLive {
            // Another of a live stream's tracks can't be asked for, so the pick is undone.
            self.entry = previous
            showMenus(in: controller)
        } else if reloads {
            applying?.cancel()
            controller.reload()
        } else {
            await select(in: controller, for: stream)
        }
    }

    /// Saves what changed for the item and, for episodes, its season and series, as Wholphin's
    /// `saveTrackSelection` does. Not for live TV, whose tracks are left to the server.
    func remember(_ entry: Entry, previous: Entry) {
        guard !entry.isLive else { return }
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
