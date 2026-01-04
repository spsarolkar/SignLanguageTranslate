//
//  DatasetManagerView.swift
//  SignLanguageTranslate
//
//  Created by Sunil Sarolkar
//

import SwiftUI

struct DatasetManagerView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Dataset Manager")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .padding(.horizontal)
                    
                    Text("Manage your datasets, import videos, and organize training data.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("Dataset Manager")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

#Preview {
    DatasetManagerView()
}

