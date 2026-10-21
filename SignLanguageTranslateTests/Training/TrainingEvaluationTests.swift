import XCTest
import SwiftData
import MLX
import MLXNN
@testable import SignLanguageTranslate

@MainActor
final class TrainingEvaluationTests: XCTestCase {
    func test_wordTargetIgnoresCategoryAndRelationshipOrder() throws {
        let sample = VideoSample(localPath: "clip.mov", datasetName: "Fixture")
        let category = Label(name: "Animals", type: .category)
        category.embedding = vector(at: 0)
        let word = Label(name: "Dog", type: .word)
        word.embedding = vector(at: 1)
        sample.labels = [category, word]
        let first = try TrainingWordTarget.resolve(sample, requiresEmbedding: true)
        sample.labels.reverse()
        let second = try TrainingWordTarget.resolve(sample, requiresEmbedding: true)
        XCTAssertEqual(first.name, "Dog")
        XCTAssertEqual(first.embedding, word.embedding)
        XCTAssertEqual(second.embedding, first.embedding)
    }

    func test_missingOrAmbiguousWordLabelsAreRejected() {
        let sample = VideoSample(localPath: "clip.mov", datasetName: "Fixture")
        sample.labels = [Label(name: "Animals", type: .category)]
        XCTAssertThrowsError(try TrainingWordTarget.resolve(sample, requiresEmbedding: false))
        sample.labels = [Label(name: "Dog", type: .word), Label(name: "Cat", type: .word)]
        XCTAssertThrowsError(try TrainingWordTarget.resolve(sample, requiresEmbedding: false))
    }

    func test_missingBadOrZeroWordEmbeddingsAreRejected() {
        let sample = VideoSample(localPath: "clip.mov", datasetName: "Fixture")
        let word = Label(name: "Dog", type: .word)
        sample.labels = [word]
        for embedding: [Float]? in [nil, [], Array(repeating: 0, count: 384), Array(repeating: 1, count: 383), Array(repeating: .nan, count: 384)] {
            word.embedding = embedding
            XCTAssertThrowsError(try TrainingWordTarget.resolve(sample, requiresEmbedding: true))
        }
    }

    func test_classificationWordDoesNotRequireEmbedding() throws {
        let sample = VideoSample(localPath: "clip.mov", datasetName: "Fixture")
        sample.labels = [Label(name: "Dog", type: .word)]
        let target = try TrainingWordTarget.resolve(sample, requiresEmbedding: false)
        XCTAssertEqual(target.name, "Dog")
        XCTAssertTrue(target.embedding.isEmpty)
    }

    func test_vocabularyIsUniqueSortedAndRejectsConflictingVectors() throws {
        let targets = [TrainingWordTarget(name: "Dog", embedding: vector(at: 1)), TrainingWordTarget(name: "Cat", embedding: vector(at: 0))]
        let vocabulary = try TrainingVocabulary(targets: targets + [targets[0]])
        XCTAssertEqual(vocabulary.words, ["Cat", "Dog"])
        XCTAssertEqual(vocabulary.indices["Dog"], 1)
        XCTAssertThrowsError(try TrainingVocabulary(targets: targets + [TrainingWordTarget(name: "Dog", embedding: vector(at: 3))]))
    }

    func test_recognitionUsesFullVocabularyInsteadOfBatchPositions() throws {
        let vocabulary = try TrainingVocabulary(targets: (0..<8).map { TrainingWordTarget(name: "Word\($0)", embedding: []) })
        let scores: [Float] = [7, 6, 5, 4, 8, 3, 2, 1, 8, 7, 6, 5, 4, 3, 2, 1]
        let counts = try vocabulary.recognition(scores: scores, targets: [0, 7])
        XCTAssertEqual(counts.top1, 0)
        XCTAssertEqual(counts.top5, 1)
    }

    func test_duplicateWordsInBatchHaveSameCorrectWordIndex() throws {
        let vocabulary = try TrainingVocabulary(targets: [TrainingWordTarget(name: "Cat", embedding: []), TrainingWordTarget(name: "Dog", embedding: [])])
        let counts = try vocabulary.recognition(scores: [0, 1, 0, 1], targets: [1, 1])
        XCTAssertEqual(counts.top1, 2)
        XCTAssertEqual(counts.top5, 2)
    }

    func test_tiesAreDeterministicAndInvalidScoresAreRejected() throws {
        let vocabulary = try TrainingVocabulary(targets: [TrainingWordTarget(name: "Cat", embedding: []), TrainingWordTarget(name: "Dog", embedding: [])])
        XCTAssertEqual(try vocabulary.recognition(scores: [1, 1], targets: [0]).top1, 1)
        XCTAssertEqual(try vocabulary.recognition(scores: [1, 1], targets: [1]).top1, 0)
        XCTAssertThrowsError(try vocabulary.recognition(scores: [.nan, 1], targets: [0]))
        XCTAssertThrowsError(try vocabulary.recognition(scores: [1], targets: [0]))
        XCTAssertThrowsError(try vocabulary.recognition(scores: [1, 1], targets: [2]))
    }

