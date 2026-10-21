import XCTest
import SwiftData
@testable import SignLanguageTranslate

@MainActor
final class TrainingWorkerLifecycleTests: XCTestCase {
    func test_resumeContinuesSameWorkerAndBatchPosition() async throws {
        let worker = TrainingWorkerLifecycle()
        var starts = 0
        var steps: [Int] = []
        XCTAssertTrue(worker.start {
            starts += 1
            for step in 0..<3 {
                guard await worker.waitUntilRunnable() else { return }
                steps.append(step)
                worker.pause()
            }
        })
        defer { worker.stop() }
        try await wait { worker.isParked }
        XCTAssertEqual(steps, [0])
        XCTAssertTrue(worker.resume())
        XCTAssertFalse(worker.resume())
        try await wait { steps.count == 2 && worker.isParked }
        XCTAssertEqual(steps, [0, 1])
        XCTAssertTrue(worker.resume())
        try await wait { !worker.hasWorker }
        XCTAssertEqual(steps, [0, 1, 2])
        XCTAssertEqual(starts, 1)
    }

    func test_duplicateStartCannotReplacePausedWorker() async throws {
        let worker = TrainingWorkerLifecycle()
        var replacements = 0
        worker.start {
            worker.pause()
            _ = await worker.waitUntilRunnable()
        }
        defer { worker.stop() }
        try await wait { worker.isParked }

        XCTAssertFalse(worker.start { replacements += 1 })
        XCTAssertEqual(replacements, 0)
        XCTAssertTrue(worker.resume())
        try await wait { !worker.hasWorker }
    }

    func test_stopWhilePausedWakesWorkerWithoutProcessingAnotherBatch() async throws {
        let worker = TrainingWorkerLifecycle()
        var updates = 0
        var gateResult: Bool?
        worker.start {
            worker.pause()
            let runnable = await worker.waitUntilRunnable()
            gateResult = runnable
            if runnable { updates += 1 }
        }
        defer { worker.stop() }
        try await wait { worker.isParked }
        XCTAssertTrue(worker.stop())
        XCTAssertFalse(worker.resume())
        try await wait { !worker.hasWorker }
        XCTAssertEqual(gateResult, false)
        XCTAssertEqual(updates, 0)
    }

    func test_idleAndCompletedWorkerCannotBeResumed() async throws {
        let worker = TrainingWorkerLifecycle()
        XCTAssertFalse(worker.pause())
        XCTAssertFalse(worker.resume())
        XCTAssertFalse(worker.stop())
        worker.start { }
        try await wait { !worker.hasWorker }
        XCTAssertFalse(worker.resume())
        XCTAssertFalse(worker.isPaused)
        XCTAssertFalse(worker.isStopping)
    }

    func test_finishedWorkerReleasesOwnershipForNextRun() async throws {
        let worker = TrainingWorkerLifecycle()
        var runs = 0
        worker.start { runs += 1 }
        try await wait { !worker.hasWorker }
        XCTAssertTrue(worker.start { runs += 1 })
        try await wait { !worker.hasWorker }
        XCTAssertEqual(runs, 2)
    }

    func test_completionNotificationObservesReleasedOwnership() async throws {
        let worker = TrainingWorkerLifecycle()
        var wasReleased: Bool?
        var completions = 0
        worker.start(onCompletion: {
            wasReleased = !worker.hasWorker
            completions += 1
        }) { }
        try await wait { completions == 1 }
        XCTAssertEqual(wasReleased, true)
        XCTAssertFalse(worker.hasWorker)
    }

    func test_checkpointAcknowledgementRequiresParkedBoundary() async throws {
        let worker = TrainingWorkerLifecycle()
        var gateReached = false
        worker.start {
            try? await Task.sleep(for: .milliseconds(100))
            gateReached = true
            _ = await worker.waitUntilRunnable()
        }
        defer { worker.stop() }
        worker.pause()
        let early = await worker.waitUntilPaused(timeout: .milliseconds(15))
        XCTAssertFalse(early)
        XCTAssertFalse(gateReached)
        let parked = await worker.waitUntilPaused(timeout: .seconds(2))
        XCTAssertTrue(parked)
        XCTAssertTrue(gateReached)
        worker.stop()
        try await wait { !worker.hasWorker }
    }

    func test_stopInvalidatesPendingCheckpointAcknowledgement() async throws {
        let worker = TrainingWorkerLifecycle()
        worker.start { _ = await worker.waitUntilRunnable() }
        worker.pause()
        worker.stop()
        let acknowledged = await worker.waitUntilPaused()
        XCTAssertFalse(acknowledged)
        try await wait { !worker.hasWorker }
    }

    func test_managerResumePreservesEpochBatchAndMetrics() async throws {
        let worker = TrainingWorkerLifecycle()
        let manager = TrainingSessionManager(config: .default, workerLifecycle: worker)
        manager.currentEpoch = 10
        manager.currentBatch = 3436
        manager.config.batchSize = 3
        manager.metrics = [TrainingMetrics(epoch: 10, batchIndex: 3436, trainingLoss: 0.9)]
        manager.state = .training
        var starts = 0
        worker.start {
            starts += 1
            manager.pauseTraining()
            if await worker.waitUntilRunnable() { manager.currentBatch += 1 }
        }
        defer { worker.stop() }
        try await wait { worker.isParked }
        manager.resumeTraining()
        manager.resumeTraining()
        XCTAssertEqual(manager.currentEpoch, 10)
        XCTAssertEqual(manager.currentBatch, 3436)
        XCTAssertEqual(manager.metrics.count, 1)
        XCTAssertEqual(manager.config.batchSize, 3)
        try await wait { !worker.hasWorker }
        XCTAssertEqual(manager.currentBatch, 3437)
        XCTAssertEqual(starts, 1)
        XCTAssertFalse(manager.logs.contains { $0.contains("Fetching training data") })
    }

