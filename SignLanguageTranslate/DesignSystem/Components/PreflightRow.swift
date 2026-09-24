import SwiftUI

/// One check in a preflight list: tinted dot, label, mono value.
/// "Free storage · 1.94 TB", amber when a check needs attention.
struct PreflightRow: View {

    let label: String
    let value: String
    let state: StateTint

    var body: some View {
        HStack(spacing: Spacing.md) {
            Circle()
                .fill(state.color.opacity(Opacity.selectedFill))
                .frame(width: Metrics.checkIndicator, height: Metrics.checkIndicator)
                .overlay(
                    Circle()
                        .fill(state.color)
                        .frame(width: Metrics.checkDot, height: Metrics.checkDot)
                )
                .accessibilityHidden(true)
            Text(label)
                .font(Typo.callout)
                .foregroundStyle(Palette.textSecondary)
            Spacer(minLength: Spacing.md)
            Text(value)
                .font(Typo.monoCaption)
                .foregroundStyle(state.label)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Preflight rows") {
    Card(padding: Spacing.xl, radius: Radius.cardLarge) {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(eyebrow: "Preflight")
            PreflightRow(label: "Free storage", value: "1.94 TB", state: .complete)
            PreflightRow(label: "Network", value: "Wi-Fi", state: .complete)
            PreflightRow(label: "Low Data Mode", value: "Off", state: .complete)
            PreflightRow(label: "Low Power Mode", value: "On — will throttle", state: .queued)
            PreflightRow(label: "Network", value: "Checking…", state: .idle)
        }
    }
    .frame(width: Metrics.preflightWidth)
    .padding(Spacing.xl)
    .background(Palette.ground)
}
