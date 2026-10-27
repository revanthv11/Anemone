import AnemoneJellyfin
import CoreGraphics
import Foundation
import ImageIO
import Observation
import SwiftUI

/// Trickplay sheets for one video, fetched through the session (they need the token) and decoded
/// off the main actor. A sheet holds 100 thumbnails and is about 23 MB decoded at Jellyfin's
/// default size, so only the last few stay; the JPEGs stay too, and they're small. Takes the place
/// of Wholphin's Coil prefetching and `CoilTrickplayTransformation`.
@MainActor
@Observable
final class TrickplaySheets {
    let trickplay: Trickplay
    private(set) var images: [Int: CGImage] = [:]

    @ObservationIgnored private let session: JellyfinSession
    @ObservationIgnored private var jpegs: [Int: Data] = [:]
    @ObservationIgnored private var loading: Set<Int> = []
    /// Decoded sheets, least recently asked for first.
    @ObservationIgnored private var recent: [Int] = []
    private static let decodedLimit = 3

    init(trickplay: Trickplay, session: JellyfinSession) {
        self.trickplay = trickplay
        self.session = session
    }

    /// The thumbnail for `tile`, once its sheet has loaded.
    func thumbnail(_ tile: Trickplay.Tile) -> CGImage? {
        let rect = CGRect(
            x: tile.column * trickplay.width,
            y: tile.row * trickplay.height,
            width: trickplay.width,
            height: trickplay.height,
        )
        return images[tile.sheet]?.cropping(to: rect)
    }

    /// Loads a sheet, unless it's loaded or loading. Failures are left alone: the preview shows
    /// the time without a thumbnail.
    func load(_ sheet: Int) {
        guard (0 ..< trickplay.sheetCount).contains(sheet) else { return }
        recent.removeAll { $0 == sheet }
        recent.append(sheet)
        guard images[sheet] == nil, !loading.contains(sheet) else { return }
        loading.insert(sheet)
        Task {
            defer { loading.remove(sheet) }
            let jpeg: Data
            if let cached = jpegs[sheet] {
                jpeg = cached
            } else {
                guard let fetched = try? await session.trickplaySheet(sheet, of: trickplay) else { return }
                jpegs[sheet] = fetched
                jpeg = fetched
            }
            guard let image = await Self.decode(jpeg) else { return }
            images[sheet] = image
            for old in recent.dropLast(Self.decodedLimit) {
                images[old] = nil
            }
            recent = Array(recent.suffix(Self.decodedLimit))
        }
    }

    /// Decodes now, away from the main actor, rather than when first drawn, so seeking doesn't
    /// stutter.
    @concurrent
    private nonisolated static func decode(_ data: Data) async -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        return CGImageSourceCreateImageAtIndex(source, 0, options)
    }
}

/// A trickplay thumbnail over a time, or just the time for a video without them. Ported from
/// Wholphin's `TrickplayPreview` and `SeekPreviewImage`.
struct SeekPreview: View {
    let position: Duration
    let sheets: TrickplaySheets?

    private static let width: CGFloat = 384

    var body: some View {
        VStack(spacing: 12) {
            if let sheets {
                let trickplay = sheets.trickplay
                let tile = trickplay.tile(at: position)
                ZStack {
                    Color.black
                    if let thumbnail = sheets.thumbnail(tile) {
                        Image(decorative: thumbnail, scale: 1)
                            .resizable()
                            .scaledToFill()
                    }
                }
                .frame(width: Self.width, height: Self.width * CGFloat(trickplay.height) / CGFloat(trickplay.width))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.white.opacity(0.85), lineWidth: 2)
                }
                .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
                .task(id: tile.sheet) {
                    sheets.load(tile.sheet)
                    // The next sheet too, since seeking mostly goes forward.
                    sheets.load(tile.sheet + 1)
                }
                .accessibilityIdentifier("player.preview")
            }
            Text(position.timecode)
                .font(.callout.monospacedDigit())
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
        }
        .fixedSize()
    }
}

/// Places its one subview over a point `fraction` of the way across, kept within the bounds, as
/// Wholphin's `offsetByPercent` does for the seek preview.
struct AlongTrack: Layout {
    var fraction: Double

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let size = subviews.first?.sizeThatFits(.unspecified) ?? .zero
        return CGSize(width: proposal.width ?? size.width, height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        guard let subview = subviews.first else { return }
        let size = subview.sizeThatFits(.unspecified)
        let centered = bounds.minX + bounds.width * min(max(fraction, 0), 1) - size.width / 2
        let left = min(max(centered, bounds.minX), max(bounds.maxX - size.width, bounds.minX))
        subview.place(at: CGPoint(x: left, y: bounds.minY), proposal: ProposedViewSize(size))
    }
}

extension Duration {
    /// "1:02:03", or "2:03" under an hour, as Wholphin's `formatDuration` shows times.
    var timecode: String {
        let total = max(Int(components.seconds), 0)
        let hours = total / 3600
        let minutes = total / 60 % 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}
