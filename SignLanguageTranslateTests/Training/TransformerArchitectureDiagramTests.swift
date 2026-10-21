import XCTest
@testable import SignLanguageTranslate

@MainActor
final class TransformerArchitectureDiagramTests: XCTestCase {
    func test_previewUsesEffectiveHeadsAndEmbeddingWidth() throws {
        var training = TrainingConfig.default
        training.hiddenDim = 256
        training.numHeads = 6
        training.numLayers = 4
        let diagram = try TransformerArchitectureDiagram.preview(training: training)
        XCTAssertEqual(diagram.source, .preview)
        XCTAssertEqual(diagram.config.numHeads, 4)
        XCTAssertEqual(diagram.mlpWidth, 1024)
        XCTAssertEqual(diagram.outputShape, "[B, 384]")
        XCTAssertEqual(diagram.stages.first?.shape, "[B, 60, 180]")
        XCTAssertEqual(diagram.stages.map(\.id), [.input, .projection, .position, .encoder, .norm, .pooling, .output, .normalization])
    }

    func test_liveDiagramKeepsActualModelConfigInsteadOfPreviewDefaults() throws {
        var config = SignLanguageModelConfig.small
        config.poolingType = .attention
        config.outputMode = .embedding
        let diagram = try TransformerArchitectureDiagram(config: config, source: .live)
        XCTAssertEqual(diagram.config, config)
        XCTAssertEqual(diagram.sequenceShape, "[B, 60, 192]")
        XCTAssertEqual(diagram.outputShape, "[B, 384]")
        XCTAssertEqual(diagram.mlpWidth, 768)
    }

    func test_classificationPreviewHasSymbolicClassCount() throws {
        var training = TrainingConfig.default
        training.lossFunction = .crossEntropy
        let diagram = try TransformerArchitectureDiagram.preview(training: training)
        XCTAssertEqual(diagram.config.outputMode, .classification)
        XCTAssertEqual(diagram.outputShape, "[B, C]")
        XCTAssertEqual(diagram.stages[6].title, "Class projection")
        XCTAssertEqual(diagram.stages.last?.id, .normalization)
    }

    func test_classificationActualCountAndNormalizationFollowForwardPass() throws {
        var config = SignLanguageModelConfig.default
        config.numClasses = 57
        let diagram = try TransformerArchitectureDiagram(config: config, source: .live)
        XCTAssertEqual(diagram.outputShape, "[B, 57]")
        XCTAssertEqual(diagram.stages.last?.shape, "[B, 57]")
        XCTAssertEqual(diagram.stages.last?.title, "L2 normalization")
    }

    func test_poolingVariantsFollowActualReduction() throws {
        var config = SignLanguageModelConfig.default
        for (pooling, title) in [(SignLanguageModelConfig.PoolingType.mean, "Mean pooling"), (.attention, "Learned attention pooling"), (.cls, "First-timestep pooling")] {
            config.poolingType = pooling
            let diagram = try TransformerArchitectureDiagram(config: config, source: .live)
            XCTAssertEqual(diagram.stages[5].title, title)
            XCTAssertEqual(diagram.stages[5].shape, "[B, 384]")
        }
    }

    func test_layerScaleIsConditionalAndMLPExpandsFourfold() throws {
        var config = SignLanguageModelConfig.small
        config.useLayerScale = false
        var diagram = try TransformerArchitectureDiagram(config: config, source: .live)
        XCTAssertEqual(diagram.mlpWidth, config.modelDim * 4)
        XCTAssertFalse(diagram.attentionBranch.contains { $0.contains("LayerScale") })
        XCTAssertFalse(diagram.mlpBranch.contains { $0.contains("LayerScale") })
        config.useLayerScale = true
        diagram = try TransformerArchitectureDiagram(config: config, source: .live)
        XCTAssertTrue(diagram.attentionBranch.last?.contains("LayerScale") == true)
        XCTAssertTrue(diagram.mlpBranch.last?.contains("LayerScale") == true)
    }

    func test_savedSpecificationWinsOverContradictoryTrainingSettings() throws {
        let actual = SignLanguageModelConfig.small
        let spec = CheckpointModelSpecification(config: actual, classNames: (0..<actual.numClasses).map { "Word\($0)" })
        let diagram = try TransformerArchitectureDiagram.saved(recordedTraining: JSONEncoder().encode(TrainingConfig.default), specification: JSONEncoder().encode(spec))
        XCTAssertEqual(diagram.source, .recorded)
        XCTAssertEqual(diagram.config, actual)
    }

    func test_missingSpecificationRequiresCompleteLegacySettings() throws {
        var recorded = TrainingConfig.default
        recorded.hiddenDim = 256
        recorded.numHeads = 6
        let diagram = try TransformerArchitectureDiagram.saved(recordedTraining: JSONEncoder().encode(recorded), specification: nil)
        XCTAssertEqual(diagram.source, .legacy)
        XCTAssertEqual(diagram.config.numHeads, 4)
        XCTAssertEqual(diagram.config.poolingType, .attention)
        XCTAssertThrowsError(try TransformerArchitectureDiagram.saved(recordedTraining: Data("{}".utf8), specification: nil))
    }

    func test_invalidSavedMetadataCannotSilentlyFallBackToPreview() throws {
        let recorded = try JSONEncoder().encode(TrainingConfig.default)
        XCTAssertThrowsError(try TransformerArchitectureDiagram.saved(recordedTraining: recorded, specification: Data("{}".utf8)))
        let spec = CheckpointModelSpecification(config: .default, classNames: [])
        XCTAssertThrowsError(try TransformerArchitectureDiagram.saved(recordedTraining: recorded, specification: JSONEncoder().encode(spec)))
    }

    func test_oversizedSpecificationIsRejectedBeforeDecoding() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("diagram-spec-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: path) }
        try Data(repeating: 0, count: 256 * 1024 + 1).write(to: path)
        XCTAssertThrowsError(try TransformerArchitectureDiagram.readSaved(recordedTraining: JSONEncoder().encode(TrainingConfig.default), specificationURL: path))
    }

    func test_invalidStructureAndBiLSTMCannotMasqueradeAsTransformer() {
        var training = TrainingConfig.default
        training.useLegacyModel = true
        XCTAssertThrowsError(try TransformerArchitectureDiagram.preview(training: training))
        var config = SignLanguageModelConfig.default
        config.numHeads = 5
        XCTAssertThrowsError(try TransformerArchitectureDiagram(config: config, source: .live))
    }
}