    func test_validationTotalsWeightFinalPartialBatchByExamples() throws {
        var totals = ValidationTotals()
        try totals.add(loss: 0.5, similarity: 0.5, samples: 8, top1: 8, top5: 8)
        try totals.add(loss: 2, similarity: 0.25, samples: 1, top1: 0, top5: 1)
        let result = try totals.result()
        XCTAssertEqual(result.sampleCount, 9)
        XCTAssertEqual(result.loss, 6 / 9, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(result.cosineSimilarity), 4.25 / 9, accuracy: 1e-6)
        XCTAssertEqual(result.top1, 8 / 9, accuracy: 1e-6)
        XCTAssertEqual(result.top5, 1)
    }

    func test_emptyOrNonFiniteValidationCannotProduceSuccessfulScore() {
        var totals = ValidationTotals()
        XCTAssertThrowsError(try totals.result())
        XCTAssertThrowsError(try totals.add(loss: .nan, similarity: nil, samples: 1, top1: 0, top5: 0))
        XCTAssertThrowsError(try totals.add(loss: 1, similarity: nil, samples: 0, top1: 0, top5: 0))
        XCTAssertThrowsError(try totals.add(loss: 1, similarity: nil, samples: 1, top1: 2, top5: 2))
    }

    func test_epochOnlyCadenceAvoidsEveryTenBatchValidation() {
        XCTAssertEqual((1...1000).filter { TrainingEvaluationPolicy.validatesAfterBatch(step: $0, interval: 0) }.count, 0)
        XCTAssertEqual((1...1000).filter { TrainingEvaluationPolicy.validatesAfterBatch(step: $0, interval: 100) }.count, 10)
        XCTAssertFalse(TrainingEvaluationPolicy.validatesAfterBatch(step: 0, interval: 0))
    }

    func test_oldMetricJSONRemainsDecodableWithoutCallingCosineWordAccuracy() throws {
        let data = try JSONSerialization.data(withJSONObject: ["id": UUID().uuidString, "epoch": 8, "batchIndex": 2, "trainingLoss": 0.8, "accuracy": 0.326, "timestamp": 0])
        let decoded = try JSONDecoder().decode(TrainingMetrics.self, from: data)
        XCTAssertEqual(try XCTUnwrap(decoded.accuracy), 0.326, accuracy: 1e-6)
        XCTAssertNil(decoded.validationAccuracy)
        XCTAssertNil(decoded.evaluationVersion)
        let current = TrainingMetrics(epoch: 9, batchIndex: 1, trainingLoss: 1, cosineSimilarity: 0.4, validationAccuracy: 0.2, validationTop5Accuracy: 0.7, evaluationVersion: 2)
        let roundTrip = try JSONDecoder().decode(TrainingMetrics.self, from: JSONEncoder().encode(current))
        XCTAssertEqual(roundTrip.cosineSimilarity, 0.4)
        XCTAssertEqual(roundTrip.validationAccuracy, 0.2)
        XCTAssertNil(roundTrip.accuracy)
    }

    func test_oldCheckpointSpecificationStillDecodes() throws {
        let config = try CheckpointCompatibility.effectiveConfig(training: .default, numClasses: 0)
        let original = CheckpointModelSpecification(config: config, classNames: [])
        let restored = try JSONDecoder().decode(CheckpointModelSpecification.self, from: JSONEncoder().encode(original))
        XCTAssertNil(restored.targetContract)
        XCTAssertEqual(try restored.validatedConfig(), config)
    }

    func test_validationKeepsTrainingAndValidationMetricsSeparate() {
        let manager = TrainingSessionManager(config: .default)
        manager.metrics = [TrainingMetrics(epoch: 1, batchIndex: 1, trainingLoss: 0.8, accuracy: 0.75, cosineSimilarity: 0.326, evaluationVersion: 2)]
        manager.reportValidationMetric(ValidationResult(loss: 1.5, cosineSimilarity: 0.4, top1: 0.2, top5: 0.8, sampleCount: 10), step: 1, epoch: 1)
        XCTAssertEqual(manager.metrics.count, 1)
        XCTAssertEqual(manager.metrics[0].accuracy, 0.75)
        XCTAssertEqual(manager.metrics[0].cosineSimilarity, 0.326)
        XCTAssertEqual(manager.metrics[0].validationCosineSimilarity, 0.4)
        XCTAssertEqual(manager.metrics[0].validationAccuracy, 0.2)
        XCTAssertEqual(manager.metrics[0].validationTop5Accuracy, 0.8)
        XCTAssertEqual(manager.metrics[0].validationSampleCount, 10)
    }

