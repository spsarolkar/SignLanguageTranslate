import SwiftUI

/// Uppercase section eyebrow ("ACTIVE TRANSFERS") with optional trailing content.
struct SectionHeader<Trailing: View>: View {

    let eyebrow: String
    @ViewBuilder var trailing: () -> Trailing

    init(eyebrow: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.eyebrow = eyebrow
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(eyebrow)
                .font(Typo.eyebrow)
                .tracking(Tracking.eyebrow)
                .textCase(.uppercase)
                .foregroundStyle(Palette.textTertiary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Spacing.md)
            trailing()
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(eyebrow: String) {
        self.init(eyebrow: eyebrow) { EmptyView() }
    }
}

extension SectionHeader where Trailing == Text {
    /// Trailing text in mono, for counts such as "3 of 3 slots".
    init(eyebrow: String, trailing: String) {
        self.init(eyebrow: eyebrow) {
            Text(trailing)
                .font(Typo.monoSmall)
                .foregroundStyle(Palette.textTertiary)
        }
    }
}

#Preview("Section headers") {
    VStack(spacing: Spacing.xxl) {
        SectionHeader(eyebrow: "Datasets")
        SectionHeader(eyebrow: "Active transfers", trailing: "3 of 3 slots")
        SectionHeader(eyebrow: "Categories") {
            Button("Browse ingested →") {}
                .font(Typo.pill)
                .foregroundStyle(Palette.accent)
        }
    }
    .padding(Spacing.xxl)
    .frame(width: 480)
    .background(Palette.ground)
    .preferredColorScheme(.dark)
}
