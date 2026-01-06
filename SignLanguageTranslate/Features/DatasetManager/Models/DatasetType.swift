import Foundation
import SwiftUI

/// Represents the type/source of a sign language dataset
enum DatasetType: String, Codable, CaseIterable, Identifiable {

    /// INCLUDE dataset - Word-level signs organized by category
    /// Source: Zenodo (multiple zip files per category)
    case include

    /// ISL-CSLTR dataset - Sentence-level continuous sign language
    /// Source: Single zip with CSV metadata
    case islcsltr

    var id: String { rawValue }

    /// Human-readable display name
    var displayName: String {
        switch self {
        case .include: return "INCLUDE"
        case .islcsltr: return "ISL-CSLTR"
        }
    }

    /// Full descriptive name
    var fullName: String {
        switch self {
        case .include: return "INCLUDE: Indian Sign Language Dataset"
        case .islcsltr: return "ISL-CSLTR: Continuous Sign Language Translation"
        }
    }

    /// Brief description of the dataset
    var description: String {
        switch self {
        case .include:
            return "Word-level Indian Sign Language dataset with 15+ categories including Animals, Greetings, Colors, and more."
        case .islcsltr:
            return "Sentence-level continuous sign language dataset for translation tasks."
        }
    }

    /// SF Symbol icon for this dataset type
    var iconName: String {
        switch self {
        case .include: return "hand.raised.fingers.spread.fill"
        case .islcsltr: return "text.bubble.fill"
        }
    }

    /// Color associated with this dataset
    var color: Color {
        switch self {
        case .include: return .blue
        case .islcsltr: return .purple
        }
    }

    /// Whether this dataset uses categories (word-level) or sentences
    var usesCategories: Bool {
        switch self {
        case .include: return true
        case .islcsltr: return false
        }
    }

    /// Label type used for the primary content
    var primaryLabelType: LabelType {
        switch self {
        case .include: return .word
        case .islcsltr: return .sentence
        }
    }

    /// Estimated total size of the dataset (for display purposes)
    var estimatedSizeDescription: String {
        switch self {
        case .include: return "~50 GB"
        case .islcsltr: return "~10 GB"
        }
    }
}
