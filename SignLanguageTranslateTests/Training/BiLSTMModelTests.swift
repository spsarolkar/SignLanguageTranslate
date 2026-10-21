import XCTest
import SwiftData
import MLX
import MLXNN
import MLXOptimizers
@testable import SignLanguageTranslate

@MainActor
final class BiLSTMModelTests: XCTestCase {
    private func training(loss: TrainingConfig.LossType = .contrastive) -> TrainingConfig {
        var config = TrainingConfig.default
        config.useLegacyModel = true
        config.bilstmVersion = 2
        config.hiddenDim = 32
        config.numLayers = 1
        config.dropout = 0
        config.lossFunction = loss
        return config
    }

    func test_oldTrainingConfigDecodesAsV1AndNewConfigRoundTripsAsV2() throws {
        let original = try JSONEncoder().encode(training())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        json.removeValue(forKey: "bilstmVersion")
        XCTAssertEqual(try JSONDecoder().decode(TrainingConfig.self, from: JSONSerialization.data(withJSONObject: json)).bilstmVersion, 1)
        XCTAssertEqual(try JSONDecoder().decode(TrainingConfig.self, from: original).bilstmVersion, 2)
    }

    func test_effectiveConfigMatchesRequestedRecurrentShapeAndOutputMode() throws {
        var selected = training()
        selected.hiddenDim = 96
        let config = try BiLSTMModelConfig.effective(training: selected, numClasses: 256)
        XCTAssertEqual(config.hiddenDim, 96)
        XCTAssertEqual(config.numLayers, 1)
        XCTAssertEqual(config.outputDim, 384)
        XCTAssertEqual(config.outputMode, .embedding)
        selected.lossFunction = .crossEntropy
        let classifier = try BiLSTMModelConfig.effective(training: selected, numClasses: 256)
        XCTAssertEqual(classifier.outputMode, .classification)
        XCTAssertEqual(classifier.numClasses, 256)
    }

    func test_invalidOrLegacySettingsCannotInstantiateV2() throws {
        var config = training()
        config.bilstmVersion = 1
        XCTAssertThrowsError(try BiLSTMModelConfig.effective(training: config, numClasses: 0))
        config.bilstmVersion = 2
        for width in [0, 16, 513] {
            config.hiddenDim = width
            XCTAssertThrowsError(try BiLSTMModelConfig.effective(training: config, numClasses: 0))
        }
        config.hiddenDim = 32
        config.numLayers = 3
        XCTAssertThrowsError(try BiLSTMModelConfig.effective(training: config, numClasses: 0))
        config.numLayers = 1
        config.dropout = .nan
        XCTAssertThrowsError(try BiLSTMModelConfig.effective(training: config, numClasses: 0))
    }

    func test_versionedSpecificationPreservesConfigAndClassifierOrder() throws {
        let config = try BiLSTMModelConfig.effective(training: training(loss: .crossEntropy), numClasses: 3)
        let spec = CheckpointModelSpecification(config: nil, classNames: ["A", "B", "C"], family: "bilstm-v2", bilstmConfig: config)
        let restored = try JSONDecoder().decode(CheckpointModelSpecification.self, from: JSONEncoder().encode(spec))
        XCTAssertEqual(try restored.validatedBiLSTMConfig(), config)
        XCTAssertEqual(restored.outputMode, .classification)
        XCTAssertThrowsError(try restored.validatedConfig())
        let wrong = CheckpointModelSpecification(config: nil, classNames: ["A"], family: "bilstm-v2", bilstmConfig: config)
        XCTAssertThrowsError(try wrong.validatedBiLSTMConfig())
        XCTAssertThrowsError(try CheckpointModelSpecification(config: nil, classNames: [], family: "bilstm").validatedBiLSTMConfig())
    }

