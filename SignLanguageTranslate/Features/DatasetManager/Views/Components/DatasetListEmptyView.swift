import SwiftUI

/// Empty state view for the dataset list when no datasets exist
struct DatasetListEmptyView: View {
    let onGetStarted: () -> Void

    var body: some View {
        ContentUnavailableView {
            SwiftUI.Label("No Datasets", systemImage: "square.stack.3d.up.slash")
        } description: {
            Text("Get started by adding datasets for sign language recognition training.")
        } actions: {
            Button(action: onGetStarted) {
                SwiftUI.Label("Get Started", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

/// Empty state view for a specific section
struct DatasetSectionEmptyView: View {
    let section: SectionType
    let compact: Bool

    enum SectionType {
        case available
        case downloading
        case ready
        case failed

        var message: String {
            switch self {
            case .available:
                return "All datasets have been downloaded or are in progress"
            case .downloading:
                return "No downloads in progress"
            case .ready:
                return "No datasets ready yet. Start downloading to get started."
            case .failed:
                return "No failed downloads"
            }
        }

        var icon: String {
            switch self {
            case .available:
                return "checkmark.circle"
            case .downloading:
                return "arrow.down.circle"
            case .ready:
                return "square.stack.3d.up"
            case .failed:
                return "checkmark.seal"
            }
        }
    }

    init(section: SectionType, compact: Bool = true) {
        self.section = section
        self.compact = compact
    }

    var body: some View {
        if compact {
            HStack(spacing: 8) {
                Image(systemName: section.icon)
                    .foregroundStyle(.tertiary)
                Text(section.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
        } else {
            VStack(spacing: 12) {
                Image(systemName: section.icon)
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                Text(section.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }
}

/// Illustration view for empty states
struct DatasetEmptyIllustration: View {
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                // Background circles
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 120, height: 120)

                Circle()
                    .fill(Color.purple.opacity(0.1))
                    .frame(width: 80, height: 80)
                    .offset(x: 30, y: -20)

                // Main icon
                Image(systemName: "hand.raised.fingers.spread.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                // Decorative elements
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .offset(x: -40, y: 30)

                Image(systemName: "folder.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
                    .offset(x: 45, y: 35)
            }
            .frame(width: 150, height: 150)
        }
    }
}

/// Full empty state view with illustration
struct DatasetListFullEmptyView: View {
    let onGetStarted: () -> Void
    let onLearnMore: (() -> Void)?

    init(onGetStarted: @escaping () -> Void, onLearnMore: (() -> Void)? = nil) {
        self.onGetStarted = onGetStarted
        self.onLearnMore = onLearnMore
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            DatasetEmptyIllustration()

            VStack(spacing: 8) {
                Text("Welcome to Dataset Manager")
                    .font(.title2.weight(.semibold))

                Text("Download sign language datasets to train and improve recognition models. Start with our curated collections.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            VStack(spacing: 12) {
                Button(action: onGetStarted) {
                    SwiftUI.Label("Initialize Default Datasets", systemImage: "arrow.down.circle.fill")
                        .frame(maxWidth: 280)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if let onLearnMore {
                    Button(action: onLearnMore) {
                        Text("Learn More")
                    }
                    .buttonStyle(.borderless)
                }
            }

            Spacer()

            // Dataset previews
            VStack(alignment: .leading, spacing: 12) {
                Text("Available Datasets")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    DatasetPreviewCard(
                        type: .include,
                        sampleCount: "15,000+",
                        size: "~50 GB"
                    )

                    DatasetPreviewCard(
                        type: .islcsltr,
                        sampleCount: "5,000+",
                        size: "~10 GB"
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

/// Preview card for a dataset type
private struct DatasetPreviewCard: View {
    let type: DatasetType
    let sampleCount: String
    let size: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: type.iconName)
                    .font(.title3)
                    .foregroundStyle(type.color)

                Text(type.displayName)
                    .font(.headline)
            }

            Text(type.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Divider()

            HStack {
                SwiftUI.Label(sampleCount, systemImage: "video.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(size)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(type.color.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Previews

#Preview("Empty List") {
    DatasetListEmptyView(onGetStarted: {})
}

#Preview("Full Empty State") {
    DatasetListFullEmptyView(
        onGetStarted: {},
        onLearnMore: {}
    )
}

#Preview("Section Empty States") {
    List {
        Section("Available") {
            DatasetSectionEmptyView(section: .available)
        }
        Section("Downloading") {
            DatasetSectionEmptyView(section: .downloading)
        }
        Section("Ready") {
            DatasetSectionEmptyView(section: .ready, compact: false)
        }
    }
    .listStyle(.insetGrouped)
}

#Preview("Illustration") {
    DatasetEmptyIllustration()
        .padding()
}
