import SwiftUI

/// Horizontal progress bar on a `Palette.track` background.
///
/// `value` is the complete fraction, drawn solid. `inFlight` is an extra
/// fraction drawn after it in the tint at reduced opacity (for example,
/// parts currently downloading). Both are clamped so the total never exceeds 1.
///
/// Heights: `Metrics.progressBarHeight` (dataset), `progressBarHeightCompact`
/// (transfer row), `progressBarHeightFine` (compact tiles).
struct ProgressBar: View {

    let value: Double
    var inFlight: Double = 0
    var height: CGFloat = Metrics.progressBarHeight
    var tint: Color = Palette.accent

    private var complete: Double { min(max(value, 0), 1) }
    private var pending: Double { min(max(inFlight, 0), 1 - complete) }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                Rectangle()
                    .fill(tint)
                    .frame(width: proxy.size.width * complete)
                Rectangle()
                    .fill(tint.opacity(Opacity.inFlight))
                    .frame(width: proxy.size.width * pending)
                Spacer(minLength: 0)
            }
        }
        .frame(height: height)
        .background(Palette.track)
        .clipShape(Capsule())
        .accessibilityElement()
        .accessibilityValue(Text(complete, format: .percent.precision(.fractionLength(0))))
    }
}

#Preview("Progress bars") {
    VStack(alignment: .leading, spacing: Spacing.xl) {
        ProgressBar(value: 0.43, inFlight: 0.09)
        ProgressBar(value: 0.68, height: Metrics.progressBarHeightCompact)
        ProgressBar(value: 0.12, height: Metrics.progressBarHeightCompact, tint: Palette.warning)
        ProgressBar(value: 0.5, height: Metrics.progressBarHeightFine)
        ProgressBar(value: 0, height: Metrics.progressBarHeightFine)
        ProgressBar(value: 1, inFlight: 0.5)
    }
    .padding(Spacing.xxl)
    .frame(width: 400)
    .background(Palette.ground)
    .preferredColorScheme(.dark)
}
