import XCTest
import SwiftData
@testable import SignLanguageTranslate

@MainActor
final class TrainingWorkerLifecycleTests: XCTestCase {
    func test_checkpointPreparationHandsOffInIdleAndStartsExactlyOnce() async throws {
        let worker = TrainingWorkerLifecycle()
        let manager = TrainingSessionManager(config: .default, workerLifecycle: worker)
        var starts = 0
        var loadedEpoch: Int?
        try await manager.prepareCheckpointResume(load: {
            XCTAssertEqual(manager.state, .preparing)
            XCTAssertTrue(manager.isPreparingCheckpoint)
            return 8
        }, start: { epoch in
            XCTAssertEqual(manager.state, .idle, "The real startTraining guard only accepts Idle")
            XCTAssertFalse(manager.isPreparingCheckpoint)
            loadedEpoch = epoch
            manager.state = .training
            worker.start { starts += 1 }
        })
        try await wait { !worker.hasWorker }
        XCTAssertEqual(loadedEpoch, 8)
        XCTAssertEqual(starts, 1)
    }

    func test_checkpointLoadingFailureReleasesPreparationForRetry() async throws {
        let manager = TrainingSessionManager(config: .default)
        do {
            try await manager.prepareCheckpointResume(load: { () async throws -> Int in
                throw NSError(domain: "CheckpointFixture", code: 1)
            }, start: { _ in XCTFail("A failed load must not start") })
            XCTFail("Expected loading error")
        } catch { }
        XCTAssertEqual(manager.state, .failed)
        XCTAssertEqual(manager.workPhase, .failed)
        XCTAssertFalse(manager.isPreparingCheckpoint)
        var retried = false
        try await manager.prepareCheckpointResume(load: { 8 }, start: { _ in retried = true })
        XCTAssertTrue(retried)
        XCTAssertEqual(manager.state, .idle)
    }

    func test_stopDuringCheckpointLoadDiscardsLateResult() async throws {
        let manager = TrainingSessionManager(config: .default)
        var pending: CheckedContinuation<Int, Never>?
        var starts = 0
        let preparation = Task {
            try await manager.prepareCheckpointResume(load: {
                await withCheckedContinuation { pending = $0 }
            }, start: { _ in starts += 1 })
        }
        try await wait { pending != nil }
        manager.stopTraining()
        XCTAssertEqual(manager.state, .idle)
        XCTAssertFalse(manager.isPreparingCheckpoint)
        try XCTUnwrap(pending).resume(returning: 8)
        do {
            try await preparation.value
            XCTFail("Stopped preparation must be cancelled")
        } catch is CancellationError { }
        XCTAssertEqual(starts, 0)
        XCTAssertFalse(manager.hasLiveWorker)
        XCTAssertEqual(manager.state, .idle)
    }

    func test_duplicateCheckpointPreparationCannotLoadOrReplaceExistingOperation() async throws {
        let manager = TrainingSessionManager(config: .default)
        var pending: CheckedContinuation<Int, Never>?
        let preparation = Task {
            try await manager.prepareCheckpointResume(load: {
                await withCheckedContinuation { pending = $0 }
            }, start: { _ in XCTFail("Stopped operation must not start") })
        }
        try await wait { pending != nil }
        do {
            try await manager.prepareCheckpointResume(load: {
                XCTFail("Duplicate must be rejected before loading")
                return 9
            }, start: { _ in XCTFail("Duplicate must not start") })
            XCTFail("Expected duplicate rejection")
        } catch { }
        XCTAssertTrue(manager.isPreparingCheckpoint)
        XCTAssertEqual(manager.state, .preparing)
        let container = try TestContainerFactory.makeContainer()
        manager.startTraining(datasetPath: FileManager.default.temporaryDirectory, modelContext: container.mainContext)
        await manager.prepare()
        XCTAssertFalse(manager.logs.contains { $0.contains("Fetching training data") || $0.contains("Initializing model") })
        XCTAssertEqual(manager.state, .preparing)
        manager.stopTraining()
        try XCTUnwrap(pending).resume(returning: 8)
        do { try await preparation.value } catch is CancellationError { }
    }

