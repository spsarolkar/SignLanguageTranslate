import SwiftUI

/// One transfer in a card: name and subtitle, a 6 pt bar, a mono value and a
/// trailing control. "Adjectives_5of8.zip · Adjectives · 6.4 / 9.4 GB · 41 MB/s".
///
/// Wide layout matches the artboard (name | bar | value | control). When the
/// row cannot fit that, it stacks: name and control on top, bar, then value.
struct TransferRow<Trailing: View>: View {

    let title: String
    let subtitle: String
    var subtitleTint: Color = Palette.textTertiary
    let progress: Double
    var tint: Color = Palette.accent
    let value: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        ViewThatFits(in: .horizontal) {
            wide
            stacked
        }
        .padding(.vertical, Spacing.md)
        .padding(.horizontal, Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: shape)
        .overlay(shape.strokeBorder(Palette.border, lineWidth: Metrics.borderWidth))
    }

    private var wide: some View {
        HStack(spacing: Spacing.lg) {
            names
                .frame(maxWidth: Metrics.transferNameWidth, alignment: .leading)
            bar
                .frame(minWidth: Metrics.transferBarMinWidth)
            // A shared minimum width keeps every row's bar the same length.
            valueText
                .frame(minWidth: Metrics.transferValueWidth, alignment: .trailing)
            trailing()
        }
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                names
                Spacer(minLength: Spacing.md)
                trailing()
            }
            bar
            valueText
        }
    }

    private var names: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(title)
                .font(Typo.control)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(subtitle)
                .font(Typo.caption2)
                .foregroundStyle(subtitleTint)
                .lineLimit(1)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var bar: some View {
        ProgressBar(value: progress, height: Metrics.progressBarHeightCompact, tint: tint)
    }

    private var valueText: some View {
        Text(value)
            .font(Typo.monoCaption)
            .foregroundStyle(Palette.textSecondary)
            .lineLimit(1)
            .fixedSize()
    }
}

// Preview values are placeholders, not measurements.
#Preview("Transfer rows") {
    VStack(spacing: Spacing.sm) {
        TransferRow(title: "Adjectives_5of8.zip", subtitle: "Adjectives", progress: 0.68,
                    value: "6.4 / 9.4 GB · 41 MB/s") {
            IconButton(systemImage: "pause.fill", accessibilityLabel: "Pause") {}
        }
        TransferRow(title: "Home_2of4.zip", subtitle: "Home · resumed", subtitleTint: Palette.warning,
                    progress: 0.12, tint: Palette.warning, value: "1.0 / 8.3 GB · 29 MB/s") {
            IconButton(systemImage: "pause.fill", accessibilityLabel: "Pause") {}
        }
        TransferRow(title: "People_3of5.zip", subtitle: "People", progress: 0.34,
                    value: "3.1 / 9.1 GB · 38 MB/s") {
            IconButton(systemImage: "pause.fill", accessibilityLabel: "Pause") {}
        }
        .frame(width: 340)
    }
    .padding(Spacing.xxl)
    .frame(width: 900)
    .background(Palette.ground)
    .preferredColorScheme(.dark)
}
