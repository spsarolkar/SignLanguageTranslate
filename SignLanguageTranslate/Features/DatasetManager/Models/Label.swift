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

    /// Standard embedding dimension for the model (must match SignLanguageModel outputDim)
    public static let embeddingDimension = 384

    /// Generates and stores a semantic embedding for this label using Apple's NaturalLanguage framework.
    /// The embedding is normalized to 384 dimensions (padded/truncated and L2-normalized) for consistency.
    /// - Returns: The generated embedding if successful
    @discardableResult
    public func generateEmbedding() -> [Float]? {
        // Use English word embeddings
        guard let embeddingModel = NLEmbedding.wordEmbedding(for: .english) else {
            print("[Label] Failed to load NLEmbedding for English")
            return nil
        }

        var rawVector: [Float]?

        // Try to get vector for the exact name
        if let vector = embeddingModel.vector(for: self.name) {
            rawVector = vector.map { Float($0) }
        }
        // Fallback: try case-insensitive
        else if let vector = embeddingModel.vector(for: self.name.lowercased()) {
            rawVector = vector.map { Float($0) }
        }
        // Fallback: average of individual words for phrases
        else {
            let words = self.name.lowercased().split(separator: " ")
            var combined: [Double] = []
            var count = 0

            for word in words {
                if let vector = embeddingModel.vector(for: String(word)) {
                    if combined.isEmpty {
                        combined = vector
                    } else {
                        for (i, v) in vector.enumerated() where i < combined.count {
                            combined[i] += v
                        }
                    }
                    count += 1
                }
            }

            if count > 0 {
                rawVector = combined.map { Float($0 / Double(count)) }
            }
        }

        guard var vector = rawVector else {
            print("[Label] No embedding found for '\(self.name)'")
            return nil
        }

        // Normalize to standard dimension (384)
        vector = Self.normalizeEmbedding(vector, toDimension: Self.embeddingDimension)

        self.embedding = vector
        return self.embedding
    }

    /// Normalizes an embedding to a target dimension and L2-normalizes it
    private static func normalizeEmbedding(_ embedding: [Float], toDimension targetDim: Int) -> [Float] {
        var result: [Float]

        if embedding.count < targetDim {
            // Pad with zeros
            result = embedding + Array(repeating: 0.0, count: targetDim - embedding.count)
        } else if embedding.count > targetDim {
            // Truncate
            result = Array(embedding.prefix(targetDim))
        } else {
            result = embedding
        }

        // L2 normalize
        let norm = sqrt(result.reduce(0) { $0 + $1 * $1 })
        if norm > 0 {
            result = result.map { $0 / norm }
        }

        return result
    }

    /// Regenerates embedding if it's missing or has wrong dimension
    @discardableResult
    public func ensureValidEmbedding() -> [Float]? {
        if let existing = embedding, existing.count == Self.embeddingDimension {
            return existing
        }
        return generateEmbedding()
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
