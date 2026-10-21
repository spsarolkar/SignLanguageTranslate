import XCTest
import SwiftData
@testable import SignLanguageTranslate

@MainActor
final class TrainingThermalProtectionTests: XCTestCase {
    @MainActor private final class Fixture {
        var level: ProcessInfo.ThermalState = .nominal
        let center = NotificationCenter()
        let worker = TrainingWorkerLifecycle()
        lazy var protection = TrainingThermalProtection(notificationCenter: center, cooldown: .milliseconds(150), thermalState: { [unowned self] in self.level })
        lazy var manager = TrainingSessionManager(config: .default, workerLifecycle: worker, notificationCenter: center, thermalProtection: protection)

        func change(_ level: ProcessInfo.ThermalState) {
            self.level = level
            center.post(name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        }

        func startWorker() {
            manager.state = .training
            manager.currentEpoch = 19
            manager.currentBatch = 354
            manager.metrics = [TrainingMetrics(epoch: 19, batchIndex: 354, trainingLoss: 0.6)]
            worker.start {
                if await self.worker.waitUntilRunnable() { self.manager.currentBatch += 1 }
            }
            manager.startThermalMonitoring()
        }

        func cleanUp() { protection.stop(); worker.stop() }
    }

    func test_alreadyHotPausesBeforeFirstBatchAndResumesSameWorker() async throws {
        let fixture = Fixture()
        fixture.level = .serious
        fixture.startWorker()
        defer { fixture.cleanUp() }
        try await wait { fixture.worker.isParked }
        XCTAssertTrue(fixture.manager.isThermallyPaused)
        XCTAssertEqual(fixture.manager.state, .paused)
        XCTAssertEqual(fixture.manager.currentBatch, 354)
        fixture.change(.fair)
        try await wait { !fixture.worker.hasWorker }
        XCTAssertEqual(fixture.manager.currentBatch, 355)
        XCTAssertEqual(fixture.manager.currentEpoch, 19)
        XCTAssertEqual(fixture.manager.metrics.count, 1)
        XCTAssertFalse(fixture.manager.isThermallyPaused)
        XCTAssertEqual(fixture.manager.logs.filter { $0.contains("Resumed existing worker") }.count, 1)
        XCTAssertFalse(fixture.manager.logs.contains { $0.contains("Fetching training data") })
    }

    func test_cooldownWaitsAndNormalWarmChangesDoNotRestartIt() async throws {
        let fixture = Fixture()
        fixture.level = .critical
        var events: [Bool] = []
        fixture.protection.start { events.append($0) }
        defer { fixture.cleanUp() }
        fixture.change(.fair)
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(events, [true])
        fixture.change(.nominal)
        try await wait { events == [true, false] }
        XCTAssertFalse(fixture.protection.isCooling)
    }

    func test_reheatingCancelsCooldownAndRequiresNewCoolPeriod() async throws {
        let fixture = Fixture()
        fixture.level = .serious
        var events: [Bool] = []
        fixture.protection.start { events.append($0) }
        defer { fixture.cleanUp() }
        fixture.change(.fair)
        try await Task.sleep(for: .milliseconds(60))
        fixture.change(.critical)
        try await Task.sleep(for: .milliseconds(180))
        XCTAssertEqual(events, [true])
        fixture.change(.nominal)
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(events, [true])
        try await wait { events == [true, false] }
    }

    func test_cooldownRechecksCurrentStateEvenWithoutNotification() async throws {
        let fixture = Fixture()
        fixture.level = .critical
        var events: [Bool] = []
        fixture.protection.start { events.append($0) }
        defer { fixture.cleanUp() }
        fixture.change(.fair)
        try await Task.sleep(for: .milliseconds(40))
        fixture.level = .serious
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(events, [true])
        XCTAssertTrue(fixture.protection.isCooling)
    }

    func test_repeatedStartAndHotNotificationsDoNotDuplicatePause() async throws {
        let fixture = Fixture()
        var events: [Bool] = []
        fixture.protection.start { events.append($0) }
        fixture.protection.start { _ in XCTFail("Duplicate observer") }
        defer { fixture.cleanUp() }
        fixture.change(.serious)
        try await wait { events == [true] }
        fixture.change(.critical)
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(events, [true])
    }

    func test_stopCancelsCooldownAndRemovesObserver() async throws {
        let fixture = Fixture()
        fixture.level = .critical
        var events: [Bool] = []
        fixture.protection.start { events.append($0) }
        fixture.change(.fair)
        try await Task.sleep(for: .milliseconds(40))
        fixture.protection.stop()
        fixture.change(.serious)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(events, [true])
        XCTAssertFalse(fixture.protection.isCooling)
    }

