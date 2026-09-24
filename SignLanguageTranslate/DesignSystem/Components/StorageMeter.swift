import SwiftUI

/// Sidebar footer: caption, mono value and a thin usage bar.
/// "Storage · 1.6 TB free of 2 TB".
struct StorageMeter: View {

    var title: String = "Storage"
    let value: String
    /// Used fraction of the volume, 0...1.
    let usedFraction: Double
    var tint: Color = Palette.textQuaternary

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(Typo.caption2)
                        .foregroundStyle(Palette.textTertiary)
                    Spacer(minLength: Spacing.sm)
                    Text(value)
                        .font(Typo.monoCaption)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                }
                ProgressBar(value: usedFraction, height: Metrics.progressBarHeightFine, tint: tint)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

// Preview values are placeholders, not measurements.
#Preview("Storage meter") {
    VStack(spacing: Spacing.md) {
        StorageMeter(value: "1.6 TB free of 2 TB", usedFraction: 0.21)
        StorageMeter(value: "80 GB free of 2 TB", usedFraction: 0.96, tint: Palette.warning)
    }
    .padding(Spacing.xl)
    .frame(width: Metrics.sidebarWidth)
    .background(Palette.chrome)
    .preferredColorScheme(.dark)
}
