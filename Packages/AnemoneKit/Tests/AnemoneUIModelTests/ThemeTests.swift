import AnemoneCore
import AnemoneUI
import Foundation
import Testing

/// Wholphin's colour themes: its names, order, setting and values, every role defined, and the
/// text in them readable against what it's drawn on.
struct ThemeTests {
    @Test func `the themes are Wholphin's, in its order and with its names`() {
        #expect(AppThemeColors.allCases.map { String(localized: $0.title) } == [
            "Purple", "Blue", "Green", "Orange", "Bold Blue", "Black", "Red", "Brown",
        ])
    }

    @Test func `the setting has Wholphin's name and default, and reads a theme it doesn't know as purple`() {
        let defaults = MemoryDefaults()
        let setting = Preferences.appThemeColors
        #expect(setting.key == "appThemeColors")
        #expect(setting.value(in: defaults) == .purple)
        #expect(Theme.standard.colors == .purple)

        setting.set(.oledBlack, in: defaults)
        #expect(defaults.string(forKey: "appThemeColors") == "oledBlack")
        #expect(setting.value(in: defaults) == .oledBlack)

        defaults.set("teal", forKey: "appThemeColors")
        #expect(setting.value(in: defaults) == .purple)
    }

    @Test(arguments: AppThemeColors.allCases, ThemeScheme.allCases)
    func `every theme defines every role`(colors: AppThemeColors, scheme: ThemeScheme) {
        let theme = Theme(colors, scheme: scheme)
        let paletteRoles = Self.colorRoles(of: theme.palette)
        let roles = Self.colorRoles(of: theme)
        // Wholphin's 26 Material roles and TV Material's `border`.
        #expect(paletteRoles.count == 27)
        #expect(roles.count == 32)
        for (role, color) in paletteRoles.merging(roles, uniquingKeysWith: { first, _ in first }) {
            #expect(color.alpha > 0, "\(colors) \(scheme) leaves \(role) transparent")
        }
        // What's behind everything is opaque, so nothing shows through it.
        #expect(theme.background.alpha == 1)
        #expect(theme.surface.alpha == 1)
    }

    @Test func `the tables hold Wholphin's values`() {
        let purple = ThemePalette.wholphin(.purple, .dark)
        #expect(purple.primary == ThemeColor(0xFFD2_BCFF))
        #expect(purple.background == ThemeColor(0xFF15_121C))
        #expect(purple.border == ThemeColor(0xBF74_1BF8))
        #expect(ThemePalette.wholphin(.purple, .light).primary == ThemeColor(0xFF5F_00D6))
        #expect(ThemePalette.wholphin(.blue, .light).primary == ThemeColor(0xFF40_5F90))
        #expect(ThemePalette.wholphin(.green, .dark).border == ThemeColor(0xBF39_912F))
        #expect(ThemePalette.wholphin(.orange, .dark).border == ThemeColor(0xFFE3_9012))
        #expect(ThemePalette.wholphin(.boldBlue, .dark).primary == ThemeColor(0xFF0C_2A67))
        let black = ThemePalette.wholphin(.oledBlack, .dark)
        #expect(black.primary == ThemeColor(0xC04D_4B4B))
        #expect(black.onBackground == ThemeColor(0xC0FF_FFFF))
        #expect(black.background == ThemeColor(0xFF00_0000))
        #expect(ThemePalette.wholphin(.red, .dark).border == ThemeColor(0xFFC0_000C))
        #expect(ThemePalette.wholphin(.brown, .dark).border == ThemeColor(0xFF6D_3B07))
        // Wholphin's black theme borrows the blue one's light scheme.
        #expect(ThemePalette.wholphin(.oledBlack, .light) == ThemePalette.wholphin(.blue, .light))
    }

    @Test func `each theme's dark palette is its own`() {
        let palettes = AppThemeColors.allCases.map { ThemePalette.wholphin($0, .dark) }
        #expect(Set(palettes).count == AppThemeColors.allCases.count)
    }

    @Test(arguments: AppThemeColors.allCases, ThemeScheme.allCases)
    func `roles come from the palette as Wholphin's views use it`(colors: AppThemeColors, scheme: ThemeScheme) {
        let theme = Theme(colors, scheme: scheme)
        let palette = theme.palette
        // TV Material's focus border is `inversePrimary`, sometimes translucent.
        #expect(palette.border.withAlpha(1) == palette.inversePrimary.withAlpha(1))
        #expect(theme.focusRing == palette.border)
        #expect(theme.accent == palette.border.withAlpha(1))
        #expect(theme.progress == palette.tertiary)
        #expect(theme.secondaryText == palette.onSurfaceVariant)
        #expect(theme.focusedPlatter == palette.onSurface)
        #expect(theme.onFocusedPlatter == palette.inverseOnSurface)
        #expect(theme.watchedBadge == (colors == .oledBlack ? palette.secondaryContainer : theme.accent))
        #expect(theme.favorite == ThemeColor(0xFFFF_4444))
    }

    @Test func `colours mix and compare as WCAG says`() {
        let white = ThemeColor(0xFFFF_FFFF)
        let black = ThemeColor(0xFF00_0000)
        #expect(abs(white.contrast(with: black) - 21) < 0.001)
        #expect(white.contrast(with: white) == 1)
        #expect(ThemeColor(0x80FF_FFFF).over(black) == ThemeColor(0xFF80_8080))
        // Replaces the alpha, where SwiftUI's `opacity(_:)` would multiply it.
        #expect(ThemeColor(0xFF12_3456).withAlpha(0.75) == ThemeColor(0xBF12_3456))
        #expect(ThemeColor(0x4012_3456).withAlpha(0.75) == ThemeColor(0xBF12_3456))
        #expect(ThemeColor(0x8012_3456).withAlpha(2) == ThemeColor(0xFF12_3456))
    }

    @Test func `a colour drawn over a translucent one composites source-over`() {
        // Opaque on top hides what's under it; opaque underneath stays opaque.
        #expect(ThemeColor(0xFF12_3456).over(ThemeColor(0x80FF_FFFF)) == ThemeColor(0xFF12_3456))
        #expect(ThemeColor(0xBF74_1BF8).over(ThemeColor(0xFF15_121C)) == ThemeColor(0xFF5C_19C1))
        // Over nothing, a colour is itself, not darkened towards black.
        #expect(ThemeColor(0x80FF_8000).over(ThemeColor(0)) == ThemeColor(0x80FF_8000))
        #expect(ThemeColor(0x00FF_0000).over(ThemeColor(0)) == ThemeColor(0))
        // Half red over half blue: three quarters covered, two thirds of it by the red.
        #expect(ThemeColor(0x80FF_0000).over(ThemeColor(0x8000_00FF)) == ThemeColor(0xC0AA_0055))
        // A quarter white over half black: the black covers more, so it's a dark grey.
        #expect(ThemeColor(0x40FF_FFFF).over(ThemeColor(0x8000_0000)) == ThemeColor(0xA066_6666))
    }

    @Test(arguments: [
        (ThemeColor(0x80FF_0000), ThemeColor(0x8000_00FF)),
        (ThemeColor(0x40FF_FFFF), ThemeColor(0x8000_0000)),
        (ThemeColor(0xBF74_1BF8), ThemeColor(0x26FF_FFFF)),
        (ThemeColor(0xC04D_4B4B), ThemeColor(0x0000_0000)),
    ])
    func `translucent layers flattened first show the same on the page`(top: ThemeColor, middle: ThemeColor) {
        // Source-over is associative: a over (b over the page) is (a over b) over the page.
        for page in [ThemeColor(0xFF15_121C), ThemeColor(0xFFFF_FFFF), ThemeColor(0xFF00_0000)] {
            let layered = top.over(middle.over(page))
            let flattened = top.over(middle).over(page)
            #expect(layered.alpha == 1)
            #expect(flattened.alpha == 1)
            let components = [
                (layered.red, flattened.red),
                (layered.green, flattened.green),
                (layered.blue, flattened.blue),
            ]
            // Each step rounds to a byte, so they may be one apart.
            for (one, other) in components {
                #expect(abs(one - other) <= 1.0 / 255 + 1e-9, "\(top) over \(middle) over \(page)")
            }
        }
    }

    /// Text against what it's drawn on: 4.5 to 1 for AA. Each palette's own pairs are checked in
    /// both schemes; the roles views use, in the dark scheme Anemone shows. Wholphin never shows
    /// its light schemes, whose `border` is the pale `inversePrimary` made for dark backgrounds.
    @Test(arguments: AppThemeColors.allCases, ThemeScheme.allCases)
    func `text meets WCAG AA wherever Wholphin's values allow`(colors: AppThemeColors, scheme: ThemeScheme) {
        let theme = Theme(colors, scheme: scheme)
        let page = theme.background
        var measured = Self.paletteTextPairs.map { $0.measure(in: theme.palette, page: page, required: 4.5) }
        if scheme == .dark {
            measured += Self.textPairs.map { $0.measure(in: theme, page: page, required: 4.5) }
            // Marks that aren't text need 3 to 1.
            measured += Self.markPairs.map { $0.measure(in: theme, page: page, required: 3) }
        }
        for pair in measured {
            let key = "\(colors) \(scheme) \(pair.name)"
            if let known = Self.wholphinLowContrast[key] {
                #expect(pair.ratio < pair.required, "\(key) now meets \(pair.required); take it off the list")
                #expect(abs(pair.ratio - known) < 0.01, "\(key) is \(pair.ratio), not \(known)")
            } else {
                #expect(pair.ratio >= pair.required, "\(key) is \(pair.ratio), under \(pair.required)")
            }
        }
        // Every shortfall listed for this theme is one measured here.
        let listed = Self.wholphinLowContrast.keys.filter { $0.hasPrefix("\(colors) \(scheme) ") }
        #expect(Set(listed).isSubset(of: measured.map { "\(colors) \(scheme) \($0.name)" }))
    }

    /// A colour and what it's drawn on, by their roles.
    private struct Pair<Root> {
        let name: String
        let foreground: KeyPath<Root, ThemeColor>
        let background: KeyPath<Root, ThemeColor>

        init(_ name: String, _ foreground: KeyPath<Root, ThemeColor>, _ background: KeyPath<Root, ThemeColor>) {
            self.name = name
            self.foreground = foreground
            self.background = background
        }

        /// Their contrast, both over the page where they're translucent.
        func measure(in root: Root, page: ThemeColor, required: Double) -> Measured {
            let behind = root[keyPath: background].over(page)
            let ratio = root[keyPath: foreground].over(behind).contrast(with: behind)
            return Measured(name: name, ratio: ratio, required: required)
        }
    }

    private struct Measured {
        let name: String
        let ratio: Double
        let required: Double
    }

    /// Where Wholphin's own values fall short, kept as Wholphin has them and listed with their
    /// ratio, so any change to the tables shows up here.
    ///
    /// - Text: a few filled colours in four themes. Anemone's views don't draw text in these
    ///   pairs: filled buttons use `primary`, whose dark text is short only in orange and bold blue.
    /// - Focus rings and the accent on the page: Wholphin's `border` is dark in most themes. On
    ///   tvOS it's never the only sign of focus, since focused cards also lift and grow.
    /// - Orange's white check on its watched badge.
    private static let wholphinLowContrast: [String: Double] = [
        "purple dark onTertiary/tertiary": 3.89,
        "orange dark onPrimary/primary": 2.16,
        "boldBlue dark onPrimary/primary": 3.96,
        "boldBlue dark onTertiaryContainer/tertiaryContainer": 1.19,
        "oledBlack dark onSecondary/secondary": 2.99,
        "oledBlack dark onTertiaryContainer/tertiaryContainer": 3.19,
        "purple dark focusRing/background": 2.08,
        "purple dark accent/background": 2.87,
        "blue dark focusRing/background": 2.88,
        "blue dark accent/background": 2.88,
        "boldBlue dark focusRing/background": 1.50,
        "boldBlue dark accent/background": 1.50,
        "red dark focusRing/background": 2.87,
        "red dark accent/background": 2.87,
        "brown dark focusRing/background": 2.01,
        "brown dark accent/background": 2.01,
        "orange dark onWatchedBadge/watchedBadge": 2.54,
    ]

    private static var paletteTextPairs: [Pair<ThemePalette>] {
        [
            Pair("onPrimary/primary", \.onPrimary, \.primary),
            Pair("onPrimaryContainer/primaryContainer", \.onPrimaryContainer, \.primaryContainer),
            Pair("onSecondary/secondary", \.onSecondary, \.secondary),
            Pair("onSecondaryContainer/secondaryContainer", \.onSecondaryContainer, \.secondaryContainer),
            Pair("onTertiary/tertiary", \.onTertiary, \.tertiary),
            Pair("onTertiaryContainer/tertiaryContainer", \.onTertiaryContainer, \.tertiaryContainer),
            Pair("onError/error", \.onError, \.error),
            Pair("onErrorContainer/errorContainer", \.onErrorContainer, \.errorContainer),
            Pair("onBackground/background", \.onBackground, \.background),
            Pair("onSurface/surface", \.onSurface, \.surface),
            Pair("onSurfaceVariant/surfaceVariant", \.onSurfaceVariant, \.surfaceVariant),
            Pair("inverseOnSurface/inverseSurface", \.inverseOnSurface, \.inverseSurface),
        ]
    }

    private static var textPairs: [Pair<Theme>] {
        // The palette's own pairs, such as onBackground on background, are checked above.
        [
            Pair("secondaryText/background", \.secondaryText, \.background),
            Pair("onPlatter/platter", \.onPlatter, \.platter),
            Pair("onFocusedPlatter/focusedPlatter", \.onFocusedPlatter, \.focusedPlatter),
            Pair("onCardBadge/cardBadge", \.onCardBadge, \.cardBadge),
            Pair("highlight/background", \.highlight, \.background),
            Pair("error/background", \.error, \.background),
        ]
    }

    private static var markPairs: [Pair<Theme>] {
        [
            Pair("focusRing/background", \.focusRing, \.background),
            Pair("accent/background", \.accent, \.background),
            Pair("progress/progressTrack", \.progress, \.progressTrack),
            Pair("onWatchedBadge/watchedBadge", \.onWatchedBadge, \.watchedBadge),
            Pair("favorite/cardBadge", \.favorite, \.cardBadge),
        ]
    }

    /// The colours a palette or theme holds, by name.
    private static func colorRoles(of value: Any) -> [String: ThemeColor] {
        var roles: [String: ThemeColor] = [:]
        for child in Mirror(reflecting: value).children {
            if let label = child.label, let color = child.value as? ThemeColor {
                roles[label] = color
            }
        }
        return roles
    }
}

/// Defaults kept in memory, so the setting's test leaves nothing on disk: macOS writes a suite's
/// plist, even an emptied one, after the test process has ended.
private final class MemoryDefaults: UserDefaults, @unchecked Sendable {
    private var values: [String: Any] = [:]

    override func object(forKey key: String) -> Any? {
        values[key]
    }

    override func string(forKey key: String) -> String? {
        values[key] as? String
    }

    override func set(_ value: Any?, forKey key: String) {
        values[key] = value
    }

    override func removeObject(forKey key: String) {
        values[key] = nil
    }
}
