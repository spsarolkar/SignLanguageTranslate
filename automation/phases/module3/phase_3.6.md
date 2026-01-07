# Phase 3.6 — Download Tasks List Sheet

Create the full download management sheet/view.

## Context

We have:
- `DownloadTaskRowView` for individual tasks
- `DownloadManager` observable
- `DownloadTaskGroup` for category grouping
- Category icons and status badges

## Files to Create/Update

### 1. Update Features/DatasetManager/Views/DownloadListView.swift

Full-featured download list:

```swift
struct DownloadListView: View {
    @Environment(DownloadManager.self) private var downloadManager
    @State private var searchText = ""
    @State private var filterStatus: DownloadTaskStatus?
    @State private var expandedCategories: Set<String> = []
    
    var body: some View {
        List {
            // Summary section
            DownloadSummarySection(manager: downloadManager)
            
            // Grouped by category
            ForEach(filteredGroups) { group in
                DisclosureGroup(
                    isExpanded: binding(for: group.category)
                ) {
                    ForEach(group.tasks) { task in
                        DownloadTaskRowView(task: task, ...)
                    }
                } label: {
                    DownloadCategoryHeaderView(group: group)
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Search downloads")
        .navigationTitle("Downloads")
        .toolbar { toolbarContent }
    }
}
```

### 2. Features/DatasetManager/Views/Components/DownloadSummarySection.swift

Summary at top of list:

```swift
struct DownloadSummarySection: View {
    let manager: DownloadManager
    
    var body: some View {
        Section {
            VStack(spacing: 16) {
                // Overall progress
                HStack {
                    VStack(alignment: .leading) {
                        Text(manager.statusText)
                            .font(.headline)
                        Text(manager.progressText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    DownloadProgressRing(
                        progress: manager.overallProgress,
                        status: currentStatus,
                        size: .large
                    )
                }
                
                // Progress bar
                ProgressView(value: manager.overallProgress)
                    .tint(.blue)
                
                // Quick stats
                HStack(spacing: 24) {
                    StatItem(title: "Active", value: "\(manager.activeCount)")
                    StatItem(title: "Pending", value: "\(manager.pendingCount)")
                    StatItem(title: "Completed", value: "\(manager.completedCount)")
                    StatItem(title: "Failed", value: "\(manager.failedCount)")
                }
            }
            .padding(.vertical, 8)
        }
    }
}
```

### 3. Features/DatasetManager/Views/Components/DownloadCategoryHeaderView.swift

Category section header:

```swift
struct DownloadCategoryHeaderView: View {
    let group: DownloadTaskGroup
    
    var body: some View {
        HStack {
            CategoryIconView(category: group.category, size: .small)
            
            VStack(alignment: .leading) {
                Text(group.category)
                    .font(.headline)
                Text("\(group.completedCount)/\(group.tasks.count) complete")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Mini progress
            if group.anyActive {
                ProgressView(value: group.totalProgress)
                    .frame(width: 60)
            } else if group.allCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }
}
```

### 4. Toolbar Content

Toolbar with:
- Pause All / Resume All toggle
- Retry All Failed button
- Cancel All button (with confirmation)
- Filter menu (by status)
- Sort menu (by category, status, progress)

### 5. Features/DatasetManager/Views/DownloadSheet.swift

Sheet wrapper for presenting downloads:

```swift
struct DownloadSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DownloadManager.self) private var downloadManager
    
    var body: some View {
        NavigationStack {
            DownloadListView()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
```

### 6. Filter & Search

Implement filtering:
- By status (downloading, pending, completed, failed)
- By category
- Search by filename/category name

### 7. Empty States

Different empty states for:
- No downloads at all: "Start a download to see progress here"
- No results for filter: "No downloads match your filter"
- All completed: "All downloads complete! 🎉"

### 8. Batch Operations

Support multi-select for:
- Pause selected
- Resume selected
- Cancel selected
- Retry selected

## Requirements

1. Real-time updates from DownloadManager
2. Smooth animations for progress/state changes
3. Efficient list rendering (LazyVStack)
4. Pull to refresh
5. Keyboard shortcuts (Cmd+P pause, Cmd+R resume)
6. iPad-optimized layout
