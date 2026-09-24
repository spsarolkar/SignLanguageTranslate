import SwiftUI

/// Square, control-filled, icon-only button at the minimum touch target
/// (row pause / resume / retry). The accessibility label is required.
struct IconButton: View {

    let systemImage: String
    let accessibilityLabel: String
    var tint: Color = Palette.textSecondary
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.iconButton, style: .continuous)
        Button(action: action) {
            Image(systemName: systemImage)
                .font(Typo.control)
                .foregroundStyle(tint)
                .frame(width: Metrics.touchTarget, height: Metrics.touchTarget)
                .background(Palette.control, in: shape)
                .overlay(shape.strokeBorder(Palette.borderStrong, lineWidth: Metrics.borderWidth))
                .contentShape(shape)
                .opacity(isEnabled ? 1 : Opacity.disabled)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

#Preview("Icon buttons") {
    HStack(spacing: Spacing.md) {
        IconButton(systemImage: "pause.fill", accessibilityLabel: "Pause") {}
        IconButton(systemImage: "play.fill", accessibilityLabel: "Resume", tint: Palette.accent) {}
        IconButton(systemImage: "arrow.clockwise", accessibilityLabel: "Retry", tint: Palette.danger) {}
        IconButton(systemImage: "checkmark", accessibilityLabel: "Done") {}
            .disabled(true)
    }
    .padding(Spacing.xxl)
    .background(Palette.ground)
    .preferredColorScheme(.dark)
}