    func test_oldQueuedNotificationCannotAffectRestartedMonitor() async throws {
        let fixture = Fixture()
        var oldEvents: [Bool] = []
        var newEvents: [Bool] = []
        fixture.protection.start { oldEvents.append($0) }
        fixture.change(.critical) // Delivery hops asynchronously onto MainActor.
        fixture.protection.stop()
        fixture.level = .nominal
        fixture.protection.start { newEvents.append($0) }
        defer { fixture.cleanUp() }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(oldEvents.isEmpty)
        XCTAssertTrue(newEvents.isEmpty)
        fixture.change(.serious)
        try await wait { newEvents == [true] }
    }

    func test_oldCooldownCannotReleaseNewRunPause() async throws {
        let fixture = Fixture()
        fixture.level = .critical
        var events: [Bool] = []
        fixture.protection.start { events.append($0) }
        fixture.change(.fair)
        try await Task.sleep(for: .milliseconds(40))
        fixture.protection.stop()
        fixture.level = .serious
        fixture.protection.start { events.append($0) }
        defer { fixture.cleanUp() }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(events, [true, true])
        XCTAssertTrue(fixture.protection.isCooling)
    }

    func test_controllerReleaseIsSafeBeforeStartAndWithPendingCooldown() {
        weak var released: TrainingThermalProtection?
        do {
            let controller = TrainingThermalProtection(notificationCenter: NotificationCenter(), thermalState: { .nominal })
            released = controller
        }
        XCTAssertNil(released)

        let fixture = Fixture()
        do {
            let controller = TrainingThermalProtection(notificationCenter: fixture.center, thermalState: { [unowned fixture] in fixture.level })
            released = controller
            fixture.level = .serious
            controller.start { _ in }
            fixture.level = .fair
            controller.refresh() // Leave a weakly captured cooldown task pending.
        }
        XCTAssertNil(released)
    }

    func test_manualPauseDuringCoolingTakesOwnershipUntilExplicitResume() async throws {
        let fixture = Fixture()
        fixture.level = .serious
        fixture.startWorker()
        defer { fixture.cleanUp() }
        try await wait { fixture.worker.isParked }
        fixture.manager.pauseTraining()
        fixture.change(.nominal)
        try await wait { !fixture.manager.isThermallyPaused }
        XCTAssertTrue(fixture.worker.isPaused)
        XCTAssertTrue(fixture.manager.isManuallyPaused)
        XCTAssertEqual(fixture.manager.currentBatch, 354)
        XCTAssertTrue(fixture.manager.activityDescription.contains("Paused by you"))
        fixture.manager.resumeTraining()
        try await wait { !fixture.worker.hasWorker }
        XCTAssertEqual(fixture.manager.currentBatch, 355)
    }

    func test_heatDuringActiveWorkPausesAtNextBoundaryWithoutRestarting() async throws {
        let fixture = Fixture()
        fixture.manager.state = .training
        var starts = 0
        var steps = 0
        fixture.worker.start {
            starts += 1
            steps += 1 // Simulate one already-running operation.
            fixture.change(.serious)
            try? await Task.sleep(for: .milliseconds(100))
            if await fixture.worker.waitUntilRunnable() { steps += 1 }
        }
        fixture.manager.startThermalMonitoring()
        defer { fixture.cleanUp() }
        try await wait { fixture.worker.isParked }
        XCTAssertEqual(steps, 1)
        fixture.change(.nominal)
        try await wait { !fixture.worker.hasWorker }
        XCTAssertEqual(steps, 2)
        XCTAssertEqual(starts, 1)
    }

    func test_existingManualPauseSurvivesHeatingAndCooling() async throws {
        let fixture = Fixture()
        fixture.manager.state = .training
        fixture.worker.start { _ = await fixture.worker.waitUntilRunnable() }
        fixture.manager.pauseTraining()
        fixture.manager.startThermalMonitoring()
        defer { fixture.cleanUp() }
        try await wait { fixture.worker.isParked }
        fixture.change(.critical)
        try await wait { fixture.manager.isThermallyPaused }
        fixture.change(.fair)
        try await wait { !fixture.manager.isThermallyPaused }
        XCTAssertTrue(fixture.manager.isManuallyPaused)
        XCTAssertTrue(fixture.worker.isPaused)
        fixture.manager.resumeTraining()
        try await wait { !fixture.worker.hasWorker }
    }

