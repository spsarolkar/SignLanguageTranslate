import SwiftUI

/// Design tokens for SignLanguageTranslate.
///
/// Single source of truth for color, type, spacing and radius. Views must not
/// hardcode hex values or magic numbers — if something is missing here, add it
/// here rather than inlining it at the call site.
///
/// Mirrors the design canvas. When the canvas changes, this file changes first.

// MARK: - Palette

enum Palette {
    /// Page background. The darkest surface.
    static let ground = Color(hex: 0x0B0D0F)
    /// Sidebar and secondary chrome.
    static let chrome = Color(hex: 0x111417)
    /// Default card surface.
    static let surface = Color(hex: 0x15181B)
    /// Raised or selected card surface.
    static let surfaceRaised = Color(hex: 0x1D2126)
    /// Inset wells inside cards (stat tiles, table rows).
    static let well = Color(hex: 0x101316)
    /// Control fill — secondary buttons.
    static let control = Color(hex: 0x232930)

    static let border = Color(hex: 0x262B31)
    static let borderStrong = Color(hex: 0x333B43)
    /// Border on a selected or active card.
    static let borderSelected = Color(hex: 0x33414A)
    /// Border on inset wells (metric tiles).
    static let borderSubtle = Color(hex: 0x232930)
    /// Border on a neutral (idle) badge.
    static let borderMuted = Color(hex: 0x2C333A)
    /// Track behind a progress bar.
    static let track = Color(hex: 0x232930)

    static let textPrimary = Color(hex: 0xEEF1F3)
    static let textSecondary = Color(hex: 0xC9D1D8)
    /// Captions and labels. Passes 4.5:1 on `surface`.
    static let textTertiary = Color(hex: 0x8A949D)
    /// Decorative only — do not use for text that must be read.
    static let textQuaternary = Color(hex: 0x6C7A85)
    /// Label on a control-filled button.
    static let textControl = Color(hex: 0xE4E9ED)
    /// Unselected pill and idle badge labels.
    static let textMuted = Color(hex: 0x98A2AC)

    /// Primary accent: active, complete, healthy.
    static let accent = Color(hex: 0x5EC8A8)
    static let accentBright = Color(hex: 0x8EDCC3)
    /// Secondary accent: model/inference surfaces.
    static let accentBlue = Color(hex: 0x6BA8E8)
    /// Tertiary accent: the reservoir/experimental arm.
    static let accentViolet = Color(hex: 0xB58BE0)

    /// Queued, throttled, resumed, degraded.
    static let warning = Color(hex: 0xE0A458)
    /// Failed, corrupt, quarantined, below confidence threshold.
    static let danger = Color(hex: 0xE5695B)

    /// Fill behind an accent-tinted pill or badge.
    static let accentFill = Color(hex: 0x5EC8A8).opacity(Opacity.tintFill)
    static let warningFill = Color(hex: 0xE0A458).opacity(Opacity.tintFill)
    static let dangerFill = Color(hex: 0xE5695B).opacity(Opacity.tintFill)
}

// MARK: - Opacity

/// Opacities applied to a tint color. Use these rather than inline literals.
enum Opacity {
    /// Tinted badge or chip fill.
    static let tintFill: Double = 0.12
    /// Tinted badge or tile border.
    static let tintBorder: Double = 0.35
    /// In-flight segment of a progress bar.
    static let inFlight: Double = 0.32
    /// Selected pill fill.
    static let selectedFill: Double = 0.16
    /// Selected pill border.
    static let selectedBorder: Double = 0.45
    /// Button while pressed.
    static let pressed: Double = 0.8
    /// Disabled control.
    static let disabled: Double = 0.4
}

// MARK: - Typography

enum Typo {
    /// Screen titles. "Data Pipeline".
    static let largeTitle = Font.system(size: 40, weight: .bold, design: .default)
    /// Panel headings. "INCLUDE".
    static let title = Font.system(size: 24, weight: .semibold)
    static let title2 = Font.system(size: 20, weight: .semibold)
    /// Empty-state heading. "No training data yet".
    static let heroTitle = Font.system(size: 26, weight: .semibold)
    static let headline = Font.system(size: 16, weight: .semibold)
    static let body = Font.system(size: 15, weight: .regular)
    static let callout = Font.system(size: 14, weight: .medium)
    static let caption = Font.system(size: 13, weight: .regular)
    static let caption2 = Font.system(size: 12, weight: .regular)

