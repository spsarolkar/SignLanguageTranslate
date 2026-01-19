# Phase 4.6 — Download Error Handling UI

Implement comprehensive error handling and recovery in the UI.

## Context

We have:
- DownloadEngine with error handling
- DownloadError enum
- UI connected to real downloads

Need to display errors appropriately and allow recovery.

## Files to Create

### 1. `Features/DatasetManager/Views/Components/DownloadErrorView.swift`

Create a reusable view for displaying download errors:
*   **Inputs**: `DownloadError`, `onRetry` closure, `onDismiss` closure.
*   **UI**:
    *   Icon (warning/error symbol).
    *   Error description text.
    *   Recovery suggestion (if available).
    *   "Retry" button (if error is retryable).
    *   "Dismiss" button.

### 2. `Features/DatasetManager/Views/Components/DownloadErrorBanner.swift`

Create a small, dismissible banner for the top of lists:
*   **Content**: "X failed downloads" summary.
*   **Actions**: "Retry All" and "Details".
*   **Style**: Yellow/Orange background styling to indicate warning.

### 3. `Features/DatasetManager/Views/DownloadErrorListView.swift`

Create a detailed list view for failed tasks:
*   **Source**: `manager.failedTasks`.
*   **Components**: `FailedTaskRow` for each item (showing file name, error message, retry button).
*   **Toolbar**: "Retry All" button.

### 4. `Features/DatasetManager/Views/Components/StorageWarningView.swift`

Create a warning view for insufficient disk space:
*   **Inputs**: `availableSpace`, `requiredSpace`.
*   **UI**:
    *   Large warning icon.
    *   Text showing Available vs Required space.
    *   "Clear Cache" button.
    *   "Continue Anyway" button (optional override).

### 5. `Features/DatasetManager/Views/Components/NetworkErrorView.swift`

Create a view for network connectivity issues:
*   **Inputs**: `isConnected`, `connectionType`, `onRetry`.
*   **UI**:
    *   WiFi slash icon.
    *   "No Internet Connection" or "Connection Error" text.
    *   Manual "Retry" button (if connected but failing) or info text ("Will resume automatically").

## Files to Update

### 6. Update `Features/DatasetManager/Views/DownloadListView.swift`

Integrate the new error views:
*   **Error Banner**: Show `DownloadErrorBanner` at the top if `manager.failedCount > 0`.
*   **Sheet**: Tapping "Details" on banner opens `DownloadErrorListView`.
*   **Network**: Show `NetworkStatusBanner` (or similar) if `!networkMonitor.isConnected`.
*   **Storage**: Show `StorageWarningView` (via alert or sheet) if a download start fails due to space.

### 7. Update `Features/DatasetManager/Views/Components/DownloadTaskRowView.swift`

*   **Error State**: If `task.status == .failed`, display a red exclamation icon and the error message (truncated) or an error overlay.

### 8. Update `Features/DatasetManager/Downloads/DownloadManager.swift`

Implement automatic retry logic:
*   **Auto-Retry**: Monitor `NetworkMonitor.isConnected`. When connection restores, trigger `retryFailedIfNeeded()`.
*   **Logic**: Only auto-retry tasks that are marked as retryable and have `retryCount < maxRetries`.
*   **Error Categorization**: ensure errors are properly exposed so UI knows if they are network, storage, or server related.

## Error Scenarios to Handle

1.  **Network Disconnection**: Pause active, auto-resume on reconnect.
2.  **Server Error (5xx)**: Mark failed, allow manual retry.
3.  **File Not Found (404)**: Mark failed, no auto-retry.
4.  **Insufficient Storage**: Pre-check before start, warn user.
5.  **Corrupted Resume Data**: Discard resume data and restart from scratch.

## Requirements

1.  Clear, user-friendly error messages (no raw error codes).
2.  Always provide a way out (Retry, Cancel, or Dismiss).
3.  Do not spam retries infinitely.
4.  No data loss/corruption on crash or error.
