import Foundation

/// Represents the type/level of a label in the sign language dataset
enum LabelType: String, Codable, CaseIterable, Identifiable {
    /// Category-level label (e.g., "Animals", "Adjectives", "Greetings")
    case category

    /// Word-level label (e.g., "Dog", "Cat", "Hello")
    case word

    /// Sentence-level label (e.g., "How are you?", "Nice to meet you")
    case sentence

    var id: String { rawValue }

    /// Display name for UI
    var displayName: String {
        switch self {
        case .category: return "Category"
        case .word: return "Word"
        case .sentence: return "Sentence"
        }
    }

    /// SF Symbol icon for this label type
    var iconName: String {
        switch self {
        case .category: return "folder.fill"
        case .word: return "textformat.abc"
        case .sentence: return "text.quote"
        }
    }

    /// Color associated with this label type (for UI badges)
    /// Returns a string that can be used with Color(labelType.colorName)
    var colorName: String {
        switch self {
        case .category: return "blue"
        case .word: return "green"
        case .sentence: return "purple"
        }
    }
}
