import SwiftUI

/// Compact grid tile: name, 4 pt bar and a mono detail ("4 / 8").
struct CategoryTile: View {

    let name: String
    let progress: Double
    var tint: Color = Palette.accent
    let detail: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(name)
                .font(Typo.pill)
                .foregroundStyle(Palette.textControl)
                .lineLimit(1)
                .truncationMode(.tail)
            ProgressBar(value: progress, height: Metrics.progressBarHeightFine, tint: tint)
            Text(detail)
                .font(Typo.monoSmall)
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: shape)
        .overlay(shape.strokeBorder(Palette.border, lineWidth: Metrics.borderWidth))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(detail)
    }
}

// Preview values are placeholders, not measurements.
#Preview("Category tiles") {
    LazyVGrid(
        columns: [GridItem(.adaptive(minimum: Metrics.categoryTileMinWidth), spacing: Spacing.md)],
        spacing: Spacing.md
    ) {
        CategoryTile(name: "Adjectives", progress: 0.5, tint: Palette.warning, detail: "4 / 8")
        CategoryTile(name: "Animals", progress: 1, detail: "2 / 2")
        CategoryTile(name: "Transportation", progress: 0, detail: "0 / 2")
        CategoryTile(name: "Days & Time", progress: 1, detail: "3 / 3")
        CategoryTile(name: "Home", progress: 0.25, tint: Palette.warning, detail: "1 / 4")
    }
    .padding(Spacing.xxl)
    .frame(width: 700)
    .background(Palette.ground)
    .preferredColorScheme(.dark)
}