    func test_startFromPausedUsesLiveResumeWithoutRefetchingData() async throws {
        let worker = TrainingWorkerLifecycle()
        let manager = TrainingSessionManager(config: .default, workerLifecycle: worker)
        let container = try TestContainerFactory.makeContainer()
        manager.currentEpoch = 10
        manager.currentBatch = 3436
        manager.state = .training
        var starts = 0
        worker.start {
            starts += 1
            manager.pauseTraining()
            _ = await worker.waitUntilRunnable()
        }
        defer { worker.stop() }
        try await wait { worker.isParked }

        manager.startTraining(datasetPath: FileManager.default.temporaryDirectory,
                              modelContext: container.mainContext, targetDatasetName: "Other dataset")
        manager.startTraining(datasetPath: FileManager.default.temporaryDirectory,
                              modelContext: container.mainContext, targetDatasetName: "Another dataset")
        try await wait { !worker.hasWorker }
        XCTAssertEqual(starts, 1)
        XCTAssertEqual(manager.currentEpoch, 10)
        XCTAssertEqual(manager.currentBatch, 3436)
        XCTAssertNil(manager.currentRunId)
        XCTAssertFalse(manager.logs.contains { $0.contains("Fetching training data") })
    }

    func test_prepareCannotReinitializeAnActiveWorker() async throws {
        let worker = TrainingWorkerLifecycle()
        let manager = TrainingSessionManager(config: .default, workerLifecycle: worker)
        worker.start { worker.pause(); _ = await worker.waitUntilRunnable() }
        defer { worker.stop() }
        try await wait { worker.isParked }
        manager.state = .paused
        manager.currentEpoch = 10
        await manager.prepare()
        XCTAssertEqual(manager.state, .paused)
        XCTAssertEqual(manager.currentEpoch, 10)
        XCTAssertFalse(manager.logs.contains { $0.contains("Initializing model") })
        worker.stop()
        try await wait { !worker.hasWorker }
    }

    func test_foregroundObserverIsRegisteredOnceAndHonorsManualPause() async throws {
        let worker = TrainingWorkerLifecycle()
        let center = NotificationCenter()
        let manager = TrainingSessionManager(config: .default, workerLifecycle: worker, notificationCenter: center)
        manager.state = .training
        worker.start { manager.pauseTraining(); _ = await worker.waitUntilRunnable() }
        defer { worker.stop() }
        try await wait { worker.isParked }
        manager.installBackgroundObservers()
        manager.installBackgroundObservers()
        manager.installBackgroundObservers()
        let name = Notification.Name.trainingResumeInBackground
        await Task.detached { center.post(name: name, object: nil) }.value
        try await wait { manager.logs.contains { $0.contains("waiting for explicit Resume") } }
        XCTAssertEqual(manager.logs.filter { $0.contains("Attempting to resume training") }.count, 1)
        XCTAssertTrue(worker.isPaused)
        XCTAssertEqual(manager.state, .paused)
        worker.stop()
        try await wait { !worker.hasWorker }
    }

    func test_managerWithoutLiveWorkerDoesNotPretendToResume() async throws {
        let manager = TrainingSessionManager(config: .default)
        manager.state = .paused
        manager.resumeTraining()
        XCTAssertEqual(manager.state, .paused)
        XCTAssertTrue(manager.logs.contains { $0.contains("No paused live worker") })
    }

    func test_backgroundPauseAndForegroundResumeUseExistingWorker() async throws {
        let worker = TrainingWorkerLifecycle()
        let center = NotificationCenter()
        let manager = TrainingSessionManager(config: .default, workerLifecycle: worker, notificationCenter: center)
        manager.state = .training
        var starts = 0
        var finished = false
        worker.start {
            starts += 1
            try? await Task.sleep(for: .milliseconds(100))
            if await worker.waitUntilRunnable() { finished = true }
        }
        defer { worker.stop() }
        manager.installBackgroundObservers()
        center.post(name: .trainingShouldSaveAndStop, object: nil)
        try await wait { manager.logs.contains { $0.contains("Background save callback finished") } }
        XCTAssertTrue(worker.isParked)
        XCTAssertEqual(manager.state, .paused)
        center.post(name: .trainingResumeInBackground, object: nil)
        try await wait { !worker.hasWorker }
        XCTAssertEqual(starts, 1)
        XCTAssertTrue(finished)
        XCTAssertEqual(manager.state, .training)
        // No model/run was supplied: this verifies control flow without writing
        // or claiming a real checkpoint or executing MLX on Simulator.
    }

    func test_backgroundSaveDoesNotOverrideAnExistingUserPause() async throws {
        let worker = TrainingWorkerLifecycle()
        let center = NotificationCenter()
        let manager = TrainingSessionManager(config: .default, workerLifecycle: worker, notificationCenter: center)
        manager.state = .training
        worker.start { manager.pauseTraining(); _ = await worker.waitUntilRunnable() }
        defer { worker.stop() }
        try await wait { worker.isParked }
        manager.installBackgroundObservers()
        center.post(name: .trainingShouldSaveAndStop, object: nil)
        try await wait { manager.logs.contains { $0.contains("Background save callback finished") } }
        center.post(name: .trainingResumeInBackground, object: nil)
        try await wait { manager.logs.contains { $0.contains("waiting for explicit Resume") } }
        XCTAssertTrue(worker.isPaused)
        XCTAssertEqual(manager.state, .paused)
        worker.stop()
        try await wait { !worker.hasWorker }
    }

    private func wait(_ condition: @MainActor () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while !condition() {
            guard clock.now < deadline else { return XCTFail("Timed out waiting for a lifecycle transition") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
