import SwiftUI
import SwiftData

@main
struct SignLanguageTranslateApp: App {

    /// Persistence controller managing SwiftData
    private let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    // Seed initial datasets if this is first launch
                    persistenceController.seedInitialDatasetsIfNeeded()
                }
        }
        .modelContainer(persistenceController.container)
    }
}
