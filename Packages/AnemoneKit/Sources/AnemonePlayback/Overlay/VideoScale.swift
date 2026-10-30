import AnemoneCore
import Foundation

/// How the video fills the screen: Wholphin's Video Scale choices, Compose's `ContentScale` as
/// its `playbackScaleOptions` list them. Fit letterboxes; Crop fills the screen, cutting the
/// sides or the top and bottom; Fill stretches the picture to the screen; None shows it pixel
/// for pixel; Fill width and Fill height fit one side and crop or letterbox the other.
public enum VideoScale: String, CaseIterable, Sendable, PreferenceValue {
    case fit
    case unscaled
    case crop
    case fill
    case fillWidth
    case fillHeight

    /// Wholphin's names.
    public var title: String {
        switch self {
        case .fit: String(localized: "Fit", bundle: .module)
        case .unscaled: String(localized: "None", bundle: .module)
        case .crop: String(localized: "Crop", bundle: .module)
        case .fill: String(localized: "Fill", bundle: .module)
        case .fillWidth: String(localized: "Fill width", bundle: .module)
        case .fillHeight: String(localized: "Fill height", bundle: .module)
        }
    }

    /// Whether the picture is stretched to its frame rather than kept in proportion.
    public var stretches: Bool {
        self == .fill
    }

    /// Where a video `video` points big goes on a screen `bounds` points big: centred, in the
    /// video's proportions (but for Fill, which takes the screen), and past the screen's edges
    /// where the choice crops. The whole screen while the video's size isn't known.
    public func frame(video: CGSize, in bounds: CGSize) -> CGRect {
        guard video.width > 0, video.height > 0, bounds.width > 0, bounds.height > 0 else {
            return CGRect(origin: .zero, size: bounds)
        }
        let widthScale = bounds.width / video.width
        let heightScale = bounds.height / video.height
        let size: CGSize = switch self {
        case .fit: Self.scaled(video, by: min(widthScale, heightScale))
        case .unscaled: video
        case .crop: Self.scaled(video, by: max(widthScale, heightScale))
        case .fill: bounds
        case .fillWidth: Self.scaled(video, by: widthScale)
        case .fillHeight: Self.scaled(video, by: heightScale)
        }
        return CGRect(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2,
            width: size.width,
            height: size.height,
        )
    }

    private static func scaled(_ size: CGSize, by scale: CGFloat) -> CGSize {
        CGSize(width: size.width * scale, height: size.height * scale)
    }
}
