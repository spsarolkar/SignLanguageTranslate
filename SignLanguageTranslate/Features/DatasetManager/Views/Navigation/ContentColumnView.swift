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
            case .pipeline:
                DataPipelineView()
            case .training:
                TrainingContentView()
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
        .id(selectedSection)
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

/// Settings view with developer tools
struct SettingsPlaceholderView: View {
    @State private var showDatabaseInspector = false
    var body: some View {
        List {
            Section("Developer Tools") {
                Button(action: { showDatabaseInspector = true }) {
                    SwiftUI.Label("Database Inspector", systemImage: "cylinder.split.1x2")
                }
            }
            
            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showDatabaseInspector) {
            NavigationStack {
                DatabaseInspectorView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                showDatabaseInspector = false
                            }
                        }
                    }
            }
        }
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
