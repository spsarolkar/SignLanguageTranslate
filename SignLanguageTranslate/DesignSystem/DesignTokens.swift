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
    /// Track behind a progress bar.
    static let track = Color(hex: 0x232930)

    static let textPrimary = Color(hex: 0xEEF1F3)
    static let textSecondary = Color(hex: 0xC9D1D8)
    /// Captions and labels. Passes 4.5:1 on `surface`.
    static let textTertiary = Color(hex: 0x8A949D)
    /// Decorative only — do not use for text that must be read.
    static let textQuaternary = Color(hex: 0x6C7A85)

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
    static let accentFill = Color(hex: 0x5EC8A8).opacity(0.12)
    static let warningFill = Color(hex: 0xE0A458).opacity(0.12)
    static let dangerFill = Color(hex: 0xE5695B).opacity(0.12)
}

// MARK: - Typography

enum Typo {
    /// Screen titles. "Data Pipeline".
    static let largeTitle = Font.system(size: 40, weight: .bold, design: .default)
    /// Panel headings. "INCLUDE".
    static let title = Font.system(size: 24, weight: .semibold)
    static let title2 = Font.system(size: 20, weight: .semibold)
    static let headline = Font.system(size: 16, weight: .semibold)
    static let body = Font.system(size: 15, weight: .regular)
    static let callout = Font.system(size: 14, weight: .medium)
    static let caption = Font.system(size: 13, weight: .regular)
    static let caption2 = Font.system(size: 12, weight: .regular)

    /// Section eyebrows: "ACTIVE TRANSFERS". Pair with `Tracking.eyebrow`.
    static let eyebrow = Font.system(size: 11, weight: .semibold)

    /// Every number the user might compare, copy or read off: counts, sizes,
    /// rates, confidences, IDs, durations. Prevents digit jitter on updates.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static let monoMetric = mono(19, .medium)
    static let monoLarge = mono(30, .medium)
}

enum Tracking {
    static let eyebrow: CGFloat = 1.1
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
