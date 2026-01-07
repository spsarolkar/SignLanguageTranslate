# Phase 3.2 — Dataset List Item View

Create the row view for displaying datasets in the list.

## Context

We have:
- `Dataset` SwiftData model with name, type, status, progress
- `DatasetType` enum (INCLUDE, ISL-CSLTR)
- `DownloadStatus` enum with display properties
- Navigation structure from 3.1

## Files to Create

### 1. Features/DatasetManager/Views/Components/DatasetRowView.swift

Row view for dataset in list:

```swift
struct DatasetRowView: View {
    let dataset: Dataset
    
    var body: some View {
        HStack(spacing: 12) {
            // Dataset icon (based on type)
            // Name and description
            // Status indicator
            // Progress (if downloading)
        }
    }
}
```

Include:
- Large icon based on DatasetType (hand symbol variations)
- Dataset name (bold)
- Short description or sample count
- Status badge (color-coded)
- Progress indicator if downloading
- File size info
- Chevron for navigation

### 2. Features/DatasetManager/Views/Components/DatasetStatusBadge.swift

Reusable status badge:
- Color based on DownloadStatus
- Icon + text
- Compact and full modes
- Animated for active states

### 3. Features/DatasetManager/Views/Components/DatasetProgressIndicator.swift

Progress indicator for downloading:
- Linear progress bar
- Percentage text
- Parts progress (e.g., "12/46 parts")
- Bytes downloaded / total
- Cancel button

### 4. Features/DatasetManager/Views/Components/DatasetIconView.swift

Icon view for dataset types:
- INCLUDE: ASL hand signs icon
- ISL-CSLTR: ISL-specific icon
- Configurable size
- Background circle with type color

## Visual Design

```
┌────────────────────────────────────────────────────────┐
│ ┌────┐                                                 │
│ │ 🤟 │  INCLUDE Dataset                    [Ready] ✓  │
│ └────┘  Indian Sign Language words                     │
│         12,500 samples • 45.2 GB                   >   │
└────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────┐
│ ┌────┐                                                 │
│ │ 🤲 │  ISL-CSLTR Dataset              [Downloading]  │
│ └────┘  Sentence-level translations                    │
│         ████████░░░░░░░░░░░░  45%  4.5 GB / 10 GB  >   │
└────────────────────────────────────────────────────────┘
```

## Requirements

1. Smooth animations for progress updates
2. Accessible labels
3. Support for context menus (right-click)
4. Highlight state for selection
5. Preview providers with various states
