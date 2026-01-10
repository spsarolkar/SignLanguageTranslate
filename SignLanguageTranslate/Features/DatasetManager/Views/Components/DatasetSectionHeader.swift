import SwiftUI

/// A section header for dataset lists with title, count badge, and optional action button
struct DatasetSectionHeader: View {
    let title: String
    let count: Int
    let systemImage: String?
    let isExpanded: Bool
    let action: (() -> Void)?
    let actionLabel: String?
    let actionIcon: String?

    init(
        title: String,
        count: Int,
        systemImage: String? = nil,
        isExpanded: Bool = true,
        action: (() -> Void)? = nil,
        actionLabel: String? = nil,
        actionIcon: String? = nil
    ) {
        self.title = title
        self.count = count
        self.systemImage = systemImage
        self.isExpanded = isExpanded
        self.action = action
        self.actionLabel = actionLabel
        self.actionIcon = actionIcon
    }

    var body: some View {
        HStack(spacing: 8) {
            // Section icon (optional)
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Title
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            // Count badge
            if count > 0 {
                Text("\(count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(badgeColor)
                    )
            }

            Spacer()

            // Action button (optional)
            if let action, let actionLabel {
                Button(action: action) {
                    HStack(spacing: 4) {
                        if let actionIcon {
                            Image(systemName: actionIcon)
                                .font(.caption)
                        }
                        Text(actionLabel)
                            .font(.caption.weight(.medium))
                    }
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.tint)
            }

            // Expand/collapse indicator
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .animation(.easeInOut(duration: 0.2), value: isExpanded)
        }
        .padding(.vertical, 4)
    }

    private var badgeColor: Color {
        switch title.lowercased() {
        case let t where t.contains("download"):
            return .blue
        case let t where t.contains("ready") || t.contains("complete"):
            return .green
        case let t where t.contains("fail"):
            return .red
        case let t where t.contains("available"):
            return .gray
        default:
            return .secondary
        }
    }
}

// MARK: - Convenience Initializers

extension DatasetSectionHeader {
    /// Header for "Available to Download" section
    static func available(count: Int, isExpanded: Bool = true) -> DatasetSectionHeader {
        DatasetSectionHeader(
            title: "Available to Download",
            count: count,
            systemImage: "arrow.down.circle",
            isExpanded: isExpanded
        )
    }

    /// Header for "Downloading" section
    static func downloading(count: Int, isExpanded: Bool = true, onPauseAll: (() -> Void)? = nil) -> DatasetSectionHeader {
        DatasetSectionHeader(
            title: "Downloading",
            count: count,
            systemImage: "arrow.down.circle.fill",
            isExpanded: isExpanded,
            action: onPauseAll,
            actionLabel: onPauseAll != nil ? "Pause All" : nil,
            actionIcon: "pause.fill"
        )
    }

    /// Header for "Ready to Use" section
    static func ready(count: Int, isExpanded: Bool = true) -> DatasetSectionHeader {
        DatasetSectionHeader(
            title: "Ready to Use",
            count: count,
            systemImage: "checkmark.circle.fill",
            isExpanded: isExpanded
        )
    }

    /// Header for "Failed" section
    static func failed(count: Int, isExpanded: Bool = true, onRetryAll: (() -> Void)? = nil) -> DatasetSectionHeader {
        DatasetSectionHeader(
            title: "Failed",
            count: count,
            systemImage: "exclamationmark.circle.fill",
            isExpanded: isExpanded,
            action: onRetryAll,
            actionLabel: onRetryAll != nil ? "Retry All" : nil,
            actionIcon: "arrow.clockwise"
        )
    }
}

// MARK: - Previews

#Preview("Available Section") {
    List {
        Section {
            Text("Dataset 1")
            Text("Dataset 2")
        } header: {
            DatasetSectionHeader.available(count: 2)
        }
    }
    .listStyle(.insetGrouped)
}

#Preview("Downloading Section") {
    List {
        Section {
            Text("Dataset 1")
        } header: {
            DatasetSectionHeader.downloading(count: 1, onPauseAll: {})
        }
    }
    .listStyle(.insetGrouped)
}

#Preview("All Sections") {
    List {
        Section {
            Text("INCLUDE")
        } header: {
            DatasetSectionHeader.available(count: 1)
        }

        Section {
            Text("ISL-CSLTR")
        } header: {
            DatasetSectionHeader.downloading(count: 1, onPauseAll: {})
        }

        Section {
            Text("Custom Dataset")
        } header: {
            DatasetSectionHeader.ready(count: 1)
        }

        Section {
            Text("Failed Dataset")
        } header: {
            DatasetSectionHeader.failed(count: 1, onRetryAll: {})
        }
    }
    .listStyle(.insetGrouped)
}
