import AnemoneJellyfin
import AnemonePlayback
import SwiftUI

/// How the stream is being played, for Settings › Playback › Player Controls › Show debug info.
/// Ported from the parts of Wholphin's `PlaybackDebugOverlay` and `PlaybackTrackInfo` that apply:
/// the engine, the play method and session, the position and speed, the trickplay and chapters,
/// and the tracks the engine lists.
struct OverlayDebugPanel: View {
    let playback: PlaybackController
    let overlay: PlayerOverlay
    let details: PlaybackDetails?

    @State private var tracks: [PlayerTrack] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows, id: \.0) { name, value in
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(name)
                        .foregroundStyle(.secondary)
                        .frame(width: 220, alignment: .leading)
                    Text(value)
                }
            }
        }
        .font(.caption2.monospacedDigit())
        .padding(24)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityIdentifier("player.debug")
        .task(id: details?.trackChanges) {
            tracks = await playback.engine.tracks(.audio) + playback.engine.tracks(.subtitle)
        }
    }

    private var rows: [(String, String)] {
        let stream = details?.stream
        let seeker = overlay.seeker
        var rows = [
            ("Engine", String(describing: type(of: playback.engine))),
            ("Play method", stream.map { "\($0.method)" } ?? "–"),
            ("Play session", stream?.playSessionID ?? "–"),
            ("Media source", stream?.mediaSourceID ?? "–"),
            ("Position", "\(seeker.position.clockText) / \((seeker.duration ?? .zero).clockText)"),
            ("Speed", String(format: "%.2f×", playback.engine.rate)),
            ("Paused", overlay.isPaused ? "yes" : "no"),
        ]
        if let target = seeker.target {
            rows.append(("Seeking to", target.clockText))
        }
        if let previews = details?.previews {
            let trickplay = previews.trickplay.map {
                "\($0.width)×\($0.height), \($0.columns)×\($0.rows) a sheet, every \($0.interval.clockText)"
            }
            rows.append(("Trickplay", trickplay ?? "none"))
            rows.append(("Chapters", "\(previews.chapters.count)"))
        }
        for track in tracks {
            let kind = track.kind == .audio ? "Audio" : "Subtitle"
            rows.append(("\(kind) \(track.id)\(track.isSelected ? " ✓" : "")", track.title))
        }
        return rows
    }
}
