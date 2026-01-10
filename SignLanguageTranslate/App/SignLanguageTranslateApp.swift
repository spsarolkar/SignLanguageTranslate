import SwiftUI
import SwiftData

@main
struct SignLanguageTranslateApp: App {

    /// Persistence controller managing SwiftData
    private let persistenceController = PersistenceController.shared

    /// Download manager for handling dataset downloads
    @State private var downloadManager = DownloadManager()

    var body: some Scene {
        WindowGroup {
            MainNavigationView()
                .onAppear {
                    // Seed initial datasets if this is first launch
                    persistenceController.seedInitialDatasetsIfNeeded()
                }
        }
        .modelContainer(persistenceController.container)
        .environment(downloadManager)
    }
}
