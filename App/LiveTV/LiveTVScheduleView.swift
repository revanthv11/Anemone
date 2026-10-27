import AnemoneJellyfin
import SwiftUI

/// Wholphin's DVR schedule (`DvrSchedule`): recordings under way, then those scheduled, by day.
/// A recording under way plays what has been recorded so far, and a long press cancels it; a
/// scheduled one opens its programme, to watch the channel or cancel. The series set to record
/// are listed last, each with a way to cancel it.
struct LiveTVScheduleView: View {
    /// Changes when the schedule should load again.
    let version: Int
    let select: (LiveTVTimer) -> Void
    let play: (LiveTVRecording) -> Void
    /// Cancels the recording's timer, or its series' timer.
    let cancel: (LiveTVRecording, _ series: Bool) -> Void
    let cancelSeries: (LiveTVSeriesTimer) -> Void

    @Environment(BrowseModel.self) private var browse
    @State private var schedule: LiveTVSchedule?
    @State private var problem: String?

    var body: some View {
        Group {
            if let schedule {
                list(schedule)
            } else if let problem {
                PageMessage(message: problem)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: version) {
            await load()
        }
    }

    private func list(_ schedule: LiveTVSchedule) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {
                if schedule.isEmpty {
                    PageMessage(message: "No scheduled recordings")
                        .accessibilityIdentifier("schedule.empty")
                }
                if !schedule.active.isEmpty {
                    heading("Active Recordings")
                    ForEach(schedule.active) { recording in
                        row(recording)
                    }
                }
                ForEach(schedule.scheduledByDay(), id: \.day) { day in
                    heading(day.day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    ForEach(day.timers) { timer in
                        row(timer)
                    }
                }
                if !schedule.series.isEmpty {
                    heading("Series Recordings")
                    ForEach(schedule.series) { series in
                        seriesRow(series)
                    }
                }
            }
            .frame(maxWidth: 1300)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
        }
    }

    private func heading(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .padding(.top, 24)
            .padding(.horizontal, 20)
    }

    private func row(_ timer: LiveTVTimer) -> some View {
        let program = timer.program
        return Button {
            select(timer)
        } label: {
            ScheduleRow(
                title: program.name,
                detail: [program.subtitle, program.channelName].compactMap(\.self).joined(separator: " · "),
                trailing: program.timeRange(),
                isRecording: timer.isInProgress,
            )
        }
        .buttonStyle(GuideCellStyle(fill: .white.opacity(0.08)))
        .accessibilityIdentifier("schedule.timer.\(timer.id)")
    }

    private func row(_ recording: LiveTVRecording) -> some View {
        let program = recording.program
        return Button {
            play(recording)
        } label: {
            ScheduleRow(
                title: program.name,
                detail: [program.subtitle, program.channelName].compactMap(\.self).joined(separator: " · "),
                trailing: program.timeRange(),
                isRecording: true,
            )
        }
        .buttonStyle(GuideCellStyle(fill: .white.opacity(0.08)))
        .contextMenu {
            if program.timerID != nil {
                Button("Cancel Recording", systemImage: "xmark.circle") {
                    cancel(recording, false)
                }
                .accessibilityIdentifier("schedule.cancelRecording")
            }
            if program.seriesTimerID != nil {
                Button("Cancel Series Recording", systemImage: "xmark.circle") {
                    cancel(recording, true)
                }
                .accessibilityIdentifier("schedule.cancelSeries")
            }
        }
        .accessibilityIdentifier("schedule.recording.\(recording.id)")
    }

    private func seriesRow(_ series: LiveTVSeriesTimer) -> some View {
        Button {
            cancelSeries(series)
        } label: {
            ScheduleRow(
                title: series.name,
                detail: [
                    series.recordsAnyChannel ? "Any channel" : series.channelName,
                    series.recordsAnyTime ? "Any time" : nil,
                    series.recordsNewOnly ? "New episodes only" : nil,
                ].compactMap(\.self).joined(separator: " · "),
                trailing: "Cancel",
                isRecording: false,
            )
        }
        .buttonStyle(GuideCellStyle(fill: .white.opacity(0.08)))
        .accessibilityIdentifier("schedule.series.\(series.id)")
    }

    private func load() async {
        do {
            schedule = try await browse.session.liveTVSchedule()
            problem = nil
        } catch {
            if schedule == nil {
                problem = browse.problem(with: error, doing: "load the recording schedule from \(browse.server.name)")
            }
        }
    }
}

private struct ScheduleRow: View {
    let title: String
    let detail: String
    let trailing: String
    let isRecording: Bool

    var body: some View {
        HStack(spacing: 24) {
            if isRecording {
                Circle()
                    .fill(.red)
                    .frame(width: 16, height: 16)
                    .accessibilityLabel("Recording")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.callout)
                    .lineLimit(1)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .lineLimit(1)
                        .opacity(0.8)
                }
            }
            Spacer()
            Text(trailing)
                .font(.caption)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
}