    func test_checkpointPreparationRejectsLiveWorkerWithoutChangingItsState() async throws {
        let worker = TrainingWorkerLifecycle()
        let manager = TrainingSessionManager(config: .default, workerLifecycle: worker)
        manager.state = .training
        worker.start { manager.pauseTraining(); _ = await worker.waitUntilRunnable() }
        defer { worker.stop() }
        try await wait { worker.isParked }
        do {
            try await manager.prepareCheckpointResume(load: {
                XCTFail("Must not load over a live worker")
                return 8
            }, start: { _ in XCTFail("Must not start") })
            XCTFail("Expected live-worker rejection")
        } catch { }
        XCTAssertEqual(manager.state, .paused)
        XCTAssertTrue(worker.isParked)
        worker.stop()
        try await wait { !worker.hasWorker }
    }

    func test_cancelledCheckpointTaskDoesNotHandOffToTraining() async throws {
        let manager = TrainingSessionManager(config: .default)
        var pending: CheckedContinuation<Int, Never>?
        let preparation = Task {
            try await manager.prepareCheckpointResume(load: {
                await withCheckedContinuation { pending = $0 }
            }, start: { _ in XCTFail("Cancelled task must not start") })
        }
        try await wait { pending != nil }
        preparation.cancel()
        try XCTUnwrap(pending).resume(returning: 8)
        do { try await preparation.value } catch is CancellationError { }
        XCTAssertEqual(manager.state, .idle)
        XCTAssertFalse(manager.isPreparingCheckpoint)
    }

    func test_stopClearsPreparingWhenNoWorkerWasEverStarted() {
        let manager = TrainingSessionManager(config: .default)
        manager.state = .preparing
        manager.stopTraining()
        XCTAssertEqual(manager.state, .idle)
        XCTAssertEqual(manager.workPhase, .idle)
        XCTAssertFalse(manager.hasLiveWorker)
    }

    func test_stoppedLoadCannotClearNewerCheckpointPreparation() async throws {
        let manager = TrainingSessionManager(config: .default)
        var oldPending: CheckedContinuation<Int, Never>?
        var newPending: CheckedContinuation<Int, Never>?
        let oldPreparation = Task {
            try await manager.prepareCheckpointResume(load: {
                await withCheckedContinuation { oldPending = $0 }
            }, start: { _ in XCTFail("Stopped load must not start") })
        }
        try await wait { oldPending != nil }
        manager.stopTraining()
        var loadedEpoch: Int?
        let newPreparation = Task {
            try await manager.prepareCheckpointResume(load: {
                await withCheckedContinuation { newPending = $0 }
            }, start: { loadedEpoch = $0 })
        }
        try await wait { newPending != nil }
        try XCTUnwrap(oldPending).resume(returning: 8)
        do { try await oldPreparation.value } catch is CancellationError { }
        XCTAssertTrue(manager.isPreparingCheckpoint)
        XCTAssertEqual(manager.state, .preparing)
        try XCTUnwrap(newPending).resume(returning: 9)
        try await newPreparation.value
        XCTAssertEqual(loadedEpoch, 9)
        XCTAssertFalse(manager.isPreparingCheckpoint)
        XCTAssertEqual(manager.state, .idle)
    }

    func test_resumeFromRunWithoutCheckpointFailsAndExitsPreparing() async throws {
        let manager = TrainingSessionManager(config: .default)
        let container = try TestContainerFactory.makeContainer()
        let run = TrainingRun(name: "checkpoint-regression-\(UUID())", config: .default)
        container.mainContext.insert(run)
        let folder = manager.getRunCheckpointDirectory(runName: run.name)
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            try await manager.resumeFromRun(run, modelContext: container.mainContext, targetDatasetName: "Fixture")
            XCTFail("Expected missing-checkpoint error")
        } catch { }
        XCTAssertEqual(manager.state, .failed)
        XCTAssertEqual(manager.workPhase, .failed)
        XCTAssertFalse(manager.isPreparingCheckpoint)
        XCTAssertFalse(manager.hasLiveWorker)
        XCTAssertNil(manager.currentRunId)
    }

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
