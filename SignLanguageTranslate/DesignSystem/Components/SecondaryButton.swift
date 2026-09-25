import SwiftUI

/// Control-filled button for secondary actions ("Pause All").
struct SecondaryButton: View {

    let title: String
    var systemImage: String? = nil
    var size: ButtonSize = .regular
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ButtonLabel(title: title, systemImage: systemImage)
        }
        .buttonStyle(SecondaryButtonStyle(size: size))
    }
}

// MARK: - Style

struct SecondaryButtonStyle: ButtonStyle {
    var size: ButtonSize = .regular
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: size.radius, style: .continuous)
        configuration.label
            .font(size == .large ? Typo.controlLarge : Typo.control)
            .foregroundStyle(Palette.textControl)
            .padding(.horizontal, size.horizontalPadding)
            .frame(minHeight: size.minHeight)
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
        SecondaryButton(title: "Import from Files", size: .large) {}
        SecondaryButton(title: "Disabled") {}
            .disabled(true)
        PrimaryButton(title: "Download All") {}
    }
    .padding(Spacing.xxl)
    .background(Palette.ground)
    .preferredColorScheme(.dark)
}
