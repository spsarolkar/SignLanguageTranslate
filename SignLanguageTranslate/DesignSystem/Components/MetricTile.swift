import SwiftUI

/// Inset stat tile: a mono value over an uppercase caption ("214" / "CLIPS / MIN").
///
/// `tint` colors the value. Set `highlighted` to also tint the border, for a
/// value that needs attention (for example, a quarantine count).
struct MetricTile: View {

    let value: String
    let caption: String
    var tint: Color = Palette.textPrimary
    var highlighted: Bool = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(value)
                .font(Typo.monoMetric)
                .foregroundStyle(tint)
                .lineLimit(1)
            Text(caption)
                .font(Typo.tileCaption)
                .textCase(.uppercase)
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.well, in: shape)
        .overlay(shape.strokeBorder(border, lineWidth: Metrics.borderWidth))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption)
        .accessibilityValue(value)
    }

    private var border: Color {
        highlighted ? tint.opacity(Opacity.tintBorder) : Palette.borderSubtle
    }
}

// Preview values are placeholders, not measurements.
#Preview("Metric tiles") {
    HStack(spacing: Spacing.md) {
        MetricTile(value: "214", caption: "Clips / min")
        MetricTile(value: "15", caption: "Sampled fps")
        MetricTile(value: "0.94", caption: "Mean conf", tint: Palette.accent)
        MetricTile(value: "64", caption: "Quarantined", tint: Palette.danger, highlighted: true)
    }
    .padding(Spacing.xxl)
    .frame(width: 640)
    .background(Palette.ground)
    .preferredColorScheme(.dark)
}
