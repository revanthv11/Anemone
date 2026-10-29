import AnemoneJellyfin
import AnemonePlayback
import AnemoneUI
import AVFoundation
import SwiftUI

/// How the stream is being played, for Settings › Playback › Player Controls › Show debug info.
/// Ported from the parts of Wholphin's `PlaybackDebugOverlay` and `PlaybackTrackInfo` that apply:
/// the engine, the play method and session, the position and speed, the trickplay and chapters,
/// and the tracks the engine lists. The video's dynamic range, the display mode asked for and
/// what this Apple TV decodes stand in for the HDR tables Wholphin's debug page gained in
/// `6d02908`, since tvOS lists neither its display modes nor its HDR formats.
struct OverlayDebugPanel: View {
    let playback: PlaybackController
    let overlay: PlayerOverlay
    let details: PlaybackDetails?

    @Environment(\.theme) private var theme
    @State private var tracks: [PlayerTrack] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows, id: \.0) { name, value in
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(name)
                        .foregroundStyle(theme.secondaryText)
                        .frame(width: 220, alignment: .leading)
                    Text(value)
                        .foregroundStyle(theme.onSurface)
                }
                // Each line reads as its name and value.
                .accessibilityElement(children: .combine)
            }
        }
        .font(.caption2.monospacedDigit())
        .padding(24)
        .background(theme.surface.withAlpha(0.6), in: RoundedRectangle(cornerRadius: 16))
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
        if let stream {
            rows.append(("Video", stream.video.map(Self.videoText) ?? "–"))
            rows.append(("Display asked", DisplayCriteria(stream: stream).map(Self.criteriaText) ?? "none"))
        }
        rows.append(("Decodes", Self.decodersText(.current)))
        rows.append(("HDR output", AVPlayer.eligibleForHDRPlayback ? "yes" : "no"))
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

    /// The video as the server read it: "hevc 3840×2160 23.976 fps DOVIWithHDR10".
    static func videoText(_ video: MediaVersion.Video) -> String {
        var parts: [String] = []
        if let codec = video.codec {
            parts.append(codec)
        }
        if let width = video.width, let height = video.height {
            parts.append("\(width)×\(height)")
        }
        if let frameRate = video.frameRate {
            parts.append("\(frameRate.formatted(.number.precision(.fractionLength(0 ... 3)))) fps")
        }
        if let range = video.range {
            parts.append(range.rawValue)
        }
        return parts.isEmpty ? video.title ?? "–" : parts.joined(separator: " ")
    }

    /// The mode the player asks the display for: "23.976 fps, Dolby Vision".
    static func criteriaText(_ criteria: DisplayCriteria) -> String {
        let range = switch criteria.dynamicRange {
        case .sdr: "SDR"
        case .hdr10: "HDR10"
        case .hlg: "HLG"
        case .dolbyVision: "Dolby Vision"
        }
        return "\(criteria.frameRate.formatted(.number.precision(.fractionLength(0 ... 3)))) fps, \(range)"
    }

    /// What VideoToolbox decodes in hardware here: "HEVC, Dolby Vision"; "none" on Apple TV HD.
    static func decodersText(_ decoders: VideoDecoders) -> String {
        var names: [String] = []
        if decoders.hevc {
            names.append("HEVC")
        }
        if decoders.av1 {
            names.append("AV1")
        }
        if decoders.dolbyVision {
            names.append("Dolby Vision")
        }
        return names.isEmpty ? "none" : names.joined(separator: ", ")
    }
}
