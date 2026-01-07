# Phase 3.5 — Download Task Row View

Enhance the download task row view with full functionality.

## Context

We have:
- `DownloadTask` model with status, progress, category
- `DownloadTaskStatus` with display properties
- Basic `DownloadTaskRowView` from 2.6
- `DownloadManager` for controlling downloads

## Files to Create/Update

### 1. Update Features/DatasetManager/Views/Components/DownloadTaskRowView.swift

Enhanced row view:

```swift
struct DownloadTaskRowView: View {
    let task: DownloadTask
    let onPause: () -> Void
    let onResume: () -> Void
    let onCancel: () -> Void
    let onRetry: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Category icon
            CategoryIconView(category: task.category)
            
            // Info stack
            VStack(alignment: .leading, spacing: 4) {
                Text(task.displayName)
                    .font(.headline)
                
                HStack {
                    StatusBadge(status: task.status)
                    if task.isActive {
                        Text(task.progressText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                if task.status == .downloading {
                    ProgressView(value: task.progress)
                        .tint(task.status.color)
                }
            }
            
            Spacer()
            
            // Action button
            ActionButton(task: task, ...)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .contextMenu { ... }
        .swipeActions { ... }
    }
}
```

### 2. Features/DatasetManager/Views/Components/CategoryIconView.swift

Icon for download category:
- Maps category name to SF Symbol
- Colored background circle
- Multiple sizes

```swift
struct CategoryIconView: View {
    let category: String
    var size: IconSize = .medium
    
    enum IconSize {
        case small, medium, large
    }
    
    private var symbolName: String {
        switch category {
        case "Animals": return "pawprint.fill"
        case "Adjectives": return "textformat"
        // ... all category mappings
        default: return "folder.fill"
        }
    }
    
    private var backgroundColor: Color {
        // Generate consistent color from category name
    }
}
```

### 3. Features/DatasetManager/Views/Components/DownloadActionButton.swift

Action button that changes based on status:

```swift
struct DownloadActionButton: View {
    let task: DownloadTask
    let onAction: () -> Void
    
    var body: some View {
        Button(action: onAction) {
            Image(systemName: iconName)
        }
        .buttonStyle(.bordered)
        .tint(tintColor)
    }
    
    private var iconName: String {
        switch task.status {
        case .pending, .queued: return "play.fill"
        case .downloading: return "pause.fill"
        case .paused: return "play.fill"
        case .failed: return "arrow.clockwise"
        case .completed: return "checkmark"
        case .extracting: return "gearshape"
        }
    }
}
```

### 4. Swipe Actions

Implement swipe actions:
- Leading: Priority/Prioritize
- Trailing: Cancel/Remove

### 5. Context Menu

Right-click menu:
- Pause/Resume
- Prioritize (move to front)
- Cancel
- Copy URL
- Show in Finder (if completed)

### 6. Accessibility

- VoiceOver labels
- Accessibility actions
- Reduced motion support

## Visual States

```
Pending:     [▷] Animals Part 1     ○ Pending
Queued:      [▷] Animals Part 2     ○ Queued
Downloading: [⏸] Clothes Part 1     ████░░ 45%  12MB/26MB
Paused:      [▷] Colors Part 1      ⏸ Paused
Extracting:  [⚙] Home Part 1        ⚙ Extracting...
Completed:   [✓] Seasons            ✓ Complete
Failed:      [↻] Jobs Part 1        ✗ Failed - Retry
```

## Requirements

1. Smooth progress animations
2. Responsive to state changes
3. Touch-friendly hit targets
4. Keyboard accessible
5. Preview with all states