    func test_evaluationDisablesDropoutAndRestoresMixedModesOnDevice() async throws {
        try requireDevice()
        let wrapper = try model()
        wrapper.train(true)
        wrapper.trainableLayers[0].train(false)
        let previous = modes(wrapper)
        let x = MLXArray((0..<(60 * 180)).map { Float($0 % 17) / 17 }, [1, 60, 180])
        let values = await ModelEvaluationMode.withEvaluation(wrapper) {
            XCTAssertTrue(wrapper.namedModules().allSatisfy { !$0.1.training })
            return (wrapper(x).asArray(Float.self), wrapper(x).asArray(Float.self))
        }
        XCTAssertEqual(values.0, values.1)
        XCTAssertEqual(modes(wrapper), previous)
    }

    func test_evaluationRestoresModesWhenOperationThrowsOnDevice() async throws {
        try requireDevice()
        let wrapper = try model()
        let previous = modes(wrapper)
        do {
            try await ModelEvaluationMode.withEvaluation(wrapper) {
                throw TrainingEvaluationError.invalid("Fixture failure")
            }
            XCTFail("Expected failure")
        } catch { }
        XCTAssertEqual(modes(wrapper), previous)
    }

    func test_stopWhileEvaluationIsPausedRestoresModesOnDevice() async throws {
        try requireDevice()
        let wrapper = try model()
        let previous = modes(wrapper)
        let worker = TrainingWorkerLifecycle()
        worker.start {
            await ModelEvaluationMode.withEvaluation(wrapper) {
                worker.pause()
                _ = await worker.waitUntilRunnable()
            }
        }
        try await wait { worker.isParked }
        XCTAssertTrue(wrapper.namedModules().allSatisfy { !$0.1.training })
        worker.stop()
        try await wait { !worker.hasWorker }
        XCTAssertEqual(modes(wrapper), previous)
    }

    func test_realValidationCountsExamplesAndRestoresModesOnDevice() async throws {
        try requireDevice()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("validation-fixture-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("frames.json")
        try JSONEncoder().encode([FrameFeatures(timestamp: 0, body: [UnifiedKeypoint(id: "nose", x: 0.5, y: 0.5, z: nil, confidence: 1)], leftHand: nil, rightHand: nil, sourceModel: "Fixture")]).write(to: file)
        var config = TrainingConfig.default
        config.batchSize = 2
        config.hiddenDim = 8
        config.numHeads = 2
        config.numLayers = 1
        let wrapper = try model()
        let previous = modes(wrapper)
        let container = try TestContainerFactory.makeContainer()
        let pipeline = TrainingDataPipeline(modelContext: ModelContext(container))
        let vocabulary = try TrainingVocabulary(targets: [TrainingWordTarget(name: "Cat", embedding: vector(at: 0)), TrainingWordTarget(name: "Dog", embedding: vector(at: 1))])
        let samples = (0..<3).map { i in TrainingDataPipeline.SampleInfo(id: UUID(), featurePath: file, embedding: vector(at: i % 2), labelIndex: i % 2, split: "validation") }
        let worker = TrainingWorkerLifecycle()
        let manager = TrainingSessionManager(config: config, workerLifecycle: worker)
        manager.state = .training
        var result: ValidationResult?
        worker.start { result = await manager.runValidation(pipeline: pipeline, samples: samples, wrapper: wrapper, config: config, vocabulary: vocabulary) }
        try await wait { !worker.hasWorker }
        let value = try XCTUnwrap(result)
        XCTAssertEqual(value.sampleCount, 3)
        XCTAssertTrue(value.loss.isFinite)
        XCTAssertEqual(value.top5, 1)
        XCTAssertEqual(modes(wrapper), previous)
        var emptyResult: ValidationResult?
        worker.start { emptyResult = await manager.runValidation(pipeline: pipeline, samples: [], wrapper: wrapper, config: config, vocabulary: vocabulary) }
        try await wait { !worker.hasWorker }
        XCTAssertNil(emptyResult)
        XCTAssertEqual(manager.state, .failed)
        XCTAssertEqual(modes(wrapper), previous)
    }

    private func vector(at index: Int) -> [Float] {
        var vector = Array(repeating: Float(0), count: 384)
        vector[index] = 1
        return vector
    }

    private func model() throws -> SignLanguageModuleWrapper {
        var config = TrainingConfig.default
        config.hiddenDim = 8
        config.numHeads = 2
        config.numLayers = 1
        config.dropout = 0.5
        return SignLanguageModuleWrapper(model: SignLanguageModel(config: try CheckpointCompatibility.effectiveConfig(training: config, numClasses: 0)))
    }

    private func modes(_ wrapper: SignLanguageModuleWrapper) -> [String: Bool] {
        Dictionary(uniqueKeysWithValues: wrapper.namedModules().map { ($0.0, $0.1.training) })
    }

    private func requireDevice() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("MLX evaluation/mode checks require a physical device.")
        #endif
    }

    private func wait(_ condition: @MainActor () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(10))
        while !condition() {
            guard clock.now < deadline else { throw TrainingEvaluationError.invalid("Timed out waiting for the evaluation worker.") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