    func test_explicitResumeCannotBypassHeatProtection() async throws {
        let fixture = Fixture()
        fixture.level = .critical
        fixture.startWorker()
        defer { fixture.cleanUp() }
        try await wait { fixture.worker.isParked }
        fixture.manager.pauseTraining()
        fixture.manager.resumeTraining()
        XCTAssertFalse(fixture.manager.isManuallyPaused)
        XCTAssertTrue(fixture.worker.isPaused)
        XCTAssertTrue(fixture.manager.isThermallyPaused)
        XCTAssertEqual(fixture.manager.currentBatch, 354)
        fixture.change(.fair)
        try await wait { !fixture.worker.hasWorker }
        XCTAssertEqual(fixture.manager.currentBatch, 355)
    }

    func test_stopWhileCoolingCannotRestartWhenDeviceCools() async throws {
        let fixture = Fixture()
        fixture.level = .serious
        fixture.startWorker()
        defer { fixture.cleanUp() }
        try await wait { fixture.worker.isParked }
        fixture.change(.fair)
        fixture.manager.stopTraining()
        try await wait { !fixture.worker.hasWorker }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(fixture.manager.currentBatch, 354)
        XCTAssertEqual(fixture.manager.state, .completing)
        XCTAssertFalse(fixture.manager.isThermallyPaused)
        XCTAssertFalse(fixture.manager.logs.contains { $0.contains("Resumed existing worker") })
    }

    func test_backgroundSavePauseSurvivesCooldownUntilForeground() async throws {
        let fixture = Fixture()
        fixture.level = .serious
        fixture.startWorker()
        defer { fixture.cleanUp() }
        try await wait { fixture.worker.isParked }
        fixture.manager.installBackgroundObservers()
        fixture.center.post(name: .trainingShouldSaveAndStop, object: nil)
        try await wait { fixture.manager.logs.contains { $0.contains("Background save callback finished") } }
        fixture.change(.nominal)
        try await wait { !fixture.manager.isThermallyPaused }
        XCTAssertTrue(fixture.worker.isPaused)
        fixture.center.post(name: .trainingResumeInBackground, object: nil)
        try await wait { !fixture.worker.hasWorker }
        XCTAssertEqual(fixture.manager.currentBatch, 355)
    }

    func test_foregroundDoesNotBypassThermalOrManualPause() async throws {
        let fixture = Fixture()
        fixture.level = .serious
        fixture.startWorker()
        defer { fixture.cleanUp() }
        try await wait { fixture.worker.isParked }
        fixture.manager.installBackgroundObservers()
        fixture.manager.pauseTraining()
        fixture.center.post(name: .trainingShouldSaveAndStop, object: nil)
        try await wait { fixture.manager.logs.contains { $0.contains("Background save callback finished") } }
        fixture.center.post(name: .trainingResumeInBackground, object: nil)
        try await wait { fixture.manager.logs.contains { $0.contains("Attempting to resume") } }
        XCTAssertTrue(fixture.worker.isPaused)
        fixture.change(.fair)
        try await wait { !fixture.manager.isThermallyPaused }
        XCTAssertTrue(fixture.worker.isPaused)
        XCTAssertTrue(fixture.manager.isManuallyPaused)
    }

    func test_dataProducerGateDoesNotClaimGPUWorkerIsParked() async throws {
        let fixture = Fixture()
        fixture.manager.state = .training
        fixture.worker.start { try? await Task.sleep(for: .milliseconds(200)) }
        fixture.manager.pauseTraining()
        let dataTask = Task { await fixture.manager.waitForDataWork() }
        defer { fixture.cleanUp(); dataTask.cancel() }
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertFalse(fixture.worker.isParked)
        let acknowledged = await fixture.worker.waitUntilPaused(timeout: .milliseconds(20))
        XCTAssertFalse(acknowledged)
        fixture.manager.stopTraining()
        let allowed = await dataTask.value
        XCTAssertFalse(allowed)
        try await wait { !fixture.worker.hasWorker }
    }

    func test_pipelineGateCanStopBeforeLoadingOrAllocatingTensors() async throws {
        let container = try TestContainerFactory.makeContainer()
        let pipeline = TrainingDataPipeline(modelContext: ModelContext(container))
        let sample = TrainingDataPipeline.SampleInfo(id: UUID(), featurePath: URL(fileURLWithPath: "/missing-thermal-fixture.json"), embedding: [], labelIndex: 0, split: nil)
        let stream = await pipeline.batchStream(samples: [sample], batchSize: 1, waitForWork: { false })
        var batches = 0
        for await _ in stream { batches += 1 }
        XCTAssertEqual(batches, 0)
    }

    private func wait(_ condition: @MainActor () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while !condition() {
            guard clock.now < deadline else { return XCTFail("Timed out waiting for thermal transition") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
