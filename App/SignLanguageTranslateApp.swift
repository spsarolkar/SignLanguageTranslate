//  SignLanguageTranslateApp.swift
import SwiftUI
import SwiftData

@main
struct SignLanguageTranslateApp: App {
    private let persistenceController = PersistenceController.shared
    @State private var downloadManager = DownloadManager()

    var body: some Scene {
        WindowGroup {
            MainNavigationView()
                .environment(downloadManager)
                .onAppear {
                    persistenceController.seedInitialDatasetsIfNeeded()
                }
        }
        .modelContainer(persistenceController.container)
    }
}