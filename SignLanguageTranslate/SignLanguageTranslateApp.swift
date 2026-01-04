//
//  SignLanguageTranslateApp.swift
//  SignLanguageTranslate
//
//  Created by Sunil Sarolkar
//

import SwiftUI
import SwiftData

@main
struct SignLanguageTranslateApp: App {
    let modelContainer: ModelContainer
    
    init() {
        // Configure SwiftData model container
        let schema = Schema([Dataset.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        
        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            modelContainer = container
            
            // Set up DatasetManager with model context
            Task { @MainActor in
                let context = container.mainContext
                DatasetManager.shared.modelContext = context
                
                // Recreate background session in case app was terminated and relaunched
                DatasetManager.shared.recreateBackgroundSession()
            }
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(modelContainer)
        }
    }
}
