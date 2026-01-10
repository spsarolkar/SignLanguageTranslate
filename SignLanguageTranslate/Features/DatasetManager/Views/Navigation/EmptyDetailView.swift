import SwiftUI

/// Placeholder view displayed when no item is selected in the detail column.
/// Provides instructional text and optional quick action buttons.
struct EmptyDetailView: View {
    let title: String
    let systemImage: String
    let description: String
    var quickActions: [QuickAction]

    init(
        title: String = "Select an Item",
        systemImage: String = "hand.raised.fingers.spread.fill",
        description: String = "Choose an item from the list to view its details.",
        quickActions: [QuickAction] = []
    ) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
        self.quickActions = quickActions
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon
            Image(systemName: systemImage)
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)

            // Text Content
            VStack(spacing: 8) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }

            // Quick Actions
            if !quickActions.isEmpty {
                VStack(spacing: 12) {
                    ForEach(quickActions) { action in
                        QuickActionButton(action: action)
                    }
                }
                .padding(.top, 8)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Quick Action

/// Represents a quick action button in the empty detail view.
struct QuickAction: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let style: ActionStyle
    let action: () -> Void

    enum ActionStyle {
        case primary
        case secondary

        var foregroundColor: Color {
            switch self {
            case .primary: return .white
            case .secondary: return .accentColor
            }
        }

        var backgroundColor: Color {
            switch self {
            case .primary: return .accentColor
            case .secondary: return .accentColor.opacity(0.15)
            }
        }
    }
}

// MARK: - Quick Action Button

/// Button component for quick actions.
struct QuickActionButton: View {
    let action: QuickAction

    var body: some View {
        Button(action: action.action) {
            SwiftUI.Label(action.title, systemImage: action.systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(action.style.foregroundColor)
                .frame(minWidth: 200)
                .padding(.vertical, 12)
                .padding(.horizontal, 20)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(action.style.backgroundColor)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Convenience Initializers

extension EmptyDetailView {
    /// Creates an empty view for the datasets section.
    static var datasets: EmptyDetailView {
        EmptyDetailView(
            title: "Select a Dataset",
            systemImage: "folder.fill",
            description: "Choose a dataset from the list to view its contents and manage downloads."
        )
    }

    /// Creates an empty view for the downloads section.
    static var downloads: EmptyDetailView {
        EmptyDetailView(
            title: "No Active Downloads",
            systemImage: "arrow.down.circle",
            description: "Start downloading a dataset to track progress here."
        )
    }

    /// Creates an empty view for the training section.
    static var training: EmptyDetailView {
        EmptyDetailView(
            title: "Training Models",
            systemImage: "brain.head.profile",
            description: "Configure and train sign language recognition models using your datasets."
        )
    }

    /// Creates an empty view for the settings section.
    static var settings: EmptyDetailView {
        EmptyDetailView(
            title: "Settings",
            systemImage: "gearshape.fill",
            description: "Configure app preferences, manage storage, and customize your experience."
        )
    }
}

// MARK: - Previews

#Preview("Empty Detail - Default") {
    EmptyDetailView()
}

#Preview("Empty Detail - Datasets") {
    EmptyDetailView.datasets
}

#Preview("Empty Detail - Downloads") {
    EmptyDetailView.downloads
}

#Preview("Empty Detail - With Quick Actions") {
    EmptyDetailView(
        title: "Get Started",
        systemImage: "hand.raised.fingers.spread.fill",
        description: "Download the INCLUDE dataset to start exploring sign language videos.",
        quickActions: [
            QuickAction(
                title: "Download INCLUDE",
                systemImage: "arrow.down.circle.fill",
                style: .primary,
                action: { print("Download INCLUDE") }
            ),
            QuickAction(
                title: "Learn More",
                systemImage: "info.circle",
                style: .secondary,
                action: { print("Learn More") }
            )
        ]
    )
}

#Preview("Empty Detail - Dark Mode") {
    EmptyDetailView(
        title: "Select a Dataset",
        systemImage: "folder.fill",
        description: "Choose a dataset from the list to view its contents."
    )
    .preferredColorScheme(.dark)
}
