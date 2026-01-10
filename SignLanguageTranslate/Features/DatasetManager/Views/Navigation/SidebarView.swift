import SwiftUI

/// Sidebar view displaying navigation sections with icons and badges.
struct SidebarView: View {
    @Binding var selectedSection: NavigationSection?
    let activeDownloadCount: Int

    var body: some View {
        List(selection: $selectedSection) {
            Section {
                ForEach(NavigationSection.allCases) { section in
                    sectionRow(for: section)
                        .tag(section)
                }
            } header: {
                Text("Navigation")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Sign Language")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
    }

    // MARK: - Section Row

    @ViewBuilder
    private func sectionRow(for section: NavigationSection) -> some View {
        SwiftUI.Label {
            HStack {
                Text(section.rawValue)

                Spacer()

                if section == .downloads && activeDownloadCount > 0 {
                    downloadBadge
                }
            }
        } icon: {
            Image(systemName: section.icon)
                .foregroundStyle(iconColor(for: section))
        }
        .accessibilityLabel(accessibilityLabelText(for: section))
    }

    // MARK: - Download Badge

    private var downloadBadge: some View {
        Text("\(activeDownloadCount)")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(.blue)
            )
            .accessibilityLabel("\(activeDownloadCount) active downloads")
    }

    // MARK: - Helpers

    private func iconColor(for section: NavigationSection) -> Color {
        switch section {
        case .datasets:
            return .blue
        case .downloads:
            return activeDownloadCount > 0 ? .blue : .secondary
        case .training:
            return .purple
        case .settings:
            return .gray
        }
    }

    private func accessibilityLabelText(for section: NavigationSection) -> String {
        var label = section.rawValue
        if section == .downloads && activeDownloadCount > 0 {
            label += ", \(activeDownloadCount) active"
        }
        return label
    }
}

// MARK: - Previews

#Preview("Sidebar - No Downloads") {
    NavigationStack {
        SidebarView(
            selectedSection: .constant(.datasets),
            activeDownloadCount: 0
        )
    }
}

#Preview("Sidebar - With Downloads") {
    NavigationStack {
        SidebarView(
            selectedSection: .constant(.downloads),
            activeDownloadCount: 3
        )
    }
}

#Preview("Sidebar - Many Downloads") {
    NavigationStack {
        SidebarView(
            selectedSection: .constant(.downloads),
            activeDownloadCount: 25
        )
    }
}
