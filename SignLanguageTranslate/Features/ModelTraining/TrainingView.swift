//
//  TrainingView.swift
//  SignLanguageTranslate
//
//  Created by Sunil Sarolkar
//

import SwiftUI

struct TrainingView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Model Training")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .padding(.horizontal)
                    
                    Text("Train Transformer-based models using Apple MLX framework.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("Model Training")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

#Preview {
    TrainingView()
}