    /// Section eyebrows: "ACTIVE TRANSFERS". Pair with `Tracking.eyebrow`.
    static let eyebrow = Font.system(size: 11, weight: .semibold)
    /// Metric tile captions: "CLIPS / MIN".
    static let tileCaption = Font.system(size: 11, weight: .regular)

    /// Secondary button label.
    static let control = Font.system(size: 14, weight: .semibold)
    /// Primary button label.
    static let controlStrong = Font.system(size: 14, weight: .bold)
    /// Pill and status badge labels.
    static let pill = Font.system(size: 13, weight: .semibold)

    /// Every number the user might compare, copy or read off: counts, sizes,
    /// rates, confidences, IDs, durations. Prevents digit jitter on updates.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Small counts beside an eyebrow: "3 of 3 slots".
    static let monoSmall = mono(11)
    /// Values in a check list: "1.94 TB free".
    static let monoCaption = mono(12)
    static let monoMetric = mono(19, .medium)
    static let monoLarge = mono(30, .medium)
}

enum Tracking {
    static let eyebrow: CGFloat = 1.1
    /// Status badge label.
    static let badge: CGFloat = 0.26
    static let largeTitle: CGFloat = -0.8
}

// MARK: - Spacing

enum Spacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 6
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let section: CGFloat = 28
    /// Outer padding of the detail pane.
    static let pane: CGFloat = 40
}

// MARK: - Radius

enum Radius {
    static let chip: CGFloat = 8
    static let control: CGFloat = 11
    static let card: CGFloat = 12
    static let cardLarge: CGFloat = 14
    static let panel: CGFloat = 18
    static let pill: CGFloat = 999
}

// MARK: - Metrics

enum Metrics {
    /// Minimum touch target. Never go below this.
    static let touchTarget: CGFloat = 44
    static let sidebarWidth: CGFloat = 320
    /// Middle column in the three-column browser.
    static let listColumnWidth: CGFloat = 260
    static let progressBarHeight: CGFloat = 8
    static let progressBarHeightCompact: CGFloat = 6
    static let progressBarHeightFine: CGFloat = 4
    /// Hairline border on cards, tiles and controls.
    static let borderWidth: CGFloat = 1
    /// Dot inside a status badge.
    static let statusDot: CGFloat = 7
    /// Visible height of a filter pill. The hit area is still `touchTarget`.
    static let pillHeight: CGFloat = 36
    /// Line spacing for multi-line body copy (15 pt at 1.6 line height).
    static let paragraphLineSpacing: CGFloat = 9
    /// Dash and gap length of a dashed empty-state outline.
    static let dash: CGFloat = 4
    /// Illustration on a full-pane empty state.
    static let heroIcon: CGFloat = 132
    /// Max width of the text block on a full-pane empty state.
    static let heroTextWidth: CGFloat = 520
    /// Max width of the first-run preflight card.
    static let preflightWidth: CGFloat = 620
    /// Tinted circle behind a preflight check's dot.
    static let checkIndicator: CGFloat = 18
    /// Dot inside a preflight check indicator.
    static let checkDot: CGFloat = 6
}

// MARK: - Semantic state mapping

/// Maps pipeline state to color so the mapping is defined once. Do not
/// hand-pick a color at the call site.
enum StateTint {
    case idle, active, queued, complete, failed, quarantined

    var color: Color {
        switch self {
        case .idle:        return Palette.textQuaternary
        case .active:      return Palette.accent
        case .queued:      return Palette.warning
        case .complete:    return Palette.accent
        case .failed:      return Palette.danger
        case .quarantined: return Palette.danger
        }
    }

    var fill: Color {
        switch self {
        case .idle:        return Palette.surface
        case .active,
             .complete:    return Palette.accentFill
        case .queued:      return Palette.warningFill
        case .failed,
             .quarantined: return Palette.dangerFill
        }
    }

    var border: Color {
        switch self {
        case .idle: return Palette.borderMuted
        default:    return color.opacity(Opacity.tintBorder)
        }
    }

    /// Text on a badge in this state. Idle text must stay readable, so it
    /// does not use the decorative idle dot color.
    var label: Color {
        switch self {
        case .idle: return Palette.textMuted
        default:    return color
        }
    }
}

// MARK: - Helpers

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue:  Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
