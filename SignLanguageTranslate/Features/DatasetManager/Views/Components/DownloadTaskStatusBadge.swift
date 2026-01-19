import SwiftUI

/// A color-coded badge displaying the status of a download task.
///
/// Supports two display modes:
/// - Compact: Shows only the icon
/// - Full: Shows icon with status text
///
/// For active states (downloading, extracting, queued), the badge displays a subtle animation.
struct DownloadTaskStatusBadge: View {

    // MARK: - Properties

    let status: DownloadTaskStatus
    let mode: DisplayMode

    // MARK: - State

    @State private var isAnimating = false

    // MARK: - Display Mode

    enum DisplayMode {
        case compact
        case full
    }

    // MARK: - Initialization

    init(status: DownloadTaskStatus, mode: DisplayMode = .full) {
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

            Text(status.displayName)
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
        .fixedSize(horizontal: true, vertical: false) // Prevent text compression
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(status.displayName)")
    }
}

// MARK: - Previews

#Preview("All Statuses - Full Mode") {
    VStack(spacing: 12) {
        ForEach(DownloadTaskStatus.allCases, id: \.self) { status in
            HStack {
                Text(status.displayName)
                    .frame(width: 100, alignment: .leading)
                Spacer()
                DownloadTaskStatusBadge(status: status, mode: .full)
            }
        }
    }
    .padding()
}

#Preview("All Statuses - Compact Mode") {
    HStack(spacing: 16) {
        ForEach(DownloadTaskStatus.allCases, id: \.self) { status in
            DownloadTaskStatusBadge(status: status, mode: .compact)
        }
    }
    .padding()
}

#Preview("Active Status Animation") {
    VStack(spacing: 20) {
        DownloadTaskStatusBadge(status: .downloading, mode: .full)
        DownloadTaskStatusBadge(status: .extracting, mode: .full)
        DownloadTaskStatusBadge(status: .queued, mode: .full)
    }
    .padding()
}

#Preview("Badge in Context") {
    VStack(alignment: .leading, spacing: 16) {
        HStack {
            Text("Animals Part 1")
                .font(.headline)
            Spacer()
            DownloadTaskStatusBadge(status: .completed, mode: .full)
        }

        HStack {
            Text("Greetings Part 2")
                .font(.headline)
            Spacer()
            DownloadTaskStatusBadge(status: .downloading, mode: .full)
        }

        HStack {
            Text("Jobs Part 1")
                .font(.headline)
            Spacer()
            DownloadTaskStatusBadge(status: .failed, mode: .full)
        }
    }
    .padding()
}
