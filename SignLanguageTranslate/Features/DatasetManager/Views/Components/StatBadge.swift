import SwiftUI

/// A reusable badge component for displaying statistics
///
/// Shows a value with a label in a compact, styled format.
///
/// ## Usage
/// ```swift
/// StatBadge(title: "Videos", value: "1,234")
/// StatBadge(title: "Size", value: "2.5 GB", color: .blue)
/// ```
struct StatBadge: View {
    let title: String
    let value: String
    var color: Color = .primary
    var backgroundColor: Color? = nil
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor ?? Color.secondary.opacity(0.1))
        )
    }
}

// MARK: - Previews

#Preview("Basic") {
    HStack {
        StatBadge(title: "Files", value: "1,234")
        StatBadge(title: "Size", value: "2.5 GB")
    }
    .padding()
}

#Preview("With Colors") {
    HStack {
        StatBadge(title: "Downloaded", value: "45", color: .green)
        StatBadge(title: "Failed", value: "2", color: .red)
        StatBadge(title: "Pending", value: "8", color: .orange)
    }
    .padding()
}

#Preview("Custom Background") {
    HStack {
        StatBadge(
            title: "Active",
            value: "12",
            color: .white,
            backgroundColor: .blue
        )
        StatBadge(
            title: "Complete",
            value: "88",
            color: .white,
            backgroundColor: .green
        )
    }
    .padding()
}
