import SwiftUI

/// Accent-filled button for the main action on a screen or panel ("Download All").
struct PrimaryButton: View {

    let title: String
    var systemImage: String? = nil
    var size: ButtonSize = .regular
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ButtonLabel(title: title, systemImage: systemImage)
        }
        .buttonStyle(PrimaryButtonStyle(size: size))
    }
}

// MARK: - Style

struct PrimaryButtonStyle: ButtonStyle {
    var size: ButtonSize = .regular
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: size.radius, style: .continuous)
        configuration.label
            .font(size == .large ? Typo.controlStrongLarge : Typo.controlStrong)
            .foregroundStyle(Palette.ground)
            .padding(.horizontal, size.horizontalPadding)
            .frame(minHeight: size.minHeight)
            .background(Palette.accent, in: shape)
            .contentShape(shape)
            .opacity(opacity(pressed: configuration.isPressed))
    }

    private func opacity(pressed: Bool) -> Double {
        if !isEnabled { return Opacity.disabled }
        return pressed ? Opacity.pressed : 1
    }
}

/// Size shared by `PrimaryButton` and `SecondaryButton`. `.large` is for hero
/// actions on an empty state ("Download INCLUDE"); everything else is `.regular`.
enum ButtonSize {
    case regular, large

    var minHeight: CGFloat {
        self == .large ? Metrics.controlHeightLarge : Metrics.touchTarget
    }

    var horizontalPadding: CGFloat {
        self == .large ? Spacing.xxl : Spacing.lg
    }

    var radius: CGFloat {
        self == .large ? Radius.cardLarge : Radius.control
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
        PrimaryButton(title: "Download INCLUDE · 56.8 GB", size: .large) {}
    }
    .padding(Spacing.xxl)
    .background(Palette.ground)
    .preferredColorScheme(.dark)
}
