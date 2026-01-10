import SwiftUI

/// Displays download progress for a dataset.
///
/// Shows:
/// - Linear progress bar with animation
/// - Percentage text
/// - Parts progress (e.g., "12/46 parts")
/// - Bytes downloaded vs total
/// - Optional cancel button
struct DatasetProgressIndicator: View {

    // MARK: - Properties

    let progress: Double
    let downloadedBytes: Int64
    let totalBytes: Int64
    let downloadedParts: Int
    let totalParts: Int
    let showCancelButton: Bool
    let onCancel: (() -> Void)?

    // MARK: - Initialization

    init(
        progress: Double,
        downloadedBytes: Int64,
        totalBytes: Int64,
        downloadedParts: Int,
        totalParts: Int,
        showCancelButton: Bool = false,
        onCancel: (() -> Void)? = nil
    ) {
        self.progress = progress
        self.downloadedBytes = downloadedBytes
        self.totalBytes = totalBytes
        self.downloadedParts = downloadedParts
        self.totalParts = totalParts
        self.showCancelButton = showCancelButton
        self.onCancel = onCancel
    }

    /// Convenience initializer using a Dataset
    init(dataset: Dataset, showCancelButton: Bool = false, onCancel: (() -> Void)? = nil) {
        self.init(
            progress: dataset.downloadProgress,
            downloadedBytes: dataset.downloadedBytes,
            totalBytes: dataset.totalBytes,
            downloadedParts: dataset.downloadedParts,
            totalParts: dataset.totalParts,
            showCancelButton: showCancelButton,
            onCancel: onCancel
        )
    }

    // MARK: - Computed Properties

    private var percentageText: String {
        "\(Int(progress * 100))%"
    }

    private var partsText: String {
        "\(downloadedParts)/\(totalParts) parts"
    }

    private var bytesText: String {
        "\(FileManager.formattedSize(downloadedBytes)) / \(FileManager.formattedSize(totalBytes))"
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            progressBar
            progressDetails
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Download progress \(percentageText), \(partsText), \(bytesText)")
        .accessibilityValue("\(Int(progress * 100)) percent complete")
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.2))

                // Progress fill
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.blue)
                    .frame(width: geometry.size.width * CGFloat(min(max(progress, 0), 1)))
                    .animation(.easeInOut(duration: 0.3), value: progress)
            }
        }
        .frame(height: 8)
    }

    // MARK: - Progress Details

    private var progressDetails: some View {
        HStack(spacing: 8) {
            // Percentage
            Text(percentageText)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .monospacedDigit()

            // Parts progress
            Text(partsText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Spacer()

            // Bytes progress
            Text(bytesText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            // Cancel button
            if showCancelButton, let onCancel {
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel download")
            }
        }
    }
}

// MARK: - Compact Progress Indicator

/// A compact version of the progress indicator for use in list rows.
struct DatasetProgressIndicatorCompact: View {

    // MARK: - Properties

    let progress: Double
    let downloadedBytes: Int64
    let totalBytes: Int64

    // MARK: - Initialization

    init(progress: Double, downloadedBytes: Int64, totalBytes: Int64) {
        self.progress = progress
        self.downloadedBytes = downloadedBytes
        self.totalBytes = totalBytes
    }

    /// Convenience initializer using a Dataset
    init(dataset: Dataset) {
        self.init(
            progress: dataset.downloadProgress,
            downloadedBytes: dataset.downloadedBytes,
            totalBytes: dataset.totalBytes
        )
    }

    // MARK: - Computed Properties

    private var percentageText: String {
        "\(Int(progress * 100))%"
    }

    private var bytesText: String {
        "\(FileManager.formattedSize(downloadedBytes)) / \(FileManager.formattedSize(totalBytes))"
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.2))

                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.blue)
                        .frame(width: geometry.size.width * CGFloat(min(max(progress, 0), 1)))
                        .animation(.easeInOut(duration: 0.3), value: progress)
                }
            }
            .frame(height: 6)

            // Progress text
            HStack {
                Text(percentageText)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .monospacedDigit()

                Spacer()

                Text(bytesText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Download progress \(percentageText)")
        .accessibilityValue("\(Int(progress * 100)) percent complete")
    }
}

// MARK: - Previews

#Preview("Full Progress Indicator") {
    VStack(spacing: 24) {
        DatasetProgressIndicator(
            progress: 0.45,
            downloadedBytes: 4_500_000_000,
            totalBytes: 10_000_000_000,
            downloadedParts: 12,
            totalParts: 46,
            showCancelButton: true,
            onCancel: {}
        )

        DatasetProgressIndicator(
            progress: 0.25,
            downloadedBytes: 12_500_000_000,
            totalBytes: 50_000_000_000,
            downloadedParts: 12,
            totalParts: 46,
            showCancelButton: false
        )

        DatasetProgressIndicator(
            progress: 0.0,
            downloadedBytes: 0,
            totalBytes: 50_000_000_000,
            downloadedParts: 0,
            totalParts: 46
        )

        DatasetProgressIndicator(
            progress: 1.0,
            downloadedBytes: 50_000_000_000,
            totalBytes: 50_000_000_000,
            downloadedParts: 46,
            totalParts: 46
        )
    }
    .padding()
}

#Preview("Compact Progress Indicator") {
    VStack(spacing: 16) {
        DatasetProgressIndicatorCompact(
            progress: 0.45,
            downloadedBytes: 4_500_000_000,
            totalBytes: 10_000_000_000
        )

        DatasetProgressIndicatorCompact(
            progress: 0.75,
            downloadedBytes: 37_500_000_000,
            totalBytes: 50_000_000_000
        )
    }
    .padding()
    .frame(width: 300)
}

#Preview("With Dataset Model") {
    VStack(spacing: 24) {
        DatasetProgressIndicator(
            dataset: .previewIncludeDownloading,
            showCancelButton: true,
            onCancel: {}
        )

        DatasetProgressIndicatorCompact(dataset: .previewIncludeDownloading)
    }
    .padding()
}
