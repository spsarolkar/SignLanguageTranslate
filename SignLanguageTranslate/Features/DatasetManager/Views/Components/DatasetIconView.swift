import SwiftUI

/// Displays an icon representing a dataset type.
///
/// The icon is rendered inside a circular background with the dataset type's color.
/// Supports multiple sizes for use in different contexts.
struct DatasetIconView: View {

    // MARK: - Properties

    let datasetType: DatasetType
    let size: IconSize

    // MARK: - Icon Size

    enum IconSize {
        case small
        case medium
        case large

        var dimension: CGFloat {
            switch self {
            case .small: return 32
            case .medium: return 44
            case .large: return 56
            }
        }

        var iconFont: Font {
            switch self {
            case .small: return .body
            case .medium: return .title2
            case .large: return .title
            }
        }

        var cornerRadius: CGFloat {
            switch self {
            case .small: return 6
            case .medium: return 10
            case .large: return 12
            }
        }
    }

    // MARK: - Initialization

    init(type: DatasetType, size: IconSize = .medium) {
        self.datasetType = type
        self.size = size
    }

    // MARK: - Body

    var body: some View {
        Image(systemName: datasetType.iconName)
            .font(size.iconFont)
            .foregroundStyle(datasetType.color)
            .frame(width: size.dimension, height: size.dimension)
            .background(
                RoundedRectangle(cornerRadius: size.cornerRadius)
                    .fill(datasetType.color.opacity(0.15))
            )
            .accessibilityLabel("\(datasetType.displayName) dataset icon")
    }
}

// MARK: - Previews

#Preview("INCLUDE - All Sizes") {
    HStack(spacing: 20) {
        DatasetIconView(type: .include, size: .small)
        DatasetIconView(type: .include, size: .medium)
        DatasetIconView(type: .include, size: .large)
    }
    .padding()
}

#Preview("ISL-CSLTR - All Sizes") {
    HStack(spacing: 20) {
        DatasetIconView(type: .islcsltr, size: .small)
        DatasetIconView(type: .islcsltr, size: .medium)
        DatasetIconView(type: .islcsltr, size: .large)
    }
    .padding()
}

#Preview("Both Types - Medium") {
    VStack(spacing: 20) {
        DatasetIconView(type: .include, size: .medium)
        DatasetIconView(type: .islcsltr, size: .medium)
    }
    .padding()
}
