# Phase 2.6 — Download Progress UI Components

Create SwiftUI components for displaying download progress in SignLanguageTranslate.

## Context

We have:
- `DownloadManager`: Observable wrapper for the download queue
- `DownloadTask`: Model with progress, status, category info
- `DownloadTaskGroup`: Groups tasks by category
- `DownloadTaskStatus`: Enum with display properties

Now we need UI components to visualize download progress.

## Files to Create

### 1. Features/DatasetManager/Views/Components/DownloadProgressRing.swift

A circular progress indicator:
- Configurable size (small, medium, large)
- Shows percentage in center
- Color based on status
- Animated progress changes
- Indeterminate mode for unknown progress

```swift
struct DownloadProgressRing: View {
    let progress: Double  // 0.0 to 1.0
    let status: DownloadTaskStatus
    var size: Size = .medium
    
    enum Size {
        case small, medium, large
        var dimension: CGFloat { ... }
        var lineWidth: CGFloat { ... }
        var fontSize: Font { ... }
    }
}
```

### 2. Features/DatasetManager/Views/Components/DownloadTaskRowView.swift

Row view for individual download task:
- Category icon based on category name
- Task display name
- Progress ring (small)
- Status text
- Bytes downloaded / total
- Pause/Resume/Retry button based on status
- Swipe actions for cancel

### 3. Features/DatasetManager/Views/Components/DownloadCategoryHeaderView.swift

Header for category group in download list:
- Category name
- Icon
- Combined progress bar
- Completed count / total count
- Expandable/collapsible

### 4. Features/DatasetManager/Views/DownloadListView.swift

Main download list view:
- Grouped by category (using DownloadTaskGroup)
- Category headers with combined progress
- Task rows under each category
- Empty state when no downloads
- Pull to refresh
- Toolbar with:
  - Pause All / Resume All button
  - Retry Failed button (if any failed)
  - Cancel All button

### 5. Features/DatasetManager/Views/Components/DownloadSummaryBanner.swift

Compact banner showing overall progress:
- Overall progress bar
- Status text ("Downloading 3 of 46 files")
- Downloaded / Total bytes
- Estimated time remaining (optional)
- Tap to expand to full list

### 6. Features/DatasetManager/Views/DownloadSheet.swift

Sheet presentation wrapper:
- Contains DownloadListView
- Header with close button
- Overall statistics at top
- Proper sheet sizing for iPad

## Requirements

1. Use `@Observable` and `@Environment` for DownloadManager access
2. Smooth animations for progress updates
3. SF Symbols for icons (use category-appropriate symbols)
4. Support dark mode
5. iPad-optimized layouts
6. Accessible (VoiceOver labels)

## Icon Mapping for Categories

Create a helper to map category names to SF Symbols:
- Animals → "pawprint.fill"
- Adjectives → "textformat"
- Clothes → "tshirt.fill"
- Colours → "paintpalette.fill"
- Days_and_Time → "calendar"
- Electronics → "desktopcomputer"
- Greetings → "hand.wave.fill"
- Home → "house.fill"
- Jobs → "briefcase.fill"
- Means_of_Transportation → "car.fill"
- People → "person.2.fill"
- Places → "mappin.and.ellipse"
- Pronouns → "person.fill.questionmark"
- Seasons → "leaf.fill"
- Society → "building.2.fill"
- Default → "folder.fill"

## Preview Providers

Add preview providers for all views using mock data:
- Preview with tasks in various states
- Preview with empty state
- Preview with all completed
- Preview with some failed
