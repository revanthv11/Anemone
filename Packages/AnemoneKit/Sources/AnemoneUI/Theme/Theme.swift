import AnemoneCore

/// The colours views use, by what they're for, in the theme chosen in Settings › Appearance.
/// Views read it from the environment, `@Environment(\.theme) private var theme`, and use a
/// role as a style: `.foregroundStyle(theme.secondaryText)`. Each role comes from Wholphin's
/// palette the way Wholphin's own views use it; docs/PLAN.md (6b) says which to use where.
///
/// Ported from Wholphin's `ui/theme` (`WholphinTheme`, `ThemeColors` and its colour tables).
public struct Theme: Hashable, Sendable {
    public let colors: AppThemeColors
    public let scheme: ThemeScheme
    /// The Material roles the semantic ones come from, for the rare view that needs another.
    public let palette: ThemePalette

    // MARK: Page

    /// Behind every page.
    public let background: ThemeColor
    /// Titles and text on the page.
    public let onBackground: ThemeColor
    /// Captions, metadata and other quieter text on the page (Wholphin's `onSurfaceVariant`).
    public let secondaryText: ThemeColor
    /// Darkens artwork under text and controls, in gradients and dimming.
    public let scrim: ThemeColor

    // MARK: Surfaces

    /// Sheets, panels and dialogs that sit on the page.
    public let surface: ThemeColor
    public let onSurface: ThemeColor
    /// Placeholders for artwork that hasn't loaded, and quiet fills such as chips.
    public let surfaceVariant: ThemeColor
    /// Symbols and text on `surfaceVariant`.
    public let onSurfaceVariant: ThemeColor

    // MARK: Accent

    /// The theme's own colour, for what's selected or current: an underline under the chosen
    /// tab, a selected toggle, the app's tint. Wholphin's `border`, opaque.
    public let accent: ThemeColor
    /// Text or marks that pick one thing out where `accent` is too dark to read, like the
    /// current letter of a jump bar (Wholphin's `tertiary`).
    public let highlight: ThemeColor
    /// Filled buttons and their labels.
    public let primary: ThemeColor
    public let onPrimary: ThemeColor

    // MARK: Focus

    /// The ring around a focused card, as TV Material draws it (Wholphin's `border`).
    public let focusRing: ThemeColor
    /// A soft glow under something focused that draws its own lift, like a person's photo.
    public let focusGlow: ThemeColor
    /// A focusable control at rest, and its label (Wholphin's buttons).
    public let platter: ThemeColor
    public let onPlatter: ThemeColor
    /// A focused control, and its label (Wholphin's buttons: light, with dark text).
    public let focusedPlatter: ThemeColor
    public let onFocusedPlatter: ThemeColor

    // MARK: Cards

    /// The dark rounded backing of counts over a card's artwork, and the text on it.
    public let cardBadge: ThemeColor
    public let onCardBadge: ThemeColor
    /// The watched mark on a card, and its check (Wholphin's `WatchedIcon`).
    public let watchedBadge: ThemeColor
    public let onWatchedBadge: ThemeColor
    /// The favourite heart, the same red in every theme, as in Wholphin.
    public let favorite: ThemeColor

    // MARK: Progress

    /// How much of an item has been watched, on cards and pages (Wholphin's card bar).
    public let progress: ThemeColor
    /// The rest of that bar.
    public let progressTrack: ThemeColor
    /// The player's seek bar: what's played, what's buffered and the rest (Wholphin's `SeekBar`).
    public let seekPlayed: ThemeColor
    public let seekBuffered: ThemeColor
    public let seekTrack: ThemeColor

    // MARK: Errors

    /// Error text on the page, and filled error banners with their text.
    public let error: ThemeColor
    public let onError: ThemeColor
    public let errorContainer: ThemeColor
    public let onErrorContainer: ThemeColor

    public init(_ colors: AppThemeColors, scheme: ThemeScheme = .dark) {
        let palette = ThemePalette.wholphin(colors, scheme)
        self.colors = colors
        self.scheme = scheme
        self.palette = palette
        background = palette.background
        onBackground = palette.onBackground
        secondaryText = palette.onSurfaceVariant
        scrim = palette.scrim
        surface = palette.surface
        onSurface = palette.onSurface
        surfaceVariant = palette.surfaceVariant
        onSurfaceVariant = palette.onSurfaceVariant
        accent = palette.border.opacity(1)
        highlight = palette.tertiary
        primary = palette.primary
        onPrimary = palette.onPrimary
        focusRing = palette.border
        focusGlow = palette.border.opacity(0.5)
        platter = palette.surfaceVariant.opacity(0.8)
        onPlatter = palette.onSurface.opacity(0.8)
        focusedPlatter = palette.onSurface
        onFocusedPlatter = palette.inverseOnSurface
        cardBadge = Self.transparentBlack50
        onCardBadge = palette.onSurface
        // Wholphin's black theme has a near-white `border`, which a white check wouldn't show on.
        watchedBadge = colors == .oledBlack ? palette.secondaryContainer : palette.border.opacity(1)
        onWatchedBadge = ThemeColor(0xFFFF_FFFF)
        favorite = Self.holoRedLight
        progress = palette.tertiary
        progressTrack = Self.transparentBlack50
        seekPlayed = palette.border
        seekBuffered = palette.onSurface.opacity(0.65)
        seekTrack = palette.onSurface.opacity(0.25)
        error = palette.error
        onError = palette.onError
        errorContainer = palette.errorContainer
        onErrorContainer = palette.onErrorContainer
    }

    /// Wholphin's default, purple.
    public static let standard = Theme(Preferences.appThemeColors.defaultValue)

    /// Wholphin's `AppColors.TransparentBlack50`.
    private static let transparentBlack50 = ThemeColor(0x8000_0000)
    /// Android's `holo_red_light`, Wholphin's `FavoriteIndicator`.
    private static let holoRedLight = ThemeColor(0xFFFF_4444)
}
