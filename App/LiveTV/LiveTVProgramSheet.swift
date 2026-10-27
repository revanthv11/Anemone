import AnemoneJellyfin
import AnemoneUI
import SwiftUI

/// Wholphin's programme dialog (`ProgramDialog`): the programme's details, with Watch Live while
/// it airs, Record until it ends, and Record Series for a series, each of the last two becoming
/// Cancel once set. Loads the programme again first, as Wholphin does, so the buttons match
/// what the server has scheduled.
struct LiveTVProgramSheet: View {
    let program: LiveTVProgram
    let watch: (LiveTVProgram) -> Void
    /// A recording was set or cancelled: the programme's own, or (`series`) its series'.
    let changed: (_ program: LiveTVProgram, _ series: Bool) -> Void

    @Environment(BrowseModel.self) private var browse
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @State private var loaded: LiveTVProgram?
    @State private var problem: String?
    @State private var isWorking = false

    var body: some View {
        let program = loaded ?? program
        VStack(alignment: .leading, spacing: 20) {
            Text(program.name)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("program.title")
            if let subtitle = program.subtitle {
                Text(subtitle)
                    .font(.headline)
            }
            Text([program.timeRange(), program.channelName].compactMap(\.self).joined(separator: " · "))
                .font(.callout)
                .foregroundStyle(theme.secondaryText)
            if let overview = program.overview {
                Text(overview)
                    .font(.callout)
                    .lineLimit(4)
            }
            if let problem {
                NoticeText(problem)
            }
            actions(for: program)
                .padding(.top, 20)
                .disabled(isWorking)
        }
        .padding(60)
        .frame(width: 1200, alignment: .leading)
        .task {
            if let fresh = try? await browse.session.liveTVProgram(id: self.program.id) {
                loaded = fresh
            }
        }
    }

    private func actions(for program: LiveTVProgram) -> some View {
        let now = Date.now
        return HStack(spacing: 30) {
            if program.isAiring(at: now) {
                Button("Watch Live", systemImage: "play.fill") {
                    watch(program)
                }
                .accessibilityIdentifier("program.watch")
            }
            if program.isSeries {
                if let seriesTimerID = program.seriesTimerID {
                    Button("Cancel Series Recording", systemImage: "xmark.circle") {
                        perform(series: true) { try await $0.cancelRecording(timerID: seriesTimerID, series: true) }
                    }
                    .accessibilityIdentifier("program.cancelSeries")
                } else {
                    Button("Record Series", systemImage: "record.circle") {
                        perform(series: true) { try await $0.record(programID: program.id, series: true) }
                    }
                    .accessibilityIdentifier("program.recordSeries")
                }
            }
            // Only until it ends, as in Wholphin.
            if program.end > now {
                if let timerID = program.timerID {
                    Button("Cancel Recording", systemImage: "xmark.circle") {
                        perform(series: false) { try await $0.cancelRecording(timerID: timerID, series: false) }
                    }
                    .accessibilityIdentifier("program.cancelRecording")
                } else {
                    Button("Record", systemImage: "record.circle") {
                        perform(series: false) { try await $0.record(programID: program.id, series: false) }
                    }
                    .accessibilityIdentifier("program.record")
                }
            }
        }
    }

    /// Sends the change, then closes, so the page shows the new state; when the server refuses,
    /// says why and stays open.
    private func perform(series: Bool, _ change: @escaping @Sendable (JellyfinSession) async throws -> Void) {
        isWorking = true
        let session = browse.session
        Task {
            do {
                try await change(session)
                changed(loaded ?? program, series)
                dismiss()
            } catch {
                problem = browse.problem(
                    with: error,
                    failure: "Couldn't change the recording on \(browse.server.name).",
                )
            }
            isWorking = false
        }
    }
}
