import SwiftUI

/// Accent-filled button for the main action on a screen or panel ("Download All").
struct PrimaryButton: View {

    let title: String
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ButtonLabel(title: title, systemImage: systemImage)
        }
        .buttonStyle(PrimaryButtonStyle())
    }
}

// MARK: - Style

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        configuration.label
            .font(Typo.controlStrong)
            .foregroundStyle(Palette.ground)
            .padding(.horizontal, Spacing.lg)
            .frame(minHeight: Metrics.touchTarget)
            .background(Palette.accent, in: shape)
            .contentShape(shape)
            .opacity(opacity(pressed: configuration.isPressed))
    }

    private func opacity(pressed: Bool) -> Double {
        if !isEnabled { return Opacity.disabled }
        return pressed ? Opacity.pressed : 1
    }
}

/// Title with an optional leading SF Symbol, shared by the button components.
/// Avoids `Label`, which the SwiftData model shadows in this module (D7).
struct ButtonLabel: View {
    let title: String
    let systemImage: String?

    var body: some View {
        HStack(spacing: Spacing.sm) {
            if let systemImage {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
            }
            Text(title)
                .lineLimit(1)
        }
    }
}

#Preview("Primary buttons") {
    VStack(alignment: .leading, spacing: Spacing.md) {
        PrimaryButton(title: "Download All") {}
        PrimaryButton(title: "Start Training", systemImage: "play.fill") {}
        PrimaryButton(title: "Disabled") {}
            .disabled(true)
    }
    .padding(Spacing.xxl)
    .background(Palette.ground)
    .preferredColorScheme(.dark)
}
