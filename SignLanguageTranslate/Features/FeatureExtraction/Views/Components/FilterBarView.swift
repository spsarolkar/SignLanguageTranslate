import SwiftUI

struct FilterBarView: View {
    @Binding var selectedCategory: String?
    @Binding var selectedWord: String?
    @Binding var searchText: String
    
    let categories: [String]
    let words: [String] // Should be filtered by selected category in parent
    
    var body: some View {
        HStack {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search videos...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color(.tertiarySystemBackground))
            .cornerRadius(8)
            .frame(maxWidth: 200)
            
            Divider()
                .frame(height: 20)
            
            // Category Filter
            Menu {
                Button("All Categories") {
                    selectedCategory = nil
                    selectedWord = nil
                }
                
                ForEach(categories, id: \.self) { category in
                    Button(category) {
                        selectedCategory = category
                        selectedWord = nil // Reset word when category changes
                    }
                }
            } label: {
                HStack {
                    Text(selectedCategory ?? "All Categories")
                    if selectedCategory == nil {
                        Image(systemName: "folder")
                    }
                }
                .fixedSize()
            }
            .menuStyle(.borderlessButton)
            .frame(width: 140, alignment: .leading)
            
            // Word Filter
            Menu {
                Button("All Words") {
                    selectedWord = nil
                }
                
                ForEach(words, id: \.self) { word in
                    Button(word) {
                        selectedWord = word
                    }
                }
            } label: {
                HStack {
                    Text(selectedWord ?? "All Words")
                    if selectedWord == nil {
                        Image(systemName: "text.quote")
                    }
                }
                .fixedSize()
            }
            .disabled(selectedCategory == nil && words.isEmpty) // Disable if no category selected (unless we show all words)
            .menuStyle(.borderlessButton)
            .frame(width: 140, alignment: .leading)
            
            Spacer()
            
            // Status or Help
            if selectedCategory != nil {
                Button(action: {
                    selectedCategory = nil
                    selectedWord = nil
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }
}
