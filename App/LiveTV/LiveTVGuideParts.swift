import AnemoneJellyfin
import AnemoneUI
import SwiftUI

/// A programme in the guide, ported from Wholphin's `Program`: its name and episode, a caret when
/// it began before the window, the recording marker, and its category's colour.
struct LiveTVProgramCell: View {
    let cell: LiveTVGuideCell
    let colorCodes: Bool
    let select: () -> Void

    var body: some View {
        let program = cell.program
        Button(action: select) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if cell.continuesBefore {
                        Image(systemName: "chevron.left")
                            .font(.caption2.bold())
                    }
                    Text(program.name)
                        .font(.callout)
                        .lineLimit(1)
                }
                if let subtitle = program.subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .lineLimit(1)
                        .opacity(0.8)
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .overlay(alignment: .bottomTrailing) {
                RecordingMarker(program: program)
            }
        }
        .buttonStyle(GuideCellStyle(fill: fill))
        .accessibilityIdentifier("guide.program.\(program.channelID).\(program.id)")
        .accessibilityLabel(program.accessibilityText)
    }

    private var fill: Color {
        guard colorCodes, let color = cell.program.categoryColor else {
            return .white.opacity(cell.program.isPlaceholder ? 0.06 : 0.12)
        }
        return color
    }
}

/// A channel at the start of its row, ported from Wholphin's `Channel`: number, logo (or name)
/// and a heart for favourites.
struct LiveTVChannelCell: View {
    let channel: LiveTVChannel
    let logoURL: URL?
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 14) {
                Text(channel.number ?? "")
                    .font(.callout.monospacedDigit())
                    .lineLimit(1)
                LogoImage(url: logoURL, maxWidth: 150, height: 56) {
                    Text(channel.name)
                        .font(.caption)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topTrailing) {
                if channel.isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .padding(6)
                }
            }
        }
        .buttonStyle(GuideCellStyle(fill: .white.opacity(0.18)))
        .accessibilityIdentifier("guide.channel.\(channel.id)")
        .accessibilityLabel(channel.isFavorite ? "\(channel.title), favorite" : channel.title)
    }
}

/// Above the guide, the focused programme's details, as Wholphin's `TvGuideHeader`.
struct LiveTVGuideHeader: View {
    let program: LiveTVProgram?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(program?.name ?? " ")
                .font(.title2.bold())
                .lineLimit(1)
                .accessibilityIdentifier("guide.header.title")
            Text(program?.subtitle ?? " ")
                .font(.headline)
                .lineLimit(1)
            HStack(spacing: 16) {
                Text(program?.quickDetails() ?? " ")
                if program?.isRepeat == true {
                    Text("Repeat")
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 2)
                        .overlay(Capsule().stroke(.secondary))
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            Text(program?.overview ?? " ")
                .font(.callout)
                .lineLimit(3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: ItemLayout.textWidth, alignment: .leading)
        .frame(height: 230, alignment: .topLeading)
    }
}

/// The times along the top of the guide, every half hour, with the weekday once the guide runs
/// into another day.
struct LiveTVTimeRuler: View {
    let guide: LiveTVGuide
    let window: DateInterval
    let width: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(guide.halfHours(in: window), id: \.self) { mark in
                Text(label(mark))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(.secondary).frame(width: 2)
                    }
                    .offset(x: x(mark))
            }
        }
        .frame(width: width, height: 44, alignment: .topLeading)
        .clipped()
    }

    private func x(_ date: Date) -> CGFloat {
        CGFloat(date.timeIntervalSince(window.start) / window.duration) * width
    }

    private func label(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        guard !Calendar.current.isDate(date, inSameDayAs: guide.start) else { return time }
        return "\(date.formatted(.dateTime.weekday(.abbreviated))) \(time)"
    }
}

/// A guide cell that fills white when focused, like Wholphin's, without tvOS's lift, which would
/// cover the cells beside it.
struct GuideCellStyle: ButtonStyle {
    let fill: Color

    func makeBody(configuration: Configuration) -> some View {
        Cell(label: configuration.label, fill: fill, isPressed: configuration.isPressed)
    }

    private struct Cell<Label: View>: View {
        let label: Label
        let fill: Color
        let isPressed: Bool

        @Environment(\.isFocused) private var isFocused

        var body: some View {
            label
                .foregroundStyle(isFocused ? .black : .primary)
                .background(isFocused ? .white : fill, in: .rect(cornerRadius: 8))
                .padding(3)
                .scaleEffect(isPressed ? 0.97 : 1)
                .animation(.easeOut(duration: 0.12), value: isFocused)
        }
    }
}
