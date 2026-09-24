import XCTest
@testable import SignLanguageTranslate

final class DatasetTransferSummaryTests: XCTestCase {

    private func makeTask(
        _ category: String,
        part: Int,
        of total: Int,
        status: DownloadTaskStatus,
        progress: Double = 0
    ) -> DownloadTask {
        var task = DownloadTask(
            url: URL(string: "https://example.com/\(category)_\(part)of\(total).zip")!,
            category: category,
            partNumber: part,
            totalParts: total,
            datasetName: "INCLUDE",
            status: status
        )
        task.progress = progress
        return task
    }

    func test_counts_splitByStatus() {
        let summary = DatasetTransferSummary(tasks: [
            makeTask("Animals", part: 1, of: 2, status: .completed, progress: 1),
            makeTask("Animals", part: 2, of: 2, status: .downloading, progress: 0.5),
            makeTask("Home", part: 1, of: 4, status: .extracting, progress: 1),
            makeTask("Home", part: 2, of: 4, status: .pending),
            makeTask("Home", part: 3, of: 4, status: .paused, progress: 0.2),
            makeTask("Home", part: 4, of: 4, status: .failed),
        ])

        XCTAssertEqual(summary.completeCount, 1)
        XCTAssertEqual(summary.activeCount, 2)
        XCTAssertEqual(summary.queuedCount, 2)
        XCTAssertEqual(summary.failedCount, 1)
        XCTAssertEqual(summary.totalCount, 6)
        XCTAssertEqual(summary.activeTasks.map(\.category), ["Animals", "Home"])
    }

    func test_fractions_completeIsSolid_inFlightIsActiveProgress() {
        let summary = DatasetTransferSummary(tasks: [
            makeTask("Animals", part: 1, of: 2, status: .completed, progress: 1),
            makeTask("Animals", part: 2, of: 2, status: .downloading, progress: 0.5),
            makeTask("Home", part: 1, of: 2, status: .pending),
            makeTask("Home", part: 2, of: 2, status: .pending),
        ])

        XCTAssertEqual(summary.completeFraction, 0.25, accuracy: 1e-9)
        XCTAssertEqual(summary.inFlightFraction, 0.125, accuracy: 1e-9)
    }

    func test_noTasks_isEmpty() {
        let summary = DatasetTransferSummary(tasks: [])

        XCTAssertEqual(summary.totalCount, 0)
        XCTAssertEqual(summary.completeFraction, 0)
        XCTAssertEqual(summary.inFlightFraction, 0)
    }

    func test_categories_countCompletedPartsAgainstManifest() {
        let manifest = [
            CategoryManifest(name: "Animals", partCount: 2, estimatedTotalSize: nil),
            CategoryManifest(name: "Home", partCount: 4, estimatedTotalSize: nil),
            CategoryManifest(name: "Seasons", partCount: 1, estimatedTotalSize: nil),
        ]
        let tasks = [
            makeTask("Animals", part: 1, of: 2, status: .completed),
            makeTask("Animals", part: 2, of: 2, status: .completed),
            makeTask("Home", part: 1, of: 4, status: .completed),
            makeTask("Home", part: 2, of: 4, status: .downloading),
        ]

        let categories = DatasetTransferSummary.categories(manifest, tasks: tasks, datasetCompleted: false)

        XCTAssertEqual(categories.map(\.name), ["Animals", "Home", "Seasons"])
        XCTAssertEqual(categories.map(\.done), [2, 1, 0])
        XCTAssertEqual(categories.map(\.state), [.complete, .partial, .none])
        XCTAssertEqual(categories[1].fraction, 0.25, accuracy: 1e-9)
    }

    func test_categories_completedDatasetWithoutTasks_countsAsDone() {
        let manifest = [CategoryManifest(name: "Animals", partCount: 2, estimatedTotalSize: nil)]

        let categories = DatasetTransferSummary.categories(manifest, tasks: [], datasetCompleted: true)

        XCTAssertEqual(categories.first?.done, 2)
        XCTAssertEqual(categories.first?.state, .complete)
    }

    func test_categoryDisplayName_replacesUnderscores() {
        let category = DatasetTransferSummary.CategoryProgress(name: "Days_and_Time", done: 0, total: 3)

        XCTAssertEqual(category.displayName, "Days and Time")
    }
}
