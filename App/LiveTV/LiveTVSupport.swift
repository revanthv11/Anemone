import AnemoneCore
import AnemoneJellyfin
import AnemonePlayback
import SwiftUI

extension Preferences {
    /// Wholphin's Live TV view options, with its defaults.
    static let liveTVShowsDetails = Preference("liveTVShowsDetails", default: true)
    static let liveTVFavoriteChannelsFirst = Preference("liveTVFavoriteChannelsFirst", default: true)
    static let liveTVRecentlyWatchedFirst = Preference("liveTVRecentlyWatchedFirst", default: false)
    static let liveTVColorCodesPrograms = Preference("liveTVColorCodesPrograms", default: true)

    static var liveTVChannelOrder: LiveTVChannelOrder {
        LiveTVChannelOrder(
            favoritesFirst: liveTVFavoriteChannelsFirst.value(),
            recentlyWatchedFirst: liveTVRecentlyWatchedFirst.value(),
        )
    }
}

enum LiveTVLayout {
    static let horizontalInset: CGFloat = 80
    static let channelWidth: CGFloat = 250
    static let rowHeight: CGFloat = 96
    static let rowSpacing: CGFloat = 8
    /// Between the channel column and the programmes.
    static let columnSpacing: CGFloat = 12
    /// How much of the guide shows at once. Wholphin shows about three and a half hours on a
    /// phone-sized TV layout; Apple TV's larger type fits less.
    static let windowLength: TimeInterval = 2.5 * 3600
}

extension BrowseModel {
    /// What a page asks for to watch a channel live. The server opens the live stream when the
    /// player asks how to play it.
    func playback(of channel: LiveTVChannel) -> PlaybackRequest {
        live(channelID: channel.id, title: channel.title, program: channel.currentProgram)
    }

    /// Watching the channel a programme is on.
    func playback(onChannelOf program: LiveTVProgram, channel: LiveTVChannel? = nil) -> PlaybackRequest {
        live(
            channelID: program.channelID,
            title: channel?.title ?? program.channelName ?? program.name,
            program: program,
        )
    }

    /// Playing a recording under way from its start, as far as it has got.
    func playback(of recording: LiveTVRecording) -> PlaybackRequest {
        let program = recording.program
        let details = [program.subtitle, program.channelName].compactMap(\.self)
        let metadata = PlaybackMetadata(
            title: program.name,
            subtitle: details.isEmpty ? nil : details.joined(separator: " · "),
            overview: program.overview,
        )
        return PlaybackRequest(PlaybackQueue.Entry(itemID: recording.id, metadata: metadata))
    }

    private func live(channelID: String, title: String, program: LiveTVProgram?) -> PlaybackRequest {
        let metadata = PlaybackMetadata(
            title: title,
            subtitle: program.map { [$0.name, $0.subtitle].compactMap(\.self).joined(separator: " · ") },
            overview: program?.overview,
        )
        return PlaybackRequest(PlaybackQueue.Entry(itemID: channelID, metadata: metadata))
    }
}

extension LiveTVProgram {
    /// "8:00 – 9:30 PM", with the weekday when it isn't today, as Wholphin's guide shows times.
    func timeRange(now: Date = .now) -> String {
        let calendar = Calendar.current
        // The interval style shares the AM or PM ("8:00 – 9:30 PM") but adds dates across
        // midnight, so those get the two times on their own.
        let range = calendar.isDate(start, inSameDayAs: end)
            ? (start ..< end).formatted(Date.IntervalFormatStyle(date: .omitted, time: .shortened))
            : [start, end].map { $0.formatted(date: .omitted, time: .shortened) }.joined(separator: " – ")
        guard !calendar.isDate(start, inSameDayAs: now) else { return range }
        return "\(start.formatted(.dateTime.weekday(.abbreviated))) \(range)"
    }

    /// Wholphin's quick details: the times, then the length, the time left while it airs, the
    /// episode and the rating.
    func quickDetails(now: Date = .now) -> String {
        var parts = [timeRange(now: now)]
        guard !isPlaceholder else { return parts[0] }
        parts.append(Self.length(duration))
        if isAiring(at: now) {
            parts.append("\(Self.length(.seconds(end.timeIntervalSince(now)))) left")
        }
        parts += [episodeLabel, officialRating].compactMap(\.self)
        return parts.joined(separator: " · ")
    }

    /// Rounded to the minute, like Wholphin's `roundMinutes`.
    static func length(_ duration: Duration) -> String {
        let minutes = Int((Double(duration.components.seconds) / 60).rounded())
        return Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    /// Wholphin's colours for its categories, dimmed so text stays readable on them.
    var categoryColor: Color? {
        switch category {
        case .kids: Color(red: 0, green: 0.4, blue: 0.4)
        case .news: Color(red: 0, green: 0.35, blue: 0)
        case .movie: Color(red: 0.3, green: 0.1, blue: 0.4)
        case .sports: Color(red: 0.45, green: 0, blue: 0)
        case nil: nil
        }
    }

    var isRecording: Bool {
        timerID != nil
    }

    var isSeriesRecording: Bool {
        seriesTimerID != nil
    }
}

/// Wholphin's recording marker: a red dot for a recording, two for a series. The red is
/// Wholphin's `Color.Red`, the same in every theme.
struct RecordingMarker: View {
    let program: LiveTVProgram

    var body: some View {
        if program.isRecording || program.isSeriesRecording {
            HStack(spacing: 3) {
                Circle().fill(.red).frame(width: 14, height: 14)
                if program.isSeriesRecording {
                    Circle().fill(.red).frame(width: 14, height: 14)
                }
            }
            .padding(4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(program.isSeriesRecording ? "Series recording" : "Recording")
        }
    }
}
