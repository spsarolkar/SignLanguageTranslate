import Foundation

/// Display summary of one dataset's download tasks: part counts, the overall
/// bar's complete and in-flight fractions, and per-category part progress.
/// Pure derivation; it never changes tasks.
struct DatasetTransferSummary: Equatable {

    /// Parts done downloading for one category ("4 / 8").
    struct CategoryProgress: Identifiable, Equatable {
        enum State { case none, partial, complete }

        let name: String
        let done: Int
        let total: Int

        var id: String { name }
        /// Manifest names use underscores for URLs ("Days_and_Time").
        var displayName: String { name.replacingOccurrences(of: "_", with: " ") }
        var fraction: Double { total > 0 ? Double(done) / Double(total) : 0 }
        var state: State {
            if total > 0 && done >= total { return .complete }
            return done > 0 ? .partial : .none
        }
    }

    let completeCount: Int
    let activeCount: Int
    let queuedCount: Int
    let failedCount: Int
    /// Completed parts / all parts.
    let completeFraction: Double
    /// Progress of in-flight parts, as a fraction of all parts.
    let inFlightFraction: Double
    /// Parts currently transferring or extracting, in queue order.
    let activeTasks: [DownloadTask]

    var totalCount: Int { completeCount + activeCount + queuedCount + failedCount }

    /// - Parameter tasks: One dataset's tasks.
    init(tasks: [DownloadTask]) {
        let active = tasks.filter { $0.status == .downloading || $0.status == .extracting }
        completeCount = tasks.filter { $0.status == .completed }.count
        activeCount = active.count
        failedCount = tasks.filter { $0.status == .failed }.count
        queuedCount = tasks.count - completeCount - activeCount - failedCount
        activeTasks = active

        let total = Double(tasks.count)
        completeFraction = total > 0 ? Double(completeCount) / total : 0
        inFlightFraction = total > 0 ? active.reduce(0) { $0 + $1.progress } / total : 0
    }

    /// Per-category part progress, in manifest order.
    /// - Parameter datasetCompleted: The dataset finished without tasks
    ///   (for example, imported), so categories with no tasks count as done.
    static func categories(
        _ manifest: [CategoryManifest],
        tasks: [DownloadTask],
        datasetCompleted: Bool
    ) -> [CategoryProgress] {
        let byCategory = Dictionary(grouping: tasks, by: \.category)
        return manifest.map { category in
            let categoryTasks = byCategory[category.name] ?? []
            let done: Int
            if categoryTasks.isEmpty && datasetCompleted {
                done = category.partCount
            } else {
                done = categoryTasks.filter { $0.status == .completed }.count
            }
            return CategoryProgress(name: category.name, done: done, total: category.partCount)
        }
    }
}
