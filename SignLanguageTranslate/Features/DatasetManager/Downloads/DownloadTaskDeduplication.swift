import Foundation

/// Finds tasks that download the same file for the same dataset.
///
/// Older builds re-enqueued the whole manifest on every zip import, so a
/// saved queue can hold two tasks per part: one completed, one pending.
/// For each (dataset, URL) the most advanced task is kept — completed first,
/// then by status, then most bytes, then the oldest — and the rest dropped.
enum DownloadTaskDeduplication {

    /// IDs of tasks to drop; empty when every part appears once.
    static func duplicateIDs(in tasks: [DownloadTask]) -> Set<UUID> {
        let groups = Dictionary(grouping: tasks) { PartKey(datasetName: $0.datasetName, url: $0.url) }
        var drop = Set<UUID>()
        for group in groups.values where group.count > 1 {
            let keep = group.max(by: isLessAdvanced)!
            for task in group where task.id != keep.id {
                drop.insert(task.id)
            }
        }
        return drop
    }

    private struct PartKey: Hashable {
        let datasetName: String
        let url: URL
    }

    /// Orders by how much work a task represents; `max` picks the keeper.
    private static func isLessAdvanced(_ a: DownloadTask, _ b: DownloadTask) -> Bool {
        if rank(a.status) != rank(b.status) { return rank(a.status) < rank(b.status) }
        if a.bytesDownloaded != b.bytesDownloaded { return a.bytesDownloaded < b.bytesDownloaded }
        // Older wins ties: it is the one the rest of the app has seen longest.
        return a.createdAt > b.createdAt
    }

    private static func rank(_ status: DownloadTaskStatus) -> Int {
        switch status {
        case .completed: return 6
        case .extracting: return 5
        case .downloading: return 4
        case .paused: return 3
        case .queued: return 2
        case .pending: return 1
        case .failed: return 0
        }
    }
}
