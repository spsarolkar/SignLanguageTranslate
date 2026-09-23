import SwiftUI

/// Pill with a status dot and label, tinted by pipeline state.
/// Sits at the top right of a screen: "Processing", "Extracting", "Idle".
struct StatusBadge: View {

    let state: StateTint
    let text: String

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Circle()
                .fill(state.color)
                .frame(width: Metrics.statusDot, height: Metrics.statusDot)
                .accessibilityHidden(true)
            Text(text)
                .font(Typo.pill)
                .tracking(Tracking.badge)
                .foregroundStyle(state.label)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(state.fill, in: Capsule())
        .overlay(Capsule().strokeBorder(state.border, lineWidth: Metrics.borderWidth))
        .accessibilityElement(children: .combine)
    }
}

#Preview("Status badges") {
    VStack(alignment: .trailing, spacing: Spacing.md) {
        StatusBadge(state: .active, text: "Processing")
        StatusBadge(state: .complete, text: "Complete")
        StatusBadge(state: .queued, text: "Extracting")
        StatusBadge(state: .failed, text: "Failed")
        StatusBadge(state: .quarantined, text: "Quarantined")
        StatusBadge(state: .idle, text: "Idle")
    }
    .padding(Spacing.xxl)
    .background(Palette.ground)
    .preferredColorScheme(.dark)
}
