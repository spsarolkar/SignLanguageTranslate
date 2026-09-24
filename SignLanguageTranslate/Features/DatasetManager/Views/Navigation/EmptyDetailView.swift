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
        VStack(spacing: Spacing.xxl) {
            Spacer()

            // Icon
            Image(systemName: systemImage)
                .font(Typo.largeTitle)
                .foregroundStyle(Palette.textTertiary)
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)

            // Text Content
            VStack(spacing: Spacing.sm) {
                Text(title)
                    .font(Typo.title2)
                    .foregroundStyle(Palette.textPrimary)

                Text(description)
                    .font(Typo.body)
                    .lineSpacing(Metrics.paragraphLineSpacing)
                    .foregroundStyle(Palette.textMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: Metrics.heroTextWidth)
            }

            // Quick Actions
            if !quickActions.isEmpty {
                VStack(spacing: Spacing.md) {
                    ForEach(quickActions) { action in
                        QuickActionButton(action: action)
                    }
                }
                .padding(.top, Spacing.sm)
            }

            Spacer()
        }
        .padding(Spacing.pane)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.ground)
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
    }
}

// MARK: - Quick Action Button

/// Button component for quick actions.
struct QuickActionButton: View {
    let action: QuickAction

    var body: some View {
        switch action.style {
        case .primary:
            PrimaryButton(title: action.title, systemImage: action.systemImage, action: action.action)
        case .secondary:
            SecondaryButton(title: action.title, systemImage: action.systemImage, action: action.action)
        }
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
