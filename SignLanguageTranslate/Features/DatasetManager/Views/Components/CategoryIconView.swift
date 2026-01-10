import SwiftUI

/// Displays an icon representing a download category.
///
/// The icon is rendered inside a circular background with a color
/// generated consistently from the category name.
/// Supports multiple sizes for use in different contexts.
struct CategoryIconView: View {

    // MARK: - Properties

    let category: String
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

    init(category: String, size: IconSize = .medium) {
        self.category = category
        self.size = size
    }

    // MARK: - Symbol Mapping

    private var symbolName: String {
        switch category {
        case "Animals":
            return "pawprint.fill"
        case "Adjectives":
            return "textformat"
        case "Clothes":
            return "tshirt.fill"
        case "Colours", "Colors":
            return "paintpalette.fill"
        case "Days_and_Time", "Days and Time":
            return "calendar"
        case "Electronics":
            return "desktopcomputer"
        case "Greetings":
            return "hand.wave.fill"
        case "Home":
            return "house.fill"
        case "Jobs":
            return "briefcase.fill"
        case "Means_of_Transportation", "Transportation":
            return "car.fill"
        case "People":
            return "person.2.fill"
        case "Places":
            return "mappin.and.ellipse"
        case "Pronouns":
            return "person.text.rectangle.fill"
        case "Seasons":
            return "leaf.fill"
        case "Society":
            return "building.2.fill"
        default:
            return "folder.fill"
        }
    }

    // MARK: - Background Color

    private var backgroundColor: Color {
        // Generate a consistent color based on the category name hash
        let hash = category.hashValue
        let hue = Double(abs(hash) % 360) / 360.0
        return Color(hue: hue, saturation: 0.6, brightness: 0.85)
    }

    // MARK: - Body

    var body: some View {
        Image(systemName: symbolName)
            .font(size.iconFont)
            .foregroundStyle(.white)
            .frame(width: size.dimension, height: size.dimension)
            .background(
                RoundedRectangle(cornerRadius: size.cornerRadius)
                    .fill(backgroundColor)
            )
            .accessibilityLabel("\(category) category icon")
    }
}

// MARK: - Previews

#Preview("All Categories - Medium") {
    ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 16) {
            ForEach(INCLUDEManifest.categoryNames, id: \.self) { category in
                VStack(spacing: 8) {
                    CategoryIconView(category: category, size: .medium)
                    Text(category)
                        .font(.caption2)
                        .lineLimit(1)
                }
            }
        }
        .padding()
    }
}

#Preview("Animals - All Sizes") {
    HStack(spacing: 20) {
        CategoryIconView(category: "Animals", size: .small)
        CategoryIconView(category: "Animals", size: .medium)
        CategoryIconView(category: "Animals", size: .large)
    }
    .padding()
}

#Preview("Unknown Category") {
    CategoryIconView(category: "Unknown", size: .medium)
        .padding()
}

#Preview("In Row Context") {
    List {
        ForEach(["Animals", "Greetings", "Seasons", "Jobs"], id: \.self) { category in
            HStack(spacing: 12) {
                CategoryIconView(category: category, size: .medium)
                Text(category)
                    .font(.headline)
                Spacer()
            }
            .padding(.vertical, 4)
        }
    }
}
