//
//  ContentView.swift
//  SignLanguageTranslate
//
//  Created by Sunil Sarolkar
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "house")
                }
            
            DatasetManagerView()
                .tabItem {
                    Label("Dataset Manager", systemImage: "folder")
                }
            
            PipelineView()
                .tabItem {
                    Label("Data Pipeline", systemImage: "gearshape")
                }
            
            TrainingView()
                .tabItem {
                    Label("Model Training", systemImage: "chart.line.uptrend.xyaxis")
                }
            
            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .onAppear {
            // Initialize core managers
            _ = PersistenceController.shared
            _ = BackgroundManager.shared
        }
    }
}

#Preview {
    ContentView()
}
