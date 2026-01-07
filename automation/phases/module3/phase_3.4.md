# Phase 3.4 — Integrate List into Split View

Connect the dataset list with navigation and detail views.

## Context

We have:
- `MainNavigationView` with split view structure
- `DatasetListView` showing all datasets
- `DatasetRowView` for list items
- Dataset models and queries

## Files to Update/Create

### 1. Update Features/DatasetManager/Views/MainNavigationView.swift

Integrate components:

```swift
struct MainNavigationView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedSection: NavigationSection? = .datasets
    @State private var selectedDataset: Dataset?
    @State private var showingDownloadSheet = false
    
    var body: some View {
        NavigationSplitView {
            SidebarView(selectedSection: $selectedSection)
        } content: {
            switch selectedSection {
            case .datasets:
                DatasetListView(selectedDataset: $selectedDataset)
            case .downloads:
                DownloadListView()
            // ...
            }
        } detail: {
            if let dataset = selectedDataset {
                DatasetDetailView(dataset: dataset)
            } else {
                EmptyDetailView()
            }
        }
    }
}
```

### 2. Features/DatasetManager/Views/DatasetDetailView.swift

Detail view for selected dataset:

```swift
struct DatasetDetailView: View {
    @Bindable var dataset: Dataset
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header with icon, name, status
                DatasetHeaderSection(dataset: dataset)
                
                // Statistics cards
                DatasetStatsSection(dataset: dataset)
                
                // Actions (Download, Browse, Delete)
                DatasetActionsSection(dataset: dataset)
                
                // Categories list (if downloaded)
                if dataset.isReady {
                    DatasetCategoriesSection(dataset: dataset)
                }
            }
            .padding()
        }
        .navigationTitle(dataset.name)
        .toolbar { ... }
    }
}
```

### 3. Features/DatasetManager/Views/Components/DatasetHeaderSection.swift

Header section with:
- Large dataset icon
- Full name
- Description
- Status badge
- Last updated date

### 4. Features/DatasetManager/Views/Components/DatasetStatsSection.swift

Statistics cards:
- Total samples
- Total categories/labels
- Storage used
- Download date

### 5. Features/DatasetManager/Views/Components/DatasetActionsSection.swift

Action buttons:
- Primary: "Download" or "Browse Samples"
- Secondary: "View in Files", "Delete"
- Progress indicator if downloading

### 6. Features/DatasetManager/Views/Components/DatasetCategoriesSection.swift

List of categories (for downloaded datasets):
- Category name and icon
- Sample count per category
- Tap to browse category

### 7. Update SidebarView

Add badge for active downloads:
```swift
Label("Downloads", systemImage: "arrow.down.circle")
    .badge(activeDownloadCount)
```

## Navigation Behavior

1. Selecting dataset in list shows detail
2. Back button behavior on compact widths
3. Keyboard navigation (arrow keys, enter)
4. URL/deep linking support (future)

## Requirements

1. Smooth transitions between views
2. State preservation when switching sections
3. Responsive layout for different iPad sizes
4. Loading states for async data
5. Error handling with user feedback
