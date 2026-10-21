import XCTest
import SwiftData
import MLX
import MLXNN
@testable import SignLanguageTranslate

@MainActor
final class CheckpointCompatibilityTests: XCTestCase {
    func test_effectiveSpecificationMatchesHistoricalInitializer() throws {
        var training = TrainingConfig.default
        training.hiddenDim = 256
        training.numHeads = 6
        let config = try CheckpointCompatibility.effectiveConfig(training: training, numClasses: 0)
        XCTAssertEqual(config.numHeads, 4)
        XCTAssertEqual(config.poolingType, .attention)
        XCTAssertEqual(config.outputMode, .embedding)
        XCTAssertEqual(config.outputDim, 384)
    }

    func test_invalidHeadCountAndUnsupportedFamilyAreRejected() throws {
        var training = TrainingConfig.default
        training.numHeads = 0
        XCTAssertThrowsError(try CheckpointCompatibility.effectiveConfig(training: training, numClasses: 0))
        training.useLegacyModel = true
        XCTAssertThrowsError(try CheckpointCompatibility.effectiveConfig(training: training, numClasses: 0))
        XCTAssertThrowsError(try CheckpointModelSpecification(config: nil, classNames: [], family: "bilstm").validatedConfig())
    }

    func test_legacyRecoveryRequiresRecordedArchitectureFields() throws {
        XCTAssertThrowsError(try CheckpointCompatibility.legacyConfig(recordedTraining: Data("{}".utf8), classNames: []))
        let training = smallTraining()
        let config = try CheckpointCompatibility.legacyConfig(recordedTraining: JSONEncoder().encode(training), classNames: [])
        XCTAssertEqual(config.modelDim, 8)
        XCTAssertEqual(config.poolingType, .attention)
    }

    func test_classificationRequiresUniquePersistedClassOrder() throws {
        var training = smallTraining()
        training.lossFunction = .crossEntropy
        let config = try CheckpointCompatibility.effectiveConfig(training: training, numClasses: 2)
        XCTAssertThrowsError(try CheckpointModelSpecification(config: config, classNames: []).validatedConfig())
        XCTAssertThrowsError(try CheckpointModelSpecification(config: config, classNames: ["Dog", "Dog"]).validatedConfig())
        _ = try CheckpointModelSpecification(config: config, classNames: ["Cat", "Dog"]).validatedConfig()
    }

    func test_parameterValidationRejectsMissingExtraAndWrongShapes() throws {
        let expected = ["weight": [2, 3], "bias": [2]]
        XCTAssertNoThrow(try CheckpointCompatibility.validateShapes(expected: expected, actual: expected))
        XCTAssertThrowsError(try CheckpointCompatibility.validateShapes(expected: expected, actual: ["weight": [2, 3]]))
        XCTAssertThrowsError(try CheckpointCompatibility.validateShapes(expected: expected, actual: expected.merging(["extra": [1]]) { $1 }))
        XCTAssertThrowsError(try CheckpointCompatibility.validateShapes(expected: expected, actual: ["weight": [3, 2], "bias": [2]]))
    }

