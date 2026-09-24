import XCTest
@testable import SignLanguageTranslate

/// Pausing a dataset must survive the detail view's 1 s sync tick, which
/// re-derives `downloadStatus` from the download tasks.
final class DatasetPauseSyncTests: XCTestCase {

    private func makeTask(part: Int, status: DownloadTaskStatus) -> DownloadTask {
        DownloadTask(
            url: URL(string: "https://example.com/Animals_\(part)of2.zip")!,
            category: "Animals",
            partNumber: part,
            totalParts: 2,
            datasetName: "INCLUDE",
            status: status
        )
    }

    func test_pause_thenSyncTicks_statusStaysPaused() async {
        let queue = DownloadQueueActor()
        await queue.enqueue(makeTask(part: 1, status: .downloading))
        await queue.enqueue(makeTask(part: 2, status: .pending))
        let dataset = Dataset(name: "INCLUDE", type: .include)
        dataset.startDownload()

        // What Pause All now does: pause the tasks, then the dataset.
        await queue.pauseAll()
        dataset.pauseDownload()

        let tasks = await queue.getAllTasks()
        dataset.syncStatus(with: tasks)
        dataset.syncStatus(with: tasks)

        XCTAssertEqual(dataset.downloadStatus, .paused)
    }

    /// The old behavior: only the dataset status changed, so the next tick
    /// saw a downloading task and flipped it back.
    func test_pausingOnlyDatasetStatus_isUndoneBySyncTick() async {
        let queue = DownloadQueueActor()
        await queue.enqueue(makeTask(part: 1, status: .downloading))
        let dataset = Dataset(name: "INCLUDE", type: .include)
        dataset.startDownload()

        dataset.pauseDownload()
        dataset.syncStatus(with: await queue.getAllTasks())

        XCTAssertEqual(dataset.downloadStatus, .downloading)
    }

    func test_syncStatus_afterResume_isDownloading() {
        let dataset = Dataset(name: "INCLUDE", type: .include)
        dataset.pauseDownload()

        dataset.syncStatus(with: [makeTask(part: 1, status: .downloading), makeTask(part: 2, status: .paused)])

        XCTAssertEqual(dataset.downloadStatus, .downloading)
    }

    func test_syncStatus_noTasks_leavesStatusUnchanged() {
        let dataset = Dataset(name: "INCLUDE", type: .include)
        dataset.pauseDownload()

        dataset.syncStatus(with: [])

        XCTAssertEqual(dataset.downloadStatus, .paused)
    }
}
