# Phase 4.5 — Connect Download UI to Engine

Wire up the UI components to the actual download engine.

## Context

We have:
- Download UI components (DownloadListView, TaskRowView, etc.)
- DownloadManager (simulated progress)
- DownloadEngine (real downloads)
- BackgroundSessionManager

Now connect everything so UI reflects real download progress.

## Files to Update

### 1. Update DownloadManager

Remove simulation, connect to engine:

```swift
@Observable
final class DownloadManager {
    private let engine: DownloadEngine
    private let queue: DownloadQueueActor
    private let persistence: DownloadStatePersistence
    
    // Published state
    private(set) var tasks: [DownloadTask] = []
    private(set) var isDownloading = false
    private(set) var isPaused = false
    
    // Progress
    private(set) var overallProgress: Double = 0
    private(set) var downloadedBytes: Int64 = 0
    private(set) var totalBytes: Int64 = 0
    private(set) var downloadRate: Double = 0
    private(set) var estimatedTimeRemaining: TimeInterval?
    
    init() {
        self.queue = DownloadQueueActor()
        self.engine = DownloadEngine(queue: queue)
        self.persistence = DownloadStatePersistence()
        
        // Setup engine callbacks
        setupEngineCallbacks()
    }
    
    private func setupEngineCallbacks() {
        engine.onTaskUpdated = { [weak self] task in
            await self?.handleTaskUpdate(task)
        }
        engine.onTaskCompleted = { [weak self] task in
            await self?.handleTaskComplete(task)
        }
        // ... etc
    }
    
    // MARK: - Public API
    
    func loadINCLUDEManifest() async {
        let entries = INCLUDEManifest.allEntries()
        let tasks = entries.map { DownloadTask(from: $0, datasetName: "INCLUDE") }
        await queue.enqueueAll(tasks)
        await refresh()
    }
    
    func startDownloads() async {
        await engine.start()
        isDownloading = true
    }
    
    func pauseAllDownloads() async {
        await engine.pause()
        isPaused = true
    }
    
    func resumeAllDownloads() async {
        await engine.resume()
        isPaused = false
    }
    
    // ... rest of API
}
```

### 2. Update MainNavigationView

Inject DownloadManager:

```swift
struct MainNavigationView: View {
    @State private var downloadManager = DownloadManager()
    
    var body: some View {
        NavigationSplitView { ... }
            .environment(downloadManager)
            .task {
                await downloadManager.recoverDownloads()
            }
    }
}
```

### 3. Update DatasetDetailView

Add download actions:

```swift
struct DatasetDetailView: View {
    @Bindable var dataset: Dataset
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        // ...
        
        DatasetActionsSection(
            dataset: dataset,
            onDownload: startDownload,
            onPause: pauseDownload,
            onCancel: cancelDownload
        )
    }
    
    private func startDownload() {
        Task {
            // Update dataset status
            dataset.startDownload()
            try? modelContext.save()
            
            // Load manifest and start
            await downloadManager.loadINCLUDEManifest()
            await downloadManager.startDownloads()
        }
    }
}
```

### 4. Update DownloadListView

Connect to real data:

```swift
struct DownloadListView: View {
    @Environment(DownloadManager.self) private var manager
    
    var body: some View {
        List {
            DownloadSummarySection(
                progress: manager.overallProgress,
                statusText: manager.statusText,
                progressText: manager.progressText,
                activeCount: manager.activeCount,
                pendingCount: manager.pendingCount,
                completedCount: manager.completedCount,
                failedCount: manager.failedCount
            )
            
            ForEach(manager.tasksGroupedByCategory) { group in
                DownloadCategorySection(
                    group: group,
                    onPause: { manager.pauseTask($0) },
                    onResume: { manager.resumeTask($0) },
                    onCancel: { manager.cancelTask($0) }
                )
            }
        }
        .refreshable {
            await manager.refresh()
        }
    }
}
```

### 5. Update DownloadTaskRowView

Connect actions:

```swift
struct DownloadTaskRowView: View {
    let task: DownloadTask
    @Environment(DownloadManager.self) private var manager
    
    var body: some View {
        HStack {
            // ... content
            
            DownloadActionButton(task: task) {
                handleAction()
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task { await manager.cancelTask(task.id) }
            } label: {
                Label("Cancel", systemImage: "xmark")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                Task { await manager.prioritizeTask(task.id) }
            } label: {
                Label("Priority", systemImage: "arrow.up")
            }
            .tint(.orange)
        }
    }
    
    private func handleAction() {
        Task {
            switch task.status {
            case .pending, .paused:
                await manager.resumeTask(task.id)
            case .downloading:
                await manager.pauseTask(task.id)
            case .failed:
                await manager.retryTask(task.id)
            default:
                break
            }
        }
    }
}
```

### 6. Create DownloadNotificationBanner

Show download status in UI:

```swift
struct DownloadNotificationBanner: View {
    @Environment(DownloadManager.self) private var manager
    @State private var showingDownloadSheet = false
    
    var body: some View {
        if manager.isDownloading {
            Button {
                showingDownloadSheet = true
            } label: {
                HStack {
                    ProgressView(value: manager.overallProgress)
                        .frame(width: 100)
                    
                    Text(manager.statusText)
                        .font(.caption)
                }
                .padding(8)
                .background(.ultraThinMaterial)
                .cornerRadius(8)
            }
            .sheet(isPresented: $showingDownloadSheet) {
                DownloadSheet()
            }
        }
    }
}
```

### 7. Update Dataset Model

Sync with download state:

```swift
extension Dataset {
    func syncWithDownloadManager(_ manager: DownloadManager) {
        // Update dataset status based on download state
        let tasks = manager.tasks.filter { $0.datasetName == self.name }
        
        if tasks.isEmpty { return }
        
        let completed = tasks.filter { $0.status == .completed }.count
        let total = tasks.count
        
        self.downloadedParts = completed
        self.totalParts = total
        self.downloadedBytes = tasks.reduce(0) { $0 + $1.bytesDownloaded }
        self.totalBytes = tasks.reduce(0) { $0 + $1.totalBytes }
        
        if tasks.allSatisfy({ $0.status == .completed }) {
            self.completeDownload()
        } else if tasks.contains(where: { $0.status == .failed }) {
            self.failDownload(with: "Some downloads failed")
        }
    }
}
```

## Flow Verification

Test the complete flow:

1. **Start Download**
   - Tap "Download INCLUDE" in dataset detail
   - Manifest loads, tasks created
   - Engine starts, first 3 downloads begin
   - Progress updates in UI

2. **View Progress**
   - Open Downloads section
   - See grouped tasks with progress
   - Real-time updates as downloads progress

3. **Pause/Resume**
   - Tap pause on a task
   - Resume data saved
   - Tap resume
   - Download continues from where it left off

4. **Background**
   - Send app to background
   - Downloads continue
   - Bring app back
   - Progress is accurate

5. **Completion**
   - All downloads complete
   - Dataset status updates to Ready
   - Files in correct location

## Requirements

1. UI updates smoothly (no jank)
2. All actions work correctly
3. State syncs between engine and UI
4. Background downloads reflected properly
5. Error states displayed correctly
