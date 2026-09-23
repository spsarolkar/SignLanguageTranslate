import SwiftUI

/// Surface container with a hairline border and rounded corners.
///
/// Use `.standard` for ordinary cards, `.raised` to lift a card off its
/// neighbors, and `.selected` for the active item in a list.
struct Card<Content: View>: View {

    enum Variant {
        case standard, raised, selected

        var fill: Color {
            switch self {
            case .standard:          return Palette.surface
            case .raised, .selected: return Palette.surfaceRaised
            }
        }

        var border: Color {
            switch self {
            case .standard, .raised: return Palette.border
            case .selected:          return Palette.borderSelected
            }
        }
    }

    var variant: Variant = .standard
    var padding: CGFloat = Spacing.lg
    var radius: CGFloat = Radius.card
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(variant.fill, in: shape)
            .overlay(shape.strokeBorder(variant.border, lineWidth: Metrics.borderWidth))
    }
}

#Preview("Card variants") {
    VStack(spacing: Spacing.md) {
        Card {
            Text("Standard").font(Typo.headline).foregroundStyle(Palette.textPrimary)
        }
        Card(variant: .raised) {
            Text("Raised").font(Typo.headline).foregroundStyle(Palette.textPrimary)
        }
        Card(variant: .selected) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("INCLUDE").font(Typo.headline).foregroundStyle(Palette.textPrimary)
                Text("Selected").font(Typo.caption2).foregroundStyle(Palette.textTertiary)
            }
        }
        Card(padding: Spacing.xxl, radius: Radius.panel) {
            Text("Panel").font(Typo.title).foregroundStyle(Palette.textPrimary)
        }
    }
    .padding(Spacing.xxl)
    .frame(width: 360)
    .background(Palette.ground)
    .preferredColorScheme(.dark)
}
