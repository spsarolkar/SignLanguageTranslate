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
    
    /// Service for batch feature extraction (persisted across navigation)
    @StateObject private var batchExtractionService = BatchExtractionService()
    
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Register background training task
        TrainingBackgroundManager.shared.register()
    }

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
        .environmentObject(batchExtractionService)
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .background:
                batchExtractionService.pause()
                // Schedule training resume
                TrainingBackgroundManager.shared.schedule()
                // Notify training to save state
                NotificationCenter.default.post(name: .trainingShouldSaveAndStop, object: nil)
            case .inactive:
                batchExtractionService.pause()
            case .active:
                batchExtractionService.resume()
                // Resume training if it was running?
                // For now, let user manually resume or wait for BG task to verify flow.
                // Or post .trainingResumeInBackground? (User requested manual lock -> BG pickup)
            @unknown default: break
            }
        }
    }
}
