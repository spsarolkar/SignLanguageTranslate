# Phase 4.6 — Download Error Handling UI

Implement comprehensive error handling and recovery in the UI.

## Context

We have:
- DownloadEngine with error handling
- DownloadError enum
- UI connected to real downloads

Need to display errors appropriately and allow recovery.

## Files to Create

### 1. Features/DatasetManager/Views/Components/DownloadErrorView.swift

View for displaying download errors:

```swift
struct DownloadErrorView: View {
    let error: DownloadError
    let onRetry: () -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: iconName)
                .font(.largeTitle)
                .foregroundStyle(iconColor)
            
            Text(error.localizedDescription)
                .font(.headline)
                .multilineTextAlignment(.center)
            
            if let suggestion = error.recoverySuggestion {
                Text(suggestion)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            HStack(spacing: 12) {
                if error.isRetryable {
                    Button("Retry") { onRetry() }
                        .buttonStyle(.borderedProminent)
                }
                
                Button("Dismiss") { onDismiss() }
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
}
```

### 2. Features/DatasetManager/Views/Components/DownloadErrorBanner.swift

Dismissible banner for errors:

```swift
struct DownloadErrorBanner: View {
    let failedCount: Int
    let onShowDetails: () -> Void
    let onRetryAll: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            
            Text("\(failedCount) download(s) failed")
                .font(.subheadline)
            
            Spacer()
            
            Button("Retry All", action: onRetryAll)
                .font(.subheadline)
                .buttonStyle(.bordered)
            
            Button("Details", action: onShowDetails)
                .font(.subheadline)
        }
        .padding()
        .background(Color.yellow.opacity(0.2))
        .cornerRadius(8)
    }
}
```

### 3. Features/DatasetManager/Views/DownloadErrorListView.swift

List of all failed downloads:

```swift
struct DownloadErrorListView: View {
    @Environment(DownloadManager.self) private var manager
    
    var body: some View {
        List {
            ForEach(manager.failedTasks) { task in
                FailedTaskRow(task: task) {
                    Task { await manager.retryTask(task.id) }
                }
            }
        }
        .navigationTitle("Failed Downloads")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Retry All") {
                    Task { await manager.retryFailed() }
                }
                .disabled(manager.failedTasks.isEmpty)
            }
        }
    }
}

struct FailedTaskRow: View {
    let task: DownloadTask
    let onRetry: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                CategoryIconView(category: task.category, size: .small)
                Text(task.displayName)
                    .font(.headline)
            }
            
            if let error = task.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            
            Button("Retry", action: onRetry)
                .buttonStyle(.bordered)
                .tint(.blue)
        }
        .padding(.vertical, 4)
    }
}
```

### 4. Features/DatasetManager/Views/Components/StorageWarningView.swift

Warning when storage is low:

```swift
struct StorageWarningView: View {
    let availableSpace: Int64
    let requiredSpace: Int64
    let onClearCache: () -> Void
    let onContinueAnyway: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            
            Text("Low Storage Space")
                .font(.title2.bold())
            
            VStack(spacing: 4) {
                Text("Available: \(formattedSize(availableSpace))")
                Text("Required: \(formattedSize(requiredSpace))")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            
            Text("You may not have enough space to complete this download.")
                .font(.body)
                .multilineTextAlignment(.center)
            
            HStack(spacing: 12) {
                Button("Clear Cache") { onClearCache() }
                    .buttonStyle(.bordered)
                
                Button("Continue Anyway") { onContinueAnyway() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
    }
}
```

### 5. Features/DatasetManager/Views/Components/NetworkErrorView.swift

Network-specific error view:

```swift
struct NetworkErrorView: View {
    let isConnected: Bool
    let connectionType: NetworkMonitor.ConnectionType
    let onRetry: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: isConnected ? "wifi.exclamationmark" : "wifi.slash")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            
            Text(isConnected ? "Connection Error" : "No Internet Connection")
                .font(.title2.bold())
            
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            if isConnected {
                Button("Retry", action: onRetry)
                    .buttonStyle(.borderedProminent)
            } else {
                Text("Downloads will resume automatically when connected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
    }
}
```

### 6. Update DownloadListView with Error Handling

```swift
struct DownloadListView: View {
    @Environment(DownloadManager.self) private var manager
    @State private var showingErrorList = false
    @State private var showingStorageWarning = false
    
    var body: some View {
        List {
            // Error banner if there are failures
            if manager.failedCount > 0 {
                DownloadErrorBanner(
                    failedCount: manager.failedCount,
                    onShowDetails: { showingErrorList = true },
                    onRetryAll: { Task { await manager.retryFailed() } }
                )
            }
            
            // Network warning
            if !networkMonitor.isConnected {
                NetworkStatusBanner()
            }
            
            // Rest of list...
        }
        .sheet(isPresented: $showingErrorList) {
            NavigationStack {
                DownloadErrorListView()
            }
        }
        .alert("Low Storage", isPresented: $showingStorageWarning) {
            Button("Clear Cache") { clearCache() }
            Button("Continue") { continueDownload() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You may not have enough storage space.")
        }
    }
}
```

### 7. Error-Specific Task Row States

Update DownloadTaskRowView for error states:

```swift
extension DownloadTaskRowView {
    @ViewBuilder
    var errorOverlay: some View {
        if task.status == .failed {
            HStack {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                
                if let error = task.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }
        }
    }
}
```

### 8. Automatic Retry Logic

Add to DownloadManager:

```swift
extension DownloadManager {
    private func setupAutoRetry() {
        // Retry failed downloads when network reconnects
        networkMonitor.$isConnected
            .filter { $0 }
            .sink { [weak self] _ in
                Task { await self?.retryFailedIfNeeded() }
            }
            .store(in: &cancellables)
    }
    
    private func retryFailedIfNeeded() async {
        let retryableTasks = await queue.getFailedTasks()
            .filter { $0.retryCount < 3 }
        
        for task in retryableTasks {
            await retryTask(task.id)
        }
    }
}
```

## Error Scenarios to Handle

1. **Network Disconnection**
   - Show banner
   - Pause active downloads
   - Auto-resume on reconnect

2. **Server Error (5xx)**
   - Mark as failed
   - Allow retry
   - Show server error message

3. **File Not Found (404)**
   - Mark as failed
   - Don't auto-retry
   - Suggest checking URL

4. **Insufficient Storage**
   - Warn before starting
   - Pause if space runs out
   - Suggest clearing cache

5. **Timeout**
   - Auto-retry (up to 3 times)
   - Show timeout error
   - Allow manual retry

6. **Corrupted Resume Data**
   - Clear resume data
   - Start fresh download
   - Log for debugging

## Requirements

1. Clear error messages for users
2. Appropriate recovery options
3. Auto-retry where sensible
4. No data loss on errors
5. Accessible error descriptions
