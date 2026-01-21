import SwiftUI
import SwiftData

/// Main navigation container using NavigationSplitView for iPad.
/// Provides a three-column layout: Sidebar, Content, and Detail.
struct MainNavigationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(DownloadManager.self) private var downloadManager

    @State private var selectedSection: NavigationSection? = .datasets
    @State private var selectedDataset: Dataset?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showingDownloadsSheet = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                selectedSection: $selectedSection,
                activeDownloadCount: downloadManager.activeCount
            )
        } content: {
            ContentColumnView(
                selectedSection: selectedSection,
                selectedDataset: $selectedDataset
            )
        } detail: {
            DetailColumnView(
                selectedSection: selectedSection,
                selectedDataset: selectedDataset
            )
        }
        .navigationSplitViewStyle(.balanced)
        .overlay(alignment: .bottom) {
            DownloadNotificationBanner(isPresented: $showingDownloadsSheet)
                .animation(.easeInOut, value: downloadManager.isDownloading)
        }
        .sheet(isPresented: $showingDownloadsSheet) {
            NavigationStack {
                DownloadListView()
                    .navigationTitle("Downloads")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                showingDownloadsSheet = false
                            }
                        }
                    }
            }
        }
    }
}

// MARK: - Navigation Section

/// Represents the main navigation sections in the sidebar.
enum NavigationSection: String, CaseIterable, Identifiable {
    case datasets = "Datasets"
    case downloads = "Downloads"
    case pipeline = "Pipeline"
    case training = "Training"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .datasets:
            return "folder.fill"
        case .downloads:
            return "arrow.down.circle.fill"
        case .pipeline:
            return "bolt.horizontal.fill"
        case .training:
            return "brain.head.profile"
        case .settings:
            return "gearshape.fill"
        }
    }

    var description: String {
        switch self {
        case .datasets:
            return "Manage downloaded datasets"
        case .downloads:
            return "View and manage downloads"
        case .pipeline:
            return "Extract features and sync to HuggingFace"
        case .training:
            return "Train sign language models"
        case .settings:
            return "App preferences and settings"
        }
    }
}

// MARK: - Previews

#Preview("Main Navigation") {
    MainNavigationView()
        .modelContainer(PersistenceController.preview.container)
        .environment(DownloadManager())
}

#Preview("Main Navigation - With Downloads") {
    let manager = DownloadManager()
    return MainNavigationView()
        .modelContainer(PersistenceController.preview.container)
        .environment(manager)
}