    func test_metadataRejectsMissingDigestAndLegacyFamily() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("best_metadata.json")
        try Data("{\"epoch\":7}".utf8).write(to: url)
        XCTAssertThrowsError(try BiLSTMCheckpointStore.readMetadata(at: url))
        let spec = CheckpointModelSpecification(config: nil, classNames: [], family: "bilstm")
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(spec))
        try JSONSerialization.data(withJSONObject: ["epoch": 7, "weightsSHA256": String(repeating: "0", count: 64), "specification": encoded]).write(to: url)
        XCTAssertThrowsError(try BiLSTMCheckpointStore.readMetadata(at: url))
    }

    func test_v2CannotEnterTransformerFineTuningPath() {
        let manager = TrainingSessionManager(config: .default)
        manager.prepareFineTuning(run: TrainingRun(name: "BiLSTM v2 fixture", config: training()))
        XCTAssertNil(manager.continuationSourceRun)
        XCTAssertTrue(manager.logs.last?.contains("Fine-tune is not available") == true)
    }

    func test_v2EmbeddingIsFiniteNormalizedAndIndependentOfBatchCompanionsOnDevice() throws {
        try requireDevice()
        let model = try BiLSTMSignLanguageModel(config: BiLSTMModelConfig.effective(training: training(), numClasses: 3))
        let wrapper = SignLanguageModuleWrapper(model: model)
        wrapper.train(false)
        XCTAssertFalse(wrapper.namedModules().contains { $0.1 is BatchNorm })
        let x = inputs(batch: 3, time: 60)
        let together = wrapper(x).asArray(Float.self)
        let alone = wrapper(x[0..<1]).asArray(Float.self)
        XCTAssertEqual(together.count, 3 * 384)
        XCTAssertTrue(together.allSatisfy(\.isFinite))
        XCTAssertLessThan(zip(alone, together.prefix(384)).map { abs($0 - $1) }.max() ?? 1, 1e-5)
        for row in 0..<3 {
            let norm = together[(row * 384)..<((row + 1) * 384)].reduce(Float(0)) { $0 + $1 * $1 }
            XCTAssertEqual(norm, 1, accuracy: 1e-4)
        }
    }

    func test_classifierReturnsRawScoresAndSupportsPartialBatchOnDevice() throws {
        try requireDevice()
        let model = try BiLSTMSignLanguageModel(config: BiLSTMModelConfig.effective(training: training(loss: .crossEntropy), numClasses: 3))
        let wrapper = SignLanguageModuleWrapper(model: model)
        wrapper.train(false)
        try model.outputProjection.update(parameters: ModuleParameters.unflattened([
            "weight": MLXArray.zeros([3, 64]), "bias": MLXArray([Float(2), 0, -2])]), verify: .all)
        let scores = wrapper(inputs(batch: 1, time: 8))
        XCTAssertEqual(scores.shape, [1, 3])
        XCTAssertEqual(scores.asArray(Float.self), [2, 0, -2])
    }

    func test_auxiliaryOutputsUseOneForwardAndMatchScalarLossGradientOnDevice() throws {
        try requireDevice()
        let counted = CountingModel()
        let wrapper = SignLanguageModuleWrapper(model: counted)
        let config = training(loss: .cosine)
        let x = inputs(batch: 3, time: 8)
        let targets = embeddings(batch: 3)
        let standard = valueAndGrad(model: wrapper) { model, x, y in
            RecurrentTrainingStep.loss(predictions: model(x), targets: y, config: config)
        }
        let (referenceLoss, referenceGrads) = standard(wrapper, x, targets)
        MLX.eval(referenceLoss, referenceGrads)
        counted.calls = 0
        let single = RecurrentTrainingStep.gradient(model: wrapper, config: config)
        let (values, grads) = single(wrapper, [x, targets])
        MLX.eval(values, grads)
        XCTAssertEqual(counted.calls, 1)
        XCTAssertEqual(values.count, 2)
        XCTAssertEqual(values[0].item(Float.self), referenceLoss.item(Float.self), accuracy: 1e-6)
        let reference = Dictionary(uniqueKeysWithValues: referenceGrads.flattened())
        for (key, gradient) in grads.flattened() {
            let expected = try XCTUnwrap(reference[key])
            let delta = abs(gradient - expected).max().item(Float.self)
            XCTAssertLessThan(delta, 1e-6)
        }
        let norm = RecurrentTrainingStep.gradientNorm(grads).item(Float.self)
        // Accumulate the independent CPU reference in Double: summing tens of
        // thousands of small squares sequentially in Float loses precision.
        let expected = sqrt(grads.flattened().reduce(Double(0)) { result, pair in
            result + pair.1.asArray(Float.self).reduce(Double(0)) { $0 + Double($1) * Double($1) }
        })
        XCTAssertEqual(Double(norm), expected, accuracy: 1e-6)
    }

    func test_v2ProducesFiniteGradientsForBothDirectionsAndAttentionOnDevice() throws {
        try requireDevice()
        let config = training(loss: .crossEntropy)
        let model = try BiLSTMSignLanguageModel(config: BiLSTMModelConfig.effective(training: config, numClasses: 4))
        let wrapper = SignLanguageModuleWrapper(model: model)
        let gradient = RecurrentTrainingStep.gradient(model: wrapper, config: config)
        let (values, grads) = gradient(wrapper, [inputs(batch: 4, time: 8), MLXArray([Int32(0), 1, 2, 3])])
        MLX.eval(values, grads)
        let flattened = grads.flattened()
        XCTAssertEqual(Set(flattened.map(\.0)), Set(wrapper.trainableParameters().flattened().map(\.0)))
        XCTAssertTrue(flattened.allSatisfy { $0.1.asArray(Float.self).allSatisfy(\.isFinite) })
        for layer in [2, 3, 5] { // forward LSTM, backward LSTM, attention score
            let magnitude = flattened.filter { $0.0.hasPrefix("trainableLayers.\(layer).") }.reduce(Float(0)) { $0 + abs($1.1).sum().item(Float.self) }
            XCTAssertGreaterThan(magnitude, 0)
        }
    }

    func test_v2CanOverfitSmallDeterministicSequenceFixtureOnDevice() throws {
        try requireDevice()
        let config = training(loss: .crossEntropy)
        let model = try BiLSTMSignLanguageModel(config: BiLSTMModelConfig.effective(training: config, numClasses: 4))
        let wrapper = SignLanguageModuleWrapper(model: model)
        let optimizer = Adam(learningRate: 0.01)
        let gradient = RecurrentTrainingStep.gradient(model: wrapper, config: config)
        let x = inputs(batch: 4, time: 8)
        let y = MLXArray([Int32(0), 1, 2, 3])
        let initial = crossEntropy(logits: wrapper(x), targets: y, reduction: .mean).item(Float.self)
        for _ in 0..<50 {
            let (values, grads) = gradient(wrapper, [x, y])
            optimizer.update(model: wrapper, gradients: grads)
            MLX.eval(wrapper, optimizer, values)
        }
        wrapper.train(false)
        let output = wrapper(x)
        let final = crossEntropy(logits: output, targets: y, reduction: .mean).item(Float.self)
        XCTAssertTrue(final.isFinite)
        XCTAssertLessThan(final, initial * 0.25)
        XCTAssertEqual(output.argMax(axis: -1).asArray(Int32.self), [0, 1, 2, 3])
    }

    func test_contrastiveUpdateIsFiniteAtProductionSequenceShapeOnDevice() throws {
        try requireDevice()
        var config = training()
        config.hiddenDim = 96
        config.dropout = 0.1
        let model = try BiLSTMSignLanguageModel(config: BiLSTMModelConfig.effective(training: config, numClasses: 8))
        let wrapper = SignLanguageModuleWrapper(model: model)
        let optimizer = Adam(learningRate: 1e-4)
        let gradient = RecurrentTrainingStep.gradient(model: wrapper, config: config)
        let (values, grads) = gradient(wrapper, [inputs(batch: 8, time: 60), embeddings(batch: 8)])
        let norm = RecurrentTrainingStep.gradientNorm(grads)
        optimizer.update(model: wrapper, gradients: grads)
        MLX.eval(wrapper, optimizer, values, norm)
        XCTAssertEqual(values[1].shape, [8, 384])
        XCTAssertTrue(values[0].item(Float.self).isFinite)
        XCTAssertTrue(norm.item(Float.self).isFinite)
        XCTAssertTrue(wrapper.parameters().flattened().allSatisfy { $0.1.asArray(Float.self).allSatisfy(\.isFinite) })
    }

    func test_v2CheckpointRoundTripRejectsWrongShapeAndTamperingOnDevice() throws {
        try requireDevice()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = try BiLSTMModelConfig.effective(training: training(), numClasses: 3)
        let model = try BiLSTMSignLanguageModel(config: config)
        let wrapper = SignLanguageModuleWrapper(model: model)
        wrapper.train(false)
        let x = inputs(batch: 2, time: 8)
        let before = wrapper(x).asArray(Float.self)
        try saveCheckpoint(wrapper: wrapper, config: config, directory: directory)
        let weights = directory.appendingPathComponent("best.safetensors")
        let originalHash = try CheckpointCompatibility.fingerprint(weights)
        let metadata = directory.appendingPathComponent("best_metadata.json")
        let (restored, record) = try BiLSTMCheckpointStore.load(metadataURL: metadata)
        let loaded = SignLanguageModuleWrapper(model: restored)
        loaded.train(false)
        XCTAssertEqual(record.epoch, 7)
        XCTAssertLessThan(zip(before, loaded(x).asArray(Float.self)).map { abs($0 - $1) }.max() ?? 1, 1e-6)
        XCTAssertEqual(try CheckpointCompatibility.fingerprint(weights), originalHash)
        var wrong = config
        wrong.hiddenDim = 64
        try writeMetadata(config: wrong, directory: directory)
        XCTAssertThrowsError(try BiLSTMCheckpointStore.load(metadataURL: metadata))
        try writeMetadata(config: config, directory: directory)
        let handle = try FileHandle(forWritingTo: weights)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([0]))
        try handle.close()
        XCTAssertThrowsError(try BiLSTMCheckpointStore.load(metadataURL: metadata))
    }

    func test_publicV2ResumeKeepsSourceAndUsesRecordedConfigurationOnDevice() async throws {
        try requireDevice()
        let selected = training()
        let config = try BiLSTMModelConfig.effective(training: selected, numClasses: 3)
        let source = TrainingRun(name: "v2-resume-fixture-\(UUID())", config: selected)
        let manager = TrainingSessionManager(config: .default)
        let directory = manager.getRunCheckpointDirectory(runName: source.name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
            if let child = manager.currentRunCheckpointDirectory { try? FileManager.default.removeItem(at: child) }
        }
        let wrapper = SignLanguageModuleWrapper(model: try BiLSTMSignLanguageModel(config: config))
        try saveCheckpoint(wrapper: wrapper, config: config, directory: directory)
        let original = try CheckpointCompatibility.fingerprint(directory.appendingPathComponent("best.safetensors"))
        let container = try TestContainerFactory.makeContainer()
        container.mainContext.insert(source)
        try await manager.resumeFromRun(source, modelContext: container.mainContext, targetDatasetName: "No samples fixture")
        XCTAssertEqual(manager.currentEpoch, 7)
        XCTAssertEqual(manager.instantiatedBiLSTMConfig, config)
        XCTAssertFalse(manager.hasLiveWorker) // Empty isolated dataset; no training step.
        XCTAssertEqual(manager.state, .failed)
        XCTAssertEqual(source.config?.bilstmVersion, 2)
        XCTAssertNotEqual(manager.currentRunId, source.id)
        XCTAssertEqual(try CheckpointCompatibility.fingerprint(directory.appendingPathComponent("best.safetensors")), original)
    }

    private func inputs(batch: Int, time: Int) -> MLXArray {
        let values = (0..<(batch * time * 180)).map { index -> Float in
            let sample = index / (time * 180)
            let feature = index % 180
            let frame = (index / 180) % time
            return sin(Float((sample + 1) * (feature + 1)) * 0.11) + Float(frame) * 0.01
        }
        return MLXArray(values, [batch, time, 180])
    }

    private func embeddings(batch: Int) -> MLXArray {
        MLXArray((0..<(batch * 384)).map { Float($0 % 384 == $0 / 384 ? 1 : 0) }, [batch, 384])
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("bilstm-v2-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func saveCheckpoint(wrapper: SignLanguageModuleWrapper, config: BiLSTMModelConfig, directory: URL) throws {
        let callback = ModelCheckpointCallback(checkpointDirectory: directory)
        try callback.saveModelWeights(wrapper.parameters(), epoch: 7)
        try writeMetadata(config: config, directory: directory)
    }

    private func writeMetadata(config: BiLSTMModelConfig, directory: URL) throws {
        let names = config.outputMode == .classification ? (0..<config.numClasses).map { "Word\($0)" } : ["A", "B", "C"]
        let spec = CheckpointModelSpecification(config: nil, classNames: names, family: "bilstm-v2", bilstmConfig: config)
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(spec))
        let hash = try CheckpointCompatibility.fingerprint(directory.appendingPathComponent("best.safetensors"))
        try JSONSerialization.data(withJSONObject: ["epoch": 7, "value": 1.0, "weightsSHA256": hash, "specification": object]).write(to: directory.appendingPathComponent("best_metadata.json"))
    }

    private func requireDevice() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("MLX training requires physical GPU hardware")
        #endif
    }

    nonisolated private final class CountingModel: @unchecked Sendable, SignLanguageModelProtocol {
        var calls = 0
        let linear = Linear(180, 384)
        nonisolated deinit {}
        func callAsFunction(_ x: MLXArray) -> MLXArray { calls += 1; return linear(mean(x, axis: 1)) }
        nonisolated func modules() -> [Module] { [linear] }
    }
}
