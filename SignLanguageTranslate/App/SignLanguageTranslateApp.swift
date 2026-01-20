import SwiftUI
import SwiftData

@main
struct SignLanguageTranslateApp: App {

    /// App delegate adaptor for handling background URL session events
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    /// Persistence controller managing SwiftData
    private let persistenceController = PersistenceController.shared

    /// Download manager for handling dataset downloads
    @State private var downloadManager = DownloadManager()

    /// Extraction progress tracker for zip extraction UI
    @State private var extractionTracker = ExtractionProgressTracker()

    var body: some Scene {
        WindowGroup {
            MainNavigationView()
                .onAppear {
                    // Seed initial datasets if this is first launch
                    persistenceController.seedInitialDatasetsIfNeeded()
                }
                .task {
                    // Recover any in-progress downloads from previous session
                    await downloadManager.recoverDownloads()
                }
        }
        .modelContainer(persistenceController.container)
        .environment(downloadManager)
        .environment(extractionTracker)
    }
}
