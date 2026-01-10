import SwiftUI

/// A color-coded badge displaying the download status of a dataset.
///
/// Supports two display modes:
/// - Compact: Shows only the icon
/// - Full: Shows icon with status text
///
/// For active states (downloading, processing), the badge displays a subtle animation.
struct DatasetStatusBadge: View {

    // MARK: - Properties

    let status: DownloadStatus
    let mode: DisplayMode

    // MARK: - State

    @State private var isAnimating = false

    // MARK: - Display Mode

    enum DisplayMode {
        case compact
        case full
    }

    // MARK: - Initialization

    init(status: DownloadStatus, mode: DisplayMode = .full) {
        self.status = status
        self.mode = mode
    }

    // MARK: - Body

    var body: some View {
        Group {
            switch mode {
            case .compact:
                compactBadge
            case .full:
                fullBadge
            }
        }
        .onAppear {
            if status.isActive {
                isAnimating = true
            }
        }
        .onChange(of: status) { _, newStatus in
            isAnimating = newStatus.isActive
        }
    }

    // MARK: - Compact Badge

    private var compactBadge: some View {
        Image(systemName: status.iconName)
            .font(.body)
            .foregroundStyle(status.color)
            .symbolEffect(.pulse, options: .repeating, isActive: status.isActive && isAnimating)
            .accessibilityLabel(status.displayName)
    }

    // MARK: - Full Badge

    private var fullBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: status.iconName)
                .font(.caption)
                .symbolEffect(.pulse, options: .repeating, isActive: status.isActive && isAnimating)

            Text(status.shortDisplayName)
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundStyle(status.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(status.color.opacity(0.15))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(status.displayName)")
    }
}

// MARK: - Previews

#Preview("All Statuses - Full Mode") {
    VStack(spacing: 12) {
        ForEach(DownloadStatus.allCases) { status in
            HStack {
                Text(status.displayName)
                    .frame(width: 100, alignment: .leading)
                Spacer()
                DatasetStatusBadge(status: status, mode: .full)
            }
        }
    }
    .padding()
}

#Preview("All Statuses - Compact Mode") {
    HStack(spacing: 16) {
        ForEach(DownloadStatus.allCases) { status in
            DatasetStatusBadge(status: status, mode: .compact)
        }
    }
    .padding()
}

#Preview("Active Status Animation") {
    VStack(spacing: 20) {
        DatasetStatusBadge(status: .downloading, mode: .full)
        DatasetStatusBadge(status: .processing, mode: .full)
    }
    .padding()
}

#Preview("Badge in Context") {
    VStack(alignment: .leading, spacing: 16) {
        HStack {
            Text("INCLUDE Dataset")
                .font(.headline)
            Spacer()
            DatasetStatusBadge(status: .completed, mode: .full)
        }

        HStack {
            Text("ISL-CSLTR Dataset")
                .font(.headline)
            Spacer()
            DatasetStatusBadge(status: .downloading, mode: .full)
        }
    }
    .padding()
}
