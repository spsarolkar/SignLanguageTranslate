import SwiftUI

/// A compact notification banner showing download progress.
///
/// Appears when downloads are in progress and can be tapped
/// to navigate to the full downloads view.
///
/// Features:
/// - Circular progress indicator with percentage
/// - Download speed display (e.g., "2.5 MB/s")
/// - Estimated time remaining
/// - Smooth animations for progress updates
/// - Paused/No Network states with appropriate visuals
struct DownloadNotificationBanner: View {

    // MARK: - Environment

    @Environment(DownloadManager.self) private var downloadManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Properties

    @Binding var isPresented: Bool

    // MARK: - Body

    var body: some View {
        ZStack {
            if shouldShowBanner {
                Button {
                    isPresented = true
                } label: {
                    bannerContent
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: shouldShowBanner)
    }

    // MARK: - Banner Content

    private var bannerContent: some View {
        HStack(spacing: 12) {
            // Progress indicator with status-aware styling
            progressIndicator

            // Status and progress info
            VStack(alignment: .leading, spacing: 2) {
                // Primary status text
                Text(primaryStatusText)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                // Secondary info (speed + ETA or bytes progress)
                HStack(spacing: 6) {
                    Text(downloadManager.bytesProgressText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if downloadManager.isDownloading {
                        if !downloadManager.formattedDownloadRate.isEmpty && downloadManager.currentDownloadRate > 0 {
                            Text("•")
                                .foregroundStyle(.tertiary)
                            Text(downloadManager.formattedDownloadRate)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let eta = downloadManager.formattedTimeRemaining {
                            Text("•")
                                .foregroundStyle(.tertiary)
                            Text(eta)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .monospacedDigit()
            }

            Spacer()

            // Right side: percentage or status icon
            rightContent

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(bannerBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
    }

    // MARK: - Progress Indicator

    private var progressIndicator: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(statusColor.opacity(0.2), lineWidth: 3)

            // Progress ring
            Circle()
                .trim(from: 0, to: downloadManager.overallProgress)
                .stroke(statusColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: downloadManager.overallProgress)

            // Center icon for paused/no network states
            if downloadManager.isPaused {
                Image(systemName: "pause.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(statusColor)
            } else if !downloadManager.isNetworkAvailable {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.orange)
            }
        }
        .frame(width: 28, height: 28)
    }

    // MARK: - Right Content

    @ViewBuilder
    private var rightContent: some View {
        if downloadManager.isPaused {
            // Show pause indicator
            Image(systemName: "pause.circle.fill")
                .font(.title3)
                .foregroundStyle(.yellow)
        } else if !downloadManager.isNetworkAvailable {
            // Show network warning
            Image(systemName: "wifi.exclamationmark")
                .font(.title3)
                .foregroundStyle(.orange)
        } else {
            // Show percentage
            Text("\(downloadManager.progressPercentage)%")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(statusColor)
        }
    }

    // MARK: - Banner Background

    private var bannerBackground: some View {
        Group {
            if downloadManager.isPaused {
                Color.yellow.opacity(0.1)
                    .background(.ultraThinMaterial)
            } else if !downloadManager.isNetworkAvailable {
                Color.orange.opacity(0.1)
                    .background(.ultraThinMaterial)
            } else {
                Color.clear
                    .background(.ultraThinMaterial)
            }
        }
    }

    // MARK: - Computed Properties

    private var shouldShowBanner: Bool {
        downloadManager.isDownloading ||
        downloadManager.activeCount > 0 ||
        (downloadManager.isPaused && downloadManager.totalCount > 0 && !downloadManager.isComplete)
    }

    private var primaryStatusText: String {
        if !downloadManager.isNetworkAvailable {
            return "Waiting for Network..."
        } else if downloadManager.isPaused {
            return "Downloads Paused"
        } else {
            return downloadManager.statusText
        }
    }

    private var statusColor: Color {
        if downloadManager.isPaused {
            return .yellow
        } else if !downloadManager.isNetworkAvailable {
            return .orange
        } else if downloadManager.hasFailed {
            return .red
        } else {
            return .accentColor
        }
    }
}

// MARK: - Previews

#Preview("Downloading") {
    VStack {
        Spacer()
        DownloadNotificationBanner(isPresented: .constant(false))
    }
    .environment(DownloadManager())
}

#Preview("Paused State") {
    VStack {
        Spacer()
        DownloadNotificationBanner(isPresented: .constant(false))
    }
    .environment(DownloadManager())
}
