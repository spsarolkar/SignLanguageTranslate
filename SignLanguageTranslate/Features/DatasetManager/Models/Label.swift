import Foundation
import SwiftData
import NaturalLanguage

/// Represents a label/tag that can be associated with video samples.
/// Labels categorize videos by category, word, or sentence.
///
/// Example usage:
/// - Category label: "Animals" (groups related words)
/// - Word label: "Dog" (specific sign being demonstrated)
/// - Sentence label: "Hello, how are you?" (for sentence-level datasets)
@Model
public final class Label {

    // MARK: - Properties

    /// Unique identifier
    public var id: UUID

    /// The label text (e.g., "Animals", "Dog", "Hello")
    public var name: String

    /// The type of label (category, word, or sentence)
    public var typeRawValue: String

    /// Timestamp when this label was created
    public var createdAt: Date

    /// Semantic embedding vector (e.g., from NLEmbedding or BERT)
    /// Stored as a flat array of Floats
    public var embedding: [Float]?

    // MARK: - Relationships

    /// Videos that have this label assigned
    /// Note: Inverse relationship will be set up in VideoSample model
    public var videoSamples: [VideoSample]?

    // MARK: - Computed Properties

    /// The label type as enum (computed from stored raw value)
    public var type: LabelType {
        get { LabelType(rawValue: typeRawValue) ?? .word }
        set { typeRawValue = newValue.rawValue }
    }

    /// Formatted display name showing type and name
    /// Example: "Category: Animals" or "Word: Dog"
    public var displayName: String {
        "\(type.displayName): \(name)"
    }

    /// Short display for compact UI (just the name)
    public var shortDisplayName: String {
        name
    }

    // MARK: - Initialization

    /// Create a new label
    /// - Parameters:
    ///   - name: The label text
    ///   - type: The type of label (category, word, sentence)
    public init(name: String, type: LabelType) {
        self.id = UUID()
        self.name = name
        self.typeRawValue = type.rawValue
        self.createdAt = Date.now
    }

    /// Create a label with a specific ID (for testing or migration)
    public init(id: UUID = UUID(), name: String, type: LabelType, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.typeRawValue = type.rawValue
        self.createdAt = createdAt
    }
    
    // MARK: - Embedding Generation
    
    /// Generates and stores a semantic embedding for this label using Apple's NaturalLanguage framework.
    /// This allows for semantic search and zero-shot learning capabilities.
    /// - Returns: The generated embedding if successful
    @discardableResult
    public func generateEmbedding() -> [Float]? {
        // Use English word embeddings
        guard let embeddingModel = NLEmbedding.wordEmbedding(for: .english) else {
            print("[Label] Failed to load NLEmbedding for English")
            return nil
        }
        
        // Try to get vector for the exact name
        if let vector = embeddingModel.vector(for: self.name) {
            self.embedding = vector.map { Float($0) }
            return self.embedding
        }
        
        // Fallback: If it's a phrase (e.g. "Thank You"), try average of words or neighbors
        // For simplicity, we'll try case-insensitive
        if let vector = embeddingModel.vector(for: self.name.lowercased()) {
            self.embedding = vector.map { Float($0) }
            return self.embedding
        }
        
        print("[Label] No embedding found for '\(self.name)'")
        return nil
    }
}

// MARK: - Preview Helpers

extension Label {

    /// Sample category labels for previews
    static var previewCategories: [Label] {
        [
            Label(name: "Animals", type: .category),
            Label(name: "Adjectives", type: .category),
            Label(name: "Greetings", type: .category),
            Label(name: "Colors", type: .category)
        ]
    }

    /// Sample word labels for previews
    static var previewWords: [Label] {
        [
            Label(name: "Dog", type: .word),
            Label(name: "Cat", type: .word),
            Label(name: "Bird", type: .word),
            Label(name: "Hello", type: .word),
            Label(name: "Thank You", type: .word)
        ]
    }

    /// Sample sentence labels for previews
    static var previewSentences: [Label] {
        [
            Label(name: "How are you?", type: .sentence),
            Label(name: "Nice to meet you", type: .sentence),
            Label(name: "What is your name?", type: .sentence)
        ]
    }

    /// Single sample label for simple previews
    static var preview: Label {
        Label(name: "Dog", type: .word)
    }
}
