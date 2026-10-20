import SwiftUI

nonisolated enum LocalFileLocation: Hashable {
    case folder(String)
    case allFeatures

    var title: String {
        switch self {
        case .folder(let path): return path.isEmpty ? "Local files" : (path as NSString).lastPathComponent
        case .allFeatures: return "All features"
        }
    }

    var path: String {
        switch self {
        case .folder(let path): return path
        case .allFeatures: return "Datasets/Features"
        }
    }
}

/// Presented over the existing split view; closing leaves extraction and the
/// current dataset/category selection untouched.
struct LocalFileBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    let store: LocalFileStore

    init(root: URL? = nil) {
        store = LocalFileStore(root: root ?? FileManager.default.documentsDirectory)
    }

    var body: some View {
        NavigationStack {
            LocalDirectoryView(location: .folder(""), store: store, onClose: { dismiss() })
                .navigationDestination(for: LocalFileLocation.self) { location in
                    LocalDirectoryView(location: location, store: store, onClose: { dismiss() })
                }
                .navigationDestination(for: LocalFileEntry.self) { entry in
                    if entry.isDirectory {
                        LocalDirectoryView(location: .folder(entry.path), store: store, onClose: { dismiss() })
                    } else {
                        LocalFilePreviewView(path: entry.path, store: store, onClose: { dismiss() })
                    }
                }
        }
        .tint(Palette.accent)
        .preferredColorScheme(.dark)
    }
}

struct LocalDirectoryView: View {
    let location: LocalFileLocation
    let store: LocalFileStore
    var onClose: () -> Void = {}
    @State private var entries: [LocalFileEntry] = []
    @State private var search = ""
    @State private var isLoading = false
    @State private var error: String?

    private var filtered: [LocalFileEntry] {
        guard !search.isEmpty else { return entries }
        return entries.filter { $0.path.localizedStandardContains(search) }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(location == .allFeatures ? "Search every saved feature file" : "Explore on-device storage")
                        .font(Typo.title2)
                        .foregroundStyle(Palette.textPrimary)
                    Text(location.path.isEmpty ? "Documents" : "Documents/\(location.path)")
                        .font(Typo.monoCaption)
                        .foregroundStyle(Palette.textSecondary)
                        .textSelection(.enabled)
                    Text("Read-only snapshot. Refresh to see new pipeline output.")
                        .font(Typo.caption)
                        .foregroundStyle(Palette.textTertiary)
                }
                .padding(.vertical, Spacing.sm)
            }
            .listRowBackground(Palette.surface)

            if location == .folder(""), search.isEmpty {
                Section("Quick access") {
                    shortcut("All features", subtitle: "Search generated keypoint files across datasets", icon: "point.3.connected.trianglepath.dotted", to: .allFeatures)
                    shortcut("Datasets", subtitle: "Local videos and dataset folders", icon: "folder", to: .folder("Datasets"))
                    shortcut("Feature folders", subtitle: "Browse the output directory hierarchy", icon: "square.stack.3d.up", to: .folder("Datasets/Features"))
                    shortcut("Downloads", subtitle: "Downloaded archives and transfer files", icon: "arrow.down.circle", to: .folder("Downloads"))
                    shortcut("Models", subtitle: "Weights, configurations and saved runs", icon: "brain", to: .folder("Models"))
                    shortcut("Checkpoints", subtitle: "Training resume artifacts", icon: "clock.arrow.circlepath", to: .folder("Checkpoints"))
                    shortcut("Training state", subtitle: "Saved session state", icon: "doc.text", to: .folder("TrainingState"))
                }
                .listRowBackground(Palette.surface)
            }

            Section {
                if isLoading {
                    ProgressView("Reading files…")
                        .font(Typo.body)
                        .tint(Palette.accent)
                }
                if let error {
                    Text(error).font(Typo.body).foregroundStyle(Palette.warning)
                } else if filtered.isEmpty, !isLoading {
                    Text(search.isEmpty ? "No files here yet." : "No files match your search.")
                        .font(Typo.body)
                        .foregroundStyle(Palette.textSecondary)
                }
                ForEach(filtered) { entry in
                    NavigationLink(value: entry) {
                        LocalFileRow(entry: entry, showsPath: location == .allFeatures)
                    }
                }
            } header: {
                HStack {
                    Text(location == .allFeatures ? "Feature files" : "Folder contents").font(Typo.eyebrow)
                    Spacer()
                    Text(filtered.count.formatted()).font(Typo.monoCaption)
                }
                .foregroundStyle(Palette.textTertiary)
            }
            .listRowBackground(Palette.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Palette.ground)
        .navigationTitle(location.title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: location == .allFeatures ? "Search feature names or paths" : "Search this folder")
        .task(id: location) { await refresh() }
        .refreshable { await refresh() }
        .toolbar {
            LocalFileCloseControl(action: onClose)
            ToolbarItem(placement: .primaryAction) {
                IconButton(systemImage: "arrow.clockwise", accessibilityLabel: "Refresh local files") {
                    Task { await refresh() }
                }
                .disabled(isLoading)
            }
        }
    }

    private func shortcut(_ title: String, subtitle: String, icon: String, to destination: LocalFileLocation) -> some View {
        NavigationLink(value: destination) {
            HStack(spacing: Spacing.md) {
                Image(systemName: icon).font(Typo.title2).foregroundStyle(Palette.accent)
                    .frame(width: Metrics.touchTarget)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title).font(Typo.headline).foregroundStyle(Palette.textPrimary)
                    Text(subtitle).font(Typo.caption).foregroundStyle(Palette.textSecondary)
                }
            }
            .frame(minHeight: Metrics.touchTarget)
        }
    }

    private func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let snapshot: [LocalFileEntry]
            switch location {
            case .folder(let path): snapshot = try await store.list(directory: path)
            case .allFeatures: snapshot = try await store.allFeatures()
            }
            try Task.checkCancellation()
            entries = snapshot
            error = nil
        } catch is CancellationError {
            // A dismissed browser should not replace its snapshot with an error.
        } catch {
            entries = []
            self.error = error.localizedDescription
        }
    }
}

struct LocalFileCloseControl: ToolbarContent {
    let action: () -> Void
    var body: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Done", action: action)
                .font(Typo.control)
                .frame(minHeight: Metrics.touchTarget)
        }
    }
}

private struct LocalFileRow: View {
    let entry: LocalFileEntry
    let showsPath: Bool
    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: entry.kind.icon)
                .font(Typo.title2)
                .foregroundStyle(entry.isDirectory ? Palette.accent : Palette.accentBlue)
                .frame(width: Metrics.touchTarget)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(entry.name).font(Typo.body).foregroundStyle(Palette.textPrimary).lineLimit(2)
                if showsPath {
                    Text(entry.path).font(Typo.monoSmall).foregroundStyle(Palette.textTertiary).lineLimit(2)
                }
                if !entry.isDirectory {
                    Text(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))
                        .font(Typo.monoCaption).foregroundStyle(Palette.textSecondary)
                }
            }
        }
        .frame(minHeight: Metrics.touchTarget, alignment: .leading)
    }
}
