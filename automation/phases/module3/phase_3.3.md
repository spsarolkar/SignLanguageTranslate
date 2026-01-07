# Phase 3.3 — Dataset List View

Create the main list view showing all datasets.

## Context

We have:
- `DatasetRowView` for individual rows
- `Dataset` model with query helpers
- `ModelQueries` for fetching datasets
- Navigation structure

## Files to Create

### 1. Features/DatasetManager/Views/DatasetListView.swift

Main list of datasets:

```swift
struct DatasetListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Dataset.name) private var datasets: [Dataset]
    @Binding var selectedDataset: Dataset?
    
    var body: some View {
        List(selection: $selectedDataset) {
            // Available Datasets section
            // Downloaded section
            // In Progress section
        }
        .listStyle(.sidebar)
        .navigationTitle("Datasets")
        .toolbar { ... }
    }
}
```

### 2. Sections

Organize datasets into sections:

**Available to Download**
- Datasets with status `.notStarted`
- Shows estimated size
- "Download" button

**Downloading**
- Datasets with status `.downloading` or `.processing`
- Shows progress
- Pause/Resume controls

**Ready to Use**
- Datasets with status `.completed`
- Shows sample count
- Storage used

**Failed**
- Datasets with status `.failed`
- Shows error message
- Retry button

### 3. Features/DatasetManager/Views/Components/DatasetSectionHeader.swift

Section header with:
- Section title
- Count badge
- Optional action button
- Collapse/expand support

### 4. Toolbar Actions

Add toolbar items:
- Add Dataset button (for future custom imports)
- Refresh button
- Sort options menu
- Filter options

### 5. Empty State

When no datasets exist:
- Illustration
- "Get Started" message
- Button to initialize default datasets

### 6. Context Menu

For each dataset row:
- Start Download / Pause / Resume
- View Details
- Delete (with confirmation)
- Show in Finder (if downloaded)

## Features

1. Pull to refresh
2. Swipe actions (delete, pause)
3. Search/filter capability
4. Sort by name, size, status
5. Multi-select for batch operations

## Requirements

1. Use @Query for reactive updates
2. Animate list changes
3. Preserve selection across updates
4. Handle empty states gracefully
5. Accessible navigation
