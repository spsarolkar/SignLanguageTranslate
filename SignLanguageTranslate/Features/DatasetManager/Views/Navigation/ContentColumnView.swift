import SwiftUI
import SwiftData

/// Content column that displays different views based on the selected navigation section.
struct ContentColumnView: View {
    @Bindable var navigation: NavigationState
    var onShowWorkspace: () -> Void = {}

    var body: some View {
        Group {
            switch navigation.selectedSection {
            case .datasets:
                DatasetListView(selectedDataset: $navigation.selectedDataset)
            case .downloads:
                DownloadListView()
            case .pipeline:
                PipelineSelectionView(navigation: navigation, onShowWorkspace: onShowWorkspace)
            case .training:
                TrainingContentView(selectedDataset: $navigation.trainingDataset)
                    .onChange(of: navigation.trainingDataset?.id) { _, id in
                        if id != nil { onShowWorkspace() }
                    }
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
        .background(Palette.ground)
        .onChange(of: navigation.selectedDataset?.id) { _, id in
            if navigation.selectedSection == .datasets, id != nil { onShowWorkspace() }
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

/// Settings view with developer tools
struct SettingsPlaceholderView: View {
    @State private var showDatabaseInspector = false
    @State private var showLocalFiles = false
    var body: some View {
        List {
            Section("On this iPad") {
                Button { showLocalFiles = true } label: {
                    SwiftUI.Label("Local files", systemImage: "folder")
                        .font(Typo.body)
                        .foregroundStyle(Palette.accent)
                        .frame(minHeight: Metrics.touchTarget)
                }
            }
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
        .fullScreenCover(isPresented: $showLocalFiles) { LocalFileBrowserView() }
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
        ContentColumnView(navigation: NavigationState(section: .datasets))
    }
    .modelContainer(PersistenceController.preview.container)
    .environment(DownloadManager())
}

#Preview("Content - Downloads Empty") {
    NavigationStack {
        ContentColumnView(navigation: NavigationState(section: .downloads))
    }
    .modelContainer(PersistenceController.preview.container)
    .environment(DownloadManager())
}

#Preview("Content - Training") {
    NavigationStack {
        ContentColumnView(navigation: NavigationState(section: .training))
    }
    .modelContainer(PersistenceController.preview.container)
    .environment(DownloadManager())
}

#Preview("Content - Settings") {
    NavigationStack {
        ContentColumnView(navigation: NavigationState(section: .settings))
    }
    .modelContainer(PersistenceController.preview.container)
    .environment(DownloadManager())
}
