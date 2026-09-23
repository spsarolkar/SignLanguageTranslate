import SwiftUI

/// Control-filled button for secondary actions ("Pause All").
struct SecondaryButton: View {

    let title: String
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ButtonLabel(title: title, systemImage: systemImage)
        }
        .buttonStyle(SecondaryButtonStyle())
    }
}

// MARK: - Style

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        configuration.label
            .font(Typo.control)
            .foregroundStyle(Palette.textControl)
            .padding(.horizontal, Spacing.lg)
            .frame(minHeight: Metrics.touchTarget)
            .background(Palette.control, in: shape)
            .overlay(shape.strokeBorder(Palette.borderStrong, lineWidth: Metrics.borderWidth))
            .contentShape(shape)
            .opacity(opacity(pressed: configuration.isPressed))
    }

    private func opacity(pressed: Bool) -> Double {
        if !isEnabled { return Opacity.disabled }
        return pressed ? Opacity.pressed : 1
    }
}

#Preview("Secondary buttons") {
    HStack(spacing: Spacing.md) {
        SecondaryButton(title: "Pause All") {}
        SecondaryButton(title: "Import from Files", systemImage: "folder") {}
        SecondaryButton(title: "Disabled") {}
            .disabled(true)
        PrimaryButton(title: "Download All") {}
    }
    .padding(Spacing.xxl)
    .background(Palette.ground)
    .preferredColorScheme(.dark)
}
