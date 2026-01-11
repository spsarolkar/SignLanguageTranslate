import SwiftUI
import SwiftData

/// Content column that displays different views based on the selected navigation section.
struct ContentColumnView: View {
    let selectedSection: NavigationSection?
    @Binding var selectedDataset: Dataset?

    var body: some View {
        Group {
            switch selectedSection {
            case .datasets:
                DatasetListView(selectedDataset: $selectedDataset)
            case .downloads:
                DownloadListView()
            case .training:
                TrainingPlaceholderView()
            case .settings:
                SettingsPlaceholderView()
            case nil:
                ContentUnavailableView(
                    "No Section Selected",
                    systemImage: "sidebar.left",
                    description: Text("Select a section from the sidebar")
                )
            }
        }
    }
}

// MARK: - Placeholder Views

/// Placeholder view for the Training section.
struct TrainingPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "Training",
            systemImage: "brain.head.profile",
            description: Text("Train sign language recognition models using your datasets. Coming soon.")
        )
        .navigationTitle("Training")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// Placeholder view for the Settings section.
struct SettingsPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "Settings",
            systemImage: "gearshape.fill",
            description: Text("Configure app preferences and manage storage. Coming soon.")
        )
        .navigationTitle("Settings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Previews

#Preview("Content - Datasets") {
    NavigationStack {
        ContentColumnView(
            selectedSection: .datasets,
            selectedDataset: .constant(nil)
        )
    }
    .modelContainer(PersistenceController.preview.container)
    .environment(DownloadManager())
}

#Preview("Content - Downloads Empty") {
    NavigationStack {
        ContentColumnView(
            selectedSection: .downloads,
            selectedDataset: .constant(nil)
        )
    }
    .modelContainer(PersistenceController.preview.container)
    .environment(DownloadManager())
}

#Preview("Content - Training") {
    NavigationStack {
        ContentColumnView(
            selectedSection: .training,
            selectedDataset: .constant(nil)
        )
    }
    .modelContainer(PersistenceController.preview.container)
    .environment(DownloadManager())
}

#Preview("Content - Settings") {
    NavigationStack {
        ContentColumnView(
            selectedSection: .settings,
            selectedDataset: .constant(nil)
        )
    }
    .modelContainer(PersistenceController.preview.container)
    .environment(DownloadManager())
}
