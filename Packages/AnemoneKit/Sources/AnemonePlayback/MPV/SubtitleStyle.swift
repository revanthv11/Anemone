import AnemoneCore
import Foundation

/// How text subtitles look: Wholphin's subtitle style settings (`SubtitleSettings`), with its
/// ranges and defaults. ASS subtitles keep their own styling. Stored as JSON in one setting,
/// so a page can edit it field by field.
public struct SubtitleStyle: Codable, Hashable, Sendable {
    /// Wholphin's font size, 8 to 70 in steps of 2.
    public var fontSize = 24
    public var fontColor = SubtitleColor.white
    public var isBold = false
    public var isItalic = false
    /// Percent, 10 to 100.
    public var fontOpacity = 100
    public var edge = SubtitleEdge.solid
    public var edgeColor = SubtitleColor.black
    /// Wholphin's edge size, 1 to 32, shown halved.
    public var edgeThickness = 4
    public var background = SubtitleBackground.none
    public var backgroundColor = SubtitleColor.black
    /// Percent, 10 to 100.
    public var backgroundOpacity = 50
    /// How far above the bottom, in percent of the screen's height, 0 to 100.
    public var margin = 8

    public init() {}

    public static let standard = Self()
}

/// Wholphin's choice of colours for text, edges and backgrounds.
public enum SubtitleColor: String, CaseIterable, Codable, Sendable {
    case white, black, lightGray, darkGray, red, yellow, green, cyan, blue, magenta

    /// As Jetpack Compose defines Wholphin's colours.
    public var rgb: UInt32 {
        switch self {
        case .white: 0xFFFFFF
        case .black: 0x000000
        case .lightGray: 0xCCCCCC
        case .darkGray: 0x444444
        case .red: 0xFF0000
        case .yellow: 0xFFFF00
        case .green: 0x00FF00
        case .cyan: 0x00FFFF
        case .blue: 0x0000FF
        case .magenta: 0xFF00FF
        }
    }

    public var name: String {
        switch self {
        case .white: "White"
        case .black: "Black"
        case .lightGray: "Light gray"
        case .darkGray: "Dark gray"
        case .red: "Red"
        case .yellow: "Yellow"
        case .green: "Green"
        case .cyan: "Cyan"
        case .blue: "Blue"
        case .magenta: "Magenta"
        }
    }
}

/// Around the letters: nothing, an outline, or a drop shadow.
public enum SubtitleEdge: String, CaseIterable, Codable, Sendable {
    case none, solid, shadow
}

/// Behind the text: nothing, a box around each line, or one box around them all.
public enum SubtitleBackground: String, CaseIterable, Codable, Sendable {
    case none, wrap, boxed
}

/// The style for most video, and a second one for HDR video when the user wants it, since
/// full-white text is glaring next to HDR highlights. Wholphin's "Different for HDR".
public struct SubtitleStyles: Hashable, Sendable {
    public var standard: SubtitleStyle
    public var hdr: SubtitleStyle?

    public init(standard: SubtitleStyle, hdr: SubtitleStyle? = nil) {
        self.standard = standard
        self.hdr = hdr
    }

    /// The user's settings.
    public static var current: Self {
        Self(
            standard: Preferences.subtitleStyle.value(),
            hdr: Preferences.subtitleStyleSeparateHDR.value() ? Preferences.hdrSubtitleStyle.value() : nil,
        )
    }

    public func style(forHDR isHDR: Bool) -> SubtitleStyle {
        isHDR ? hdr ?? standard : standard
    }
}

/// Kept as JSON text, which `@AppStorage` can hold too.
extension SubtitleStyle: PreferenceValue {
    public static func read(_ key: String, from defaults: UserDefaults) -> Self? {
        defaults.string(forKey: key).flatMap(Self.init(json:))
    }

    public func write(_ key: String, to defaults: UserDefaults) {
        defaults.set(json, forKey: key)
    }

    public init?(json: String) {
        guard let style = try? JSONDecoder().decode(Self.self, from: Data(json.utf8)) else { return nil }
        self = style
    }

    public var json: String {
        (try? JSONEncoder().encode(self)).flatMap { String(bytes: $0, encoding: .utf8) } ?? "{}"
    }

