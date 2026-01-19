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

### 1. Update `Features/DatasetManager/Downloads/DownloadManager.swift`

Refactor the class to replace the simulated logic with the real `DownloadEngine`:
1.  **Dependencies**: Initialize `DownloadQueueActor`, `DownloadEngine` (injected with queue), and `DownloadStatePersistence`.
2.  **State Properties**: Expose published properties for the UI:
    *   `tasks`: List of `DownloadTask`.
    *   `isDownloading`: Boolean status.
    *   `isPaused`: Boolean status.
    *   `overallProgress`: Double (0-1).
    *   `downloadedBytes` / `totalBytes`.
    *   `downloadRate`: Double.
    *   `estimatedTimeRemaining`: TimeInterval?.
3.  **Engine Integration**:
    *   Setup callbacks (`onTaskUpdated`, `onTaskCompleted`, `onTaskFailed`, etc.) to update the published state on the MainActor.
    *   Implement public methods (`startDownloads`, `pauseAllDownloads`, `resumeAllDownloads`, `cancelAllDownloads`) that delegate to the `engine`.
    *   Implement `loadINCLUDEManifest` to parse the manifest, convert entries to `DownloadTask`s, and enqueue them via the `queue`.
    *   Implement task-specific actions (`pauseTask(id)`, `resumeTask(id)`, `cancelTask(id)`, `retryTask(id)`) delegating to the engine.

### 2. Update `Features/App/MainNavigationView.swift`

*   Inject the `DownloadManager` instance into the environment so it's accessible globally.
*   Add a `.task` modifier to call `downloadManager.recoverDownloads()` on launch.

### 3. Update `Features/DatasetManager/Views/DatasetDetailView.swift`

*   Consume `DownloadManager` from the environment.
*   Update the `DatasetActionsSection` callbacks to trigger real downloads:
    *   **On Download**: Update dataset status to `.downloading`, save context, load the manifest via manager, and start downloads.
    *   **On Pause/Cancel**: Call respective manager methods.

### 4. Update `Features/DatasetManager/Views/DownloadListView.swift`

*   Connect the view to the real `DownloadManager` data.
*   **Summary Section**: Bind to manager's `overallProgress`, `downloadeBytes`, etc.
*   **Task List**: Display tasks grouped by category (use `manager.tasksGroupedByCategory` if available, or compute it).
*   **Actions**: Wire up the "Pause All", "Resume All", and "Cancel All" buttons in the navigation bar/toolbar.
*   **Refreshable**: Call `manager.refresh()` on pull-to-refresh.

### 5. Update `Features/DatasetManager/Views/Components/DownloadTaskRowView.swift`

*   **Primary Action**: specific simple button based on task status (e.g., Pause icon if downloading, Play if paused/pending, Retry if failed).
*   **Swipe Actions**:
    *   **Trailing**: "Cancel" (Destructive).
    *   **Leading**: "Prioritize" (Orange) -> calls `manager.prioritizeTask`.

### 6. Create `Features/DatasetManager/Views/Components/DownloadNotificationBanner.swift`

*   Create a view that appears when `manager.isDownloading` is true.
*   **Content**: Show a small progress bar, status text, and a button to open the full `DownloadSheet` (or navigate to DownloadListView).
*   **Placement**: Typically placed at the bottom of the main navigation view or inside a `.overlay`.

### 7. Update `SignLanguageTranslate/Models/Dataset.swift`

*   Add a helper method `syncWithDownloadManager(_ manager: DownloadManager)`.
*   **Logic**:
    *   Filter manager's tasks for this dataset.
    *   Update `downloadedParts`, `totalParts`, `downloadedBytes`, `totalBytes`.
    *   Update status:
        *   If all tasks `.completed` -> Mark dataset `.completed` / `.ready`.
        *   If any task `.failed` -> Mark dataset `.failed`.

## Flow Verification

Test the complete flow:
1.  **Start**: "Download INCLUDE" -> Engine starts -> UI updates.
2.  **Monitor**: Downloads tab shows real-time progress and speed.
3.  **Control**: Pause/Resume individual tasks and all tasks.
4.  **Persistence**: Restart app -> previous download state is recovered.
5.  **Completion**: All tasks finish -> Dataset becomes "Ready".

## Requirements

1.  UI updates must be smooth (throttled updates if necessary).
2.  Unidirectional data flow: View -> Manager -> Engine -> Callback -> Manager -> View.
3.  Accurate handling of background/foreground transitions.
