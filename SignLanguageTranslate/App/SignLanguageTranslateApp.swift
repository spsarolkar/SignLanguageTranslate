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

                    // Clean up stale training runs that were "Running" when app terminated
                    await cleanupStaleTrainingRuns()
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
                // Schedule background training task
                TrainingBackgroundManager.shared.schedule()
                // Save training checkpoint (training continues if possible)
                NotificationCenter.default.post(name: .trainingShouldSaveAndStop, object: nil)
            case .inactive:
                batchExtractionService.pause()
            case .active:
                batchExtractionService.resume()
                // Resume training if it was paused
                NotificationCenter.default.post(name: .trainingResumeInBackground, object: nil)
            @unknown default: break
            }
        }
    }

    /// Mark any orphaned "Running" training runs as interrupted on app launch
    @MainActor
    private func cleanupStaleTrainingRuns() async {
        let context = persistenceController.container.mainContext

        // Check if the singleton manager has an active run
        let activeRunId = TrainingSessionManager.shared.currentRunId

        do {
            // Find all runs with "Running" or "Resumed" status
            let staleStatuses = ["Running", "Resumed", "Started"]
            let descriptor = FetchDescriptor<TrainingRun>(
                predicate: #Predicate<TrainingRun> { run in
                    staleStatuses.contains(run.status)
                }
            )

            let staleRuns = try context.fetch(descriptor)

            for run in staleRuns {
                // Don't mark the currently active run as interrupted
                if run.id == activeRunId {
                    continue
                }

                run.status = "Interrupted"
                print("[App] Marked stale run '\(run.name)' as Interrupted")
            }

            if !staleRuns.isEmpty {
                try context.save()
            }
        } catch {
            print("[App] Failed to cleanup stale training runs: \(error)")
        }
    }
}
