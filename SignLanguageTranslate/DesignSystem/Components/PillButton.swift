import SwiftUI

/// Fully rounded filter chip. The visible pill is `Metrics.pillHeight` tall;
/// the hit area is padded to `Metrics.touchTarget`.
struct PillButton: View {

    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Typo.pill)
                .lineLimit(1)
                .foregroundStyle(isSelected ? Palette.accent : Palette.textMuted)
                .padding(.horizontal, Spacing.md)
                .frame(minHeight: Metrics.pillHeight)
                .background(fill, in: Capsule())
                .overlay(Capsule().strokeBorder(border, lineWidth: Metrics.borderWidth))
                .frame(minHeight: Metrics.touchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var fill: Color {
        isSelected ? Palette.accent.opacity(Opacity.selectedFill) : Palette.surface
    }

    private var border: Color {
        isSelected ? Palette.accent.opacity(Opacity.selectedBorder) : Palette.border
    }
}

#Preview("Pill buttons") {
    struct Demo: View {
        @State private var selected = "Animals"
        let names = ["Animals", "Adjectives", "Clothes", "Days & Time", "Greetings"]

        var body: some View {
            HStack(spacing: Spacing.sm) {
                ForEach(names, id: \.self) { name in
                    PillButton(title: name, isSelected: name == selected) {
                        selected = name
                    }
                }
            }
        }
    }

    return Demo()
        .padding(Spacing.xxl)
        .background(Palette.ground)
        .preferredColorScheme(.dark)
}
