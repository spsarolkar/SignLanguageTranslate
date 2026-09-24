import SwiftUI

/// Empty inline list state: dashed outline, title and a secondary line.
/// "Nothing downloaded".
struct DashedEmptyCard: View {

    let title: String
    let message: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(Typo.callout)
                .foregroundStyle(Palette.textMuted)
            Text(message)
                .font(Typo.caption2)
                .foregroundStyle(Palette.textTertiary)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            shape.strokeBorder(
                Palette.borderMuted,
                style: StrokeStyle(lineWidth: Metrics.borderWidth, dash: [Metrics.dash, Metrics.dash])
            )
        )
        .accessibilityElement(children: .combine)
    }
}

#Preview("Dashed empty card") {
    DashedEmptyCard(
        title: "Nothing downloaded",
        message: "Datasets appear here once a download starts."
    )
    .frame(width: Metrics.sidebarWidth)
    .padding(Spacing.xl)
    .background(Palette.chrome)
}
