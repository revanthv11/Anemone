import SwiftUI

/// An sRGB colour written as Wholphin writes its theme colours, `0xAARRGGBB`, so the tables read
/// like Wholphin's `Color(0xFF5F00D6)`. It's a `ShapeStyle`, so views use a role as it is:
/// `.foregroundStyle(theme.onBackground)`, `.fill(theme.progress)`. Where a `Color` is needed
/// (`shadow(color:)`, `tint(_:)`), use `color`.
///
/// It also knows its WCAG contrast, so the tests can check the themes' text against their
/// backgrounds.
public struct ThemeColor: Hashable, Sendable {
    public let argb: UInt32

    public init(_ argb: UInt32) {
        self.argb = argb
    }

    public var alpha: Double {
        Self.component(argb >> 24)
    }

    public var red: Double {
        Self.component(argb >> 16)
    }

    public var green: Double {
        Self.component(argb >> 8)
    }

    public var blue: Double {
        Self.component(argb)
    }

    public var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    /// The same colour at another opacity, from 0 to 1, as Compose's `copy(alpha =)` sets it.
    public func opacity(_ alpha: Double) -> ThemeColor {
        let byte = UInt32((min(max(alpha, 0), 1) * 255).rounded())
        return ThemeColor(byte << 24 | argb & 0x00FF_FFFF)
    }

    /// What shows when this colour is drawn over `background`; opaque when the background is.
    public func over(_ background: ThemeColor) -> ThemeColor {
        let mixed = [(red, background.red), (green, background.green), (blue, background.blue)].map { top, bottom in
            UInt32(((top * alpha + bottom * (1 - alpha)) * 255).rounded())
        }
        let outAlpha = UInt32(((alpha + background.alpha * (1 - alpha)) * 255).rounded())
        return ThemeColor(outAlpha << 24 | mixed[0] << 16 | mixed[1] << 8 | mixed[2])
    }

    /// WCAG 2's relative luminance, from 0 (black) to 1 (white), ignoring opacity.
    public var relativeLuminance: Double {
        func linear(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG 2's contrast ratio with another colour, from 1 to 21. AA asks 4.5 for text and 3 for
    /// large text and other marks. Compare opaque colours: `over(_:)` a translucent one first.
    public func contrast(with other: ThemeColor) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func component(_ value: UInt32) -> Double {
        Double(value & 0xFF) / 255
    }
}

extension ThemeColor: ShapeStyle {
    public func resolve(in _: EnvironmentValues) -> Color {
        color
    }
}
