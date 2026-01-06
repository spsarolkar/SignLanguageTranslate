import Foundation
import SwiftData

/// Represents a label/tag that can be associated with video samples.
/// Labels categorize videos by category, word, or sentence.
///
/// Example usage:
/// - Category label: "Animals" (groups related words)
/// - Word label: "Dog" (specific sign being demonstrated)
/// - Sentence label: "Hello, how are you?" (for sentence-level datasets)
@Model
final class Label {

    // MARK: - Properties

    /// Unique identifier
    var id: UUID

    /// The label text (e.g., "Animals", "Dog", "Hello")
    var name: String

    /// The type of label (category, word, or sentence)
    var typeRawValue: String

    /// Timestamp when this label was created
    var createdAt: Date

    // MARK: - Relationships

    /// Videos that have this label assigned
    /// Note: Inverse relationship will be set up in VideoSample model
    var videoSamples: [VideoSample]?

    // MARK: - Computed Properties

    /// The label type as enum (computed from stored raw value)
    var type: LabelType {
        get { LabelType(rawValue: typeRawValue) ?? .word }
        set { typeRawValue = newValue.rawValue }
    }

    /// Formatted display name showing type and name
    /// Example: "Category: Animals" or "Word: Dog"
    var displayName: String {
        "\(type.displayName): \(name)"
    }

    /// Short display for compact UI (just the name)
    var shortDisplayName: String {
        name
    }

    // MARK: - Initialization

    /// Create a new label
    /// - Parameters:
    ///   - name: The label text
    ///   - type: The type of label (category, word, sentence)
    init(name: String, type: LabelType) {
        self.id = UUID()
        self.name = name
        self.typeRawValue = type.rawValue
        self.createdAt = Date.now
    }

    /// Create a label with a specific ID (for testing or migration)
    init(id: UUID = UUID(), name: String, type: LabelType, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.typeRawValue = type.rawValue
        self.createdAt = createdAt
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
