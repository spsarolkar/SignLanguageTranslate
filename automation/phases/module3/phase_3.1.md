# Phase 3.1 — App Navigation Structure

Create the main navigation structure for SignLanguageTranslate iPad app.

## Context

We have:
- SwiftData models (Dataset, Label, VideoSample)
- PersistenceController for data management
- Download system (DownloadManager, UI components)

Now we need the main app navigation shell using NavigationSplitView for iPad.

## Files to Create/Update

### 1. Features/DatasetManager/Views/MainNavigationView.swift

Create the main navigation container:

```swift
struct MainNavigationView: View {
    @State private var selectedSection: NavigationSection? = .datasets
    @State private var selectedDataset: Dataset?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    
    enum NavigationSection: String, CaseIterable, Identifiable {
        case datasets = "Datasets"
        case downloads = "Downloads"
        case training = "Training"
        case settings = "Settings"
        
        var id: String { rawValue }
        var icon: String { ... }
    }
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar - section list
        } content: {
            // Content - based on selected section
        } detail: {
            // Detail - based on selected item
        }
    }
}
```

### 2. Features/DatasetManager/Views/Navigation/SidebarView.swift

Sidebar with sections:
- Datasets section (with dataset list)
- Downloads section (with badge for active downloads)
- Training section (future)
- Settings section

Include:
- Section headers
- Appropriate SF Symbols
- Badge for active download count
- Selected state styling

### 3. Features/DatasetManager/Views/Navigation/ContentColumnView.swift

Content column that switches based on selected section:
- Datasets: Show DatasetListView
- Downloads: Show DownloadListView
- Training: Show placeholder
- Settings: Show placeholder

### 4. Features/DatasetManager/Views/Navigation/DetailColumnView.swift

Detail column that shows:
- Dataset detail when dataset selected
- Download detail when download selected
- Empty state with instructions when nothing selected

### 5. Features/DatasetManager/Views/Navigation/EmptyDetailView.swift

Placeholder view when no selection:
- App icon or illustration
- Instructional text
- Quick action buttons (e.g., "Start Downloading INCLUDE")

### 6. Update App/SignLanguageTranslateApp.swift

Update the app entry point:
- Use MainNavigationView as root
- Inject modelContainer
- Inject DownloadManager into environment

## Navigation Flow

```
┌─────────────────────────────────────────────────────────────────┐
│ NavigationSplitView                                              │
├──────────┬──────────────────┬───────────────────────────────────┤
│ Sidebar  │ Content          │ Detail                            │
├──────────┼──────────────────┼───────────────────────────────────┤
│ Datasets │ Dataset List     │ Dataset Detail / Video Browser    │
│ Downloads│ Download List    │ Download Detail                   │
│ Training │ Training List    │ Training Detail                   │
│ Settings │ Settings List    │ Setting Detail                    │
└──────────┴──────────────────┴───────────────────────────────────┘
```

## Requirements

1. Proper iPad split view behavior
2. Column visibility controls
3. Smooth transitions between sections
4. State preservation when switching sections
5. Responsive to size class changes
6. Support for keyboard navigation