    func test_safetensorsHeaderRejectsTruncationAndOversizedHeader() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("weights.safetensors")
        try syntheticWeights().write(to: url)
        XCTAssertEqual(try CheckpointCompatibility.readShapes(at: url), ["weight": [2]])
        var bytes = try Data(contentsOf: url)
        bytes.removeLast()
        try bytes.write(to: url)
        XCTAssertThrowsError(try CheckpointCompatibility.readShapes(at: url))
        try Data(repeating: 255, count: 8).write(to: url)
        XCTAssertThrowsError(try CheckpointCompatibility.readShapes(at: url))
    }

    func test_weightsDigestDetectsChangedPayload() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("weights.safetensors")
        try syntheticWeights().write(to: url)
        let original = try CheckpointCompatibility.fingerprint(url)
        var changed = try Data(contentsOf: url)
        changed[changed.count - 1] = 1
        try changed.write(to: url)
        XCTAssertNotEqual(try CheckpointCompatibility.fingerprint(url), original)
    }

    func test_missingWeightsAndUnversionedConfigFailBeforeModelAllocation() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let config = try CheckpointCompatibility.effectiveConfig(training: smallTraining(), numClasses: 0)
        try JSONEncoder().encode(config).write(to: root.appendingPathComponent("config.json"))
        let metadata = root.appendingPathComponent("best_metadata.json")
        try flatMetadata().write(to: metadata)
        let persistence = ModelPersistence(modelsDirectory: root)
        do {
            _ = try await persistence.loadModel(from: metadata)
            XCTFail("Missing weights must fail")
        } catch ModelPersistence.PersistenceError.fileNotFound { }
        try syntheticWeights().write(to: root.appendingPathComponent("best.safetensors"))
        do {
            _ = try await persistence.loadModel(from: metadata)
            XCTFail("Unversioned recovery requires original run configuration")
        } catch CheckpointCompatibility.Error.incompatible { }
    }

    func test_configAuditDoesNotInventMissingFiles() throws {
        let manager = TrainingSessionManager(config: .default)
        let container = try TestContainerFactory.makeContainer()
        let run = TrainingRun(name: "missing-config-fixture-\(UUID())", config: .default)
        container.mainContext.insert(run)
        let folder = manager.getRunCheckpointDirectory(runName: run.name)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        manager.ensureConfigsAreSaved(modelContext: container.mainContext)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    func test_versionedMetadataWithoutDigestAndUnsupportedFamilyFailBeforeAllocation() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let config = try CheckpointCompatibility.effectiveConfig(training: smallTraining(), numClasses: 0)
        try JSONEncoder().encode(config).write(to: root.appendingPathComponent("config.json"))
        try syntheticWeights().write(to: root.appendingPathComponent("best.safetensors"))
        let metadata = root.appendingPathComponent("best_metadata.json")
        for family in ["transformer", "bilstm"] {
            var values = try XCTUnwrap(JSONSerialization.jsonObject(with: flatMetadata()) as? [String: Any])
            let specification = CheckpointModelSpecification(config: config, classNames: [], family: family)
            values["specification"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(specification))
            try JSONSerialization.data(withJSONObject: values).write(to: metadata)
            do {
                _ = try await ModelPersistence(modelsDirectory: root).loadModel(from: metadata)
                XCTFail("Unsupported/incomplete metadata must not allocate a model")
            } catch CheckpointCompatibility.Error.incompatible { }
        }
    }

    func test_embeddingAndClassificationRoundTripOnDevice() async throws {
        try requireDevice()
        for classification in [false, true] {
            let root = try folder()
            defer { try? FileManager.default.removeItem(at: root) }
            var training = smallTraining()
            training.lossFunction = classification ? .crossEntropy : .contrastive
            let classes = classification ? ["Cat", "Dog", "Tree"] : []
            let config = try CheckpointCompatibility.effectiveConfig(training: training, numClasses: classes.count)
            let model = SignLanguageModel(config: config)
            let wrapper = SignLanguageModuleWrapper(model: model)
            wrapper.train(false)
            let x = input()
            let before = wrapper(x).asArray(Float.self)
            let persistence = ModelPersistence(modelsDirectory: root)
            let url = try await persistence.saveModel(wrapper, config: config, epoch: 8, step: 20, loss: 0.5, classNames: classes)
            let (loaded, loadedConfig, metadata) = try await persistence.loadModel(from: url)
            let restored = SignLanguageModuleWrapper(model: loaded)
            restored.train(false)
            let after = restored(x).asArray(Float.self)
            XCTAssertEqual(loadedConfig, config)
            XCTAssertEqual(metadata.specification?.classNames, classes)
            XCTAssertEqual(before.count, classification ? 3 : 384)
            XCTAssertEqual(after.count, before.count)
            XCTAssertTrue(before.allSatisfy(\.isFinite))
            for (a, b) in zip(before, after) { XCTAssertEqual(a, b, accuracy: 1e-6) }
            let all = Dictionary(uniqueKeysWithValues: wrapper.parameters().flattened())
            let restoredParameters = Dictionary(uniqueKeysWithValues: restored.parameters().flattened())
            XCTAssertEqual(Set(all.keys), Set(restoredParameters.keys))
            for key in all.keys { XCTAssertEqual(all[key]?.asArray(Float.self), restoredParameters[key]?.asArray(Float.self)) }
            var wrong = config
            wrong.poolingType = .mean
            do {
                _ = try await persistence.saveModel(wrapper, config: wrong, epoch: 8, step: 20, loss: nil, name: "wrong")
                XCTFail("Must not persist a configuration that differs from the actual model")
            } catch ModelPersistence.PersistenceError.configMismatch { }
        }
    }

    func test_legacyRecoveryPreservesFilesAndRestoresActualArchitectureOnDevice() async throws {
        try requireDevice()
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        var training = smallTraining()
        training.numHeads = 3 // Historical initializer corrects to four for width eight.
        let actual = try CheckpointCompatibility.effectiveConfig(training: training, numClasses: 0)
        let wrapper = SignLanguageModuleWrapper(model: SignLanguageModel(config: actual))
        wrapper.train(false)
        let x = input()
        let before = wrapper(x).asArray(Float.self)
        var old = actual
        old.poolingType = .mean
        old.outputMode = .classification
        old.numClasses = 100
        old.numHeads = 3
        let configURL = root.appendingPathComponent("config.json")
        try JSONEncoder().encode(old).write(to: configURL)
        let weightsURL = root.appendingPathComponent("best.safetensors")
        try MLX.save(arrays: Dictionary(uniqueKeysWithValues: wrapper.parameters().flattened()), url: weightsURL)
        let metadataURL = root.appendingPathComponent("best_metadata.json")
        try flatMetadata().write(to: metadataURL)
        let original = try [configURL, weightsURL, metadataURL].map { try CheckpointCompatibility.fingerprint($0) }
        let persistence = ModelPersistence(modelsDirectory: root)
        let (loaded, config, checkpoint) = try await persistence.loadModel(from: metadataURL, legacyTrainingConfig: JSONEncoder().encode(training))
        XCTAssertEqual(config, actual)
        XCTAssertEqual(checkpoint.epoch, 8)
        XCTAssertEqual(checkpoint.modelVersion, "legacy-recovered-v1")
        let restored = SignLanguageModuleWrapper(model: loaded)
        restored.train(false)
        let after = restored(x).asArray(Float.self)
        for (a, b) in zip(before, after) { XCTAssertEqual(a, b, accuracy: 1e-6) }
        XCTAssertEqual(try [configURL, weightsURL, metadataURL].map { try CheckpointCompatibility.fingerprint($0) }, original)
    }

    func test_callbackOverwriteProducesVerifiedDigestAndMetadataOnDevice() async throws {
        try requireDevice()
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let config = try CheckpointCompatibility.effectiveConfig(training: smallTraining(), numClasses: 0)
        let wrapper = SignLanguageModuleWrapper(model: SignLanguageModel(config: config))
        try JSONEncoder().encode(config).write(to: root.appendingPathComponent("config.json"))
        try JSONEncoder().encode(CheckpointModelSpecification(config: config, classNames: [])).write(to: root.appendingPathComponent("model-specification.json"))
        let callback = ModelCheckpointCallback(checkpointDirectory: root)
        callback.onCheckpointSaved = { _, epoch, _ in try callback.saveModelWeights(wrapper.parameters(), epoch: epoch) }
        let run = TrainingRun(name: "Callback fixture", config: smallTraining())
        await callback.onTrainBegin(run: run)
        for epoch in 1...2 {
            _ = await callback.onEpochEnd(epoch: epoch, metrics: EpochMetrics(epoch: epoch, trainLoss: 1, valLoss: 1 / Float(epoch), epochDuration: 1), run: run)
        }
        let persistence = ModelPersistence(modelsDirectory: root)
        let metadata = root.appendingPathComponent("best_metadata.json")
        let (_, loadedConfig, checkpoint) = try await persistence.loadModel(from: metadata)
        XCTAssertEqual(checkpoint.epoch, 2)
        XCTAssertEqual(loadedConfig, config)
        let weights = root.appendingPathComponent("best.safetensors")
        var corrupted = try Data(contentsOf: weights)
        corrupted[corrupted.count - 1] ^= 1
        try corrupted.write(to: weights)
        do {
            _ = try await persistence.loadModel(from: metadata)
            XCTFail("Changed weights must not be paired with old metadata")
        } catch CheckpointCompatibility.Error.incompatible { }
    }

    private func smallTraining() -> TrainingConfig {
        var config = TrainingConfig.default
        config.hiddenDim = 8
        config.numLayers = 1
        config.numHeads = 2
        config.dropout = 0
        return config
    }

    private func input() -> MLXArray {
        MLXArray((0..<(60 * 180)).map { Float($0 % 17) / 17 }, [1, 60, 180])
    }

    private func requireDevice() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("MLX round-trip checks require a physical device.")
        #endif
    }

    private func folder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("checkpoint-fixture-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func flatMetadata() throws -> Data {
        try JSONSerialization.data(withJSONObject: ["epoch": 8, "value": 0.5, "timestamp": "2026-10-21T02:44:21Z"])
    }

    private func syntheticWeights() throws -> Data {
        let header = try JSONSerialization.data(withJSONObject: ["weight": ["dtype": "F32", "shape": [2], "data_offsets": [0, 8]]])
        var length = UInt64(header.count).littleEndian
        var data = withUnsafeBytes(of: &length) { Data($0) }
        data.append(header)
        data.append(Data(repeating: 0, count: 8))
        return data
    }
}