    /// Fields missing from what was saved keep their defaults, so the style can grow.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let standard = Self.standard
        fontSize = try values.decodeIfPresent(Int.self, forKey: .fontSize) ?? standard.fontSize
        fontColor = try values.decodeIfPresent(SubtitleColor.self, forKey: .fontColor) ?? standard.fontColor
        isBold = try values.decodeIfPresent(Bool.self, forKey: .isBold) ?? standard.isBold
        isItalic = try values.decodeIfPresent(Bool.self, forKey: .isItalic) ?? standard.isItalic
        fontOpacity = try values.decodeIfPresent(Int.self, forKey: .fontOpacity) ?? standard.fontOpacity
        edge = try values.decodeIfPresent(SubtitleEdge.self, forKey: .edge) ?? standard.edge
        edgeColor = try values.decodeIfPresent(SubtitleColor.self, forKey: .edgeColor) ?? standard.edgeColor
        edgeThickness = try values.decodeIfPresent(Int.self, forKey: .edgeThickness) ?? standard.edgeThickness
        background = try values.decodeIfPresent(SubtitleBackground.self, forKey: .background) ?? standard.background
        backgroundColor = try values.decodeIfPresent(SubtitleColor.self, forKey: .backgroundColor)
            ?? standard.backgroundColor
        backgroundOpacity = try values.decodeIfPresent(Int.self, forKey: .backgroundOpacity)
            ?? standard.backgroundOpacity
        margin = try values.decodeIfPresent(Int.self, forKey: .margin) ?? standard.margin
    }
}

public extension Preferences {
    /// Wholphin's `subtitlesPreferences`.
    static let subtitleStyle = Preference("subtitleStyle", default: SubtitleStyle.standard)
    /// Wholphin's `useSeparateHdr`.
    static let subtitleStyleSeparateHDR = Preference("subtitleStyleSeparateHDR", default: false)
    /// Wholphin's `hdrSubtitlesPreferences`.
    static let hdrSubtitleStyle = Preference("hdrSubtitleStyle", default: SubtitleStyle.standard)
}

extension SubtitleStyle {
    /// The style as libmpv's subtitle options, adapted from Wholphin's `applyToMpv`. libmpv
    /// measures sizes in pixels of a 720-line picture; Wholphin's sizes are Android TV's
    /// scaled pixels at 1080 lines, scaled by 0.8 to match ExoPlayer's text, so 24 becomes
    /// libmpv's own default of 38.
    ///
    /// Fixed while porting: Wholphin sets the outline size last for every edge style, so "None"
    /// and "Shadow" still get an outline. Here only "Solid" does.
    var mpvProperties: [(String, String)] {
        let fontAlpha = fontOpacity
        var properties = [
            ("sub-font-size", String(Int((Double(fontSize) * 1.6).rounded()))),
            ("sub-color", Self.mpvColor(fontColor, opacity: fontAlpha)),
            ("sub-bold", isBold ? "yes" : "no"),
            ("sub-italic", isItalic ? "yes" : "no"),
            ("sub-margin-y", String(Int((Double(margin) * 1080 / 100 * 0.8).rounded()))),
            ("sub-back-color", Self.mpvColor(backgroundColor, opacity: backgroundOpacity)),
        ]
        switch edge {
        case .none:
            properties += [("sub-outline-size", "0"), ("sub-shadow-offset", "0")]
        case .solid:
            let outline = Double(edgeThickness) / 2 * 1.6
            properties += [
                ("sub-outline-size", String(format: "%.2f", outline)),
                ("sub-outline-color", Self.mpvColor(edgeColor, opacity: fontAlpha)),
                ("sub-shadow-offset", "0"),
            ]
        case .shadow:
            properties += [
                ("sub-outline-size", "0"),
                ("sub-shadow-offset", "4"),
                ("sub-shadow-color", Self.mpvColor(edgeColor, opacity: fontAlpha)),
            ]
        }
        let border = switch background {
        case .none: "outline-and-shadow"
        case .wrap: "opaque-box"
        case .boxed: "background-box"
        }
        properties.append(("sub-border-style", border))
        return properties
    }

    /// libmpv's `#AARRGGBB`.
    static func mpvColor(_ color: SubtitleColor, opacity: Int) -> String {
        let alpha = UInt32((Double(min(max(opacity, 0), 100)) / 100 * 255).rounded())
        return String(format: "#%08X", alpha << 24 | color.rgb)
    }
}
