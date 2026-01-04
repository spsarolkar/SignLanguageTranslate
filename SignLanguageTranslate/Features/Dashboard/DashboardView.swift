//
//  DashboardView.swift
//  SignLanguageTranslate
//
//  Created by Sunil Sarolkar
//

import SwiftUI

struct DashboardView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Title Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("On-Device LLM Training for Sign Language")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                    }
                    .padding(.horizontal)
                    
                    // Metrics Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Metrics")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        VStack(spacing: 12) {
                            MetricRow(
                                title: "Keypoint Models",
                                value: "Vision / MediaPipe"
                            )
                            MetricRow(
                                title: "Training Status",
                                value: "Not Started"
                            )
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    // Important Achievements Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Important Achievements")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Track your training milestones and key accomplishments here.")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

struct MetricRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.body)
            Spacer()
            Text(value)
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    DashboardView()
}

