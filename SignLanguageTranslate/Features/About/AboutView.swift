//
//  AboutView.swift
//  SignLanguageTranslate
//
//  Created by Sunil Sarolkar
//

import SwiftUI

struct AboutView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // App Information
                    VStack(alignment: .leading, spacing: 16) {
                        Text("About")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            InfoRow(
                                label: "Version",
                                value: "1.0.0"
                            )
                            InfoRow(
                                label: "Developer",
                                value: "Sunil Sarolkar"
                            )
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    // Description
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sign Language Translate")
                            .font(.headline)
                        
                        Text("A native iOS application for training Sign Language Translation models directly on iPad Pro using Apple MLX framework.")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.body)
            Spacer()
            Text(value)
                .font(.body)
                .fontWeight(.medium)
        }
    }
}

#Preview {
    AboutView()
}

