//
//  PipelineView.swift
//  SignLanguageTranslate
//
//  Created by Sunil Sarolkar
//

import SwiftUI

struct PipelineView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Data Pipeline")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .padding(.horizontal)
                    
                    Text("Process videos, extract keypoints, and prepare data for training.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("Data Pipeline")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

#Preview {
    PipelineView()
}

