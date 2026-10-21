import Foundation

/// Value-only description of the implemented forward pass. No tensors or GPU work.
nonisolated struct TransformerArchitectureDiagram: Sendable {
    enum Source: String, Sendable {
        case live = "Instantiated model"
        case preview = "Configuration preview"
        case recorded = "Saved model specification"
        case legacy = "Reconstructed from recorded run settings"
    }

    enum StageID: String, Sendable { case input, projection, position, encoder, norm, pooling, output, normalization }
    struct Stage: Identifiable, Sendable {
        let id: StageID
        let title: String
        let shape: String
        let detail: String
    }

    let config: SignLanguageModelConfig
    let source: Source
    var sequenceShape: String { "[B, \(TrainingDataPipeline.maxFrames), \(config.modelDim)]" }
    var outputShape: String {
        let width = config.outputMode == .embedding ? String(config.outputDim) : (config.numClasses > 0 ? String(config.numClasses) : "C")
        return "[B, \(width)]"
    }
    var mlpWidth: Int { config.modelDim * 4 }

    init(config: SignLanguageModelConfig, source: Source) throws {
        try CheckpointCompatibility.validate(config)
        self.config = config
        self.source = source
    }

    private init(previewConfig: SignLanguageModelConfig) {
        config = previewConfig
        source = .preview
    }

    static func preview(training: TrainingConfig) throws -> Self {
        // Resolve the same structural fields/head correction as training. The
        // classifier's dataset vocabulary is unknown before Start: use symbolic
        // C in the diagram, never allocate a placeholder classifier/model.
        var structuralSettings = training
        structuralSettings.lossFunction = .contrastive
        var config = try CheckpointCompatibility.effectiveConfig(training: structuralSettings, numClasses: 0)
        config.outputMode = training.lossFunction == .crossEntropy ? .classification : .embedding
        return Self(previewConfig: config)
    }

    static func saved(recordedTraining: Data, specification: Data?) throws -> Self {
        if let specification {
            let spec = try JSONDecoder().decode(CheckpointModelSpecification.self, from: specification)
            return try Self(config: spec.validatedConfig(), source: .recorded)
        }
        let recovered = try CheckpointCompatibility.legacyConfig(recordedTraining: recordedTraining, classNames: [])
        return try Self(config: recovered, source: .legacy)
    }

    static func readSaved(recordedTraining: Data, specificationURL: URL) throws -> Self {
        guard FileManager.default.fileExists(atPath: specificationURL.path) else {
            return try saved(recordedTraining: recordedTraining, specification: nil)
        }
        let handle = try FileHandle(forReadingFrom: specificationURL)
        defer { try? handle.close() }
        let limit = 256 * 1024
        guard let data = try handle.read(upToCount: limit + 1), data.count <= limit else {
            throw CheckpointCompatibility.Error.incompatible("Saved architecture metadata is too large to display.")
        }
        return try saved(recordedTraining: recordedTraining, specification: data)
    }

    var stages: [Stage] {
        let pooledShape = "[B, \(config.modelDim)]"
        let pooling: (String, String)
        switch config.poolingType {
        case .attention: pooling = ("Learned attention pooling", "A learned query attends to projected keys and values across all frames.")
        case .mean: pooling = ("Mean pooling", "Average the encoded frame vectors along the time axis.")
        case .cls: pooling = ("First-timestep pooling", "Select the first encoded frame. This implementation does not insert a separate CLS token.")
        }
        return [
            Stage(id: .input, title: "Pose sequence", shape: "[B, \(TrainingDataPipeline.maxFrames), \(config.inputDim)]", detail: "Body 18 + left hand 21 + right hand 21 landmarks; 3 values per landmark. B is the actual batch size."),
            Stage(id: .projection, title: "Input projection + LayerNorm", shape: sequenceShape, detail: "Linear \(config.inputDim) → \(config.modelDim), applied to each frame, then LayerNorm."),
            Stage(id: .position, title: "Position + input dropout", shape: sequenceShape, detail: "Add sinusoidal positional encoding, then dropout p = \(config.dropout)."),
            Stage(id: .encoder, title: "Encoder stack × \(config.numLayers)", shape: sequenceShape, detail: "\(config.numHeads) attention heads · \(config.modelDim / config.numHeads) values per head. Each block has its own parameters; sequence length is preserved."),
            Stage(id: .norm, title: "Final LayerNorm", shape: sequenceShape, detail: "Normalize each encoded frame before reducing the time axis."),
            Stage(id: .pooling, title: pooling.0, shape: pooledShape, detail: pooling.1),
            Stage(id: .output, title: config.outputMode == .embedding ? "Embedding projection" : "Class projection", shape: outputShape, detail: config.outputMode == .embedding ? "Linear \(config.modelDim) → \(config.outputDim). One embedding vector per clip." : (config.numClasses > 0 ? "Linear \(config.modelDim) → \(config.numClasses). One score per word class." : "Linear from model width to the word classes. C is resolved from the dataset when training starts.")),
            Stage(id: .normalization, title: "L2 normalization", shape: outputShape, detail: config.outputMode == .embedding ? "Normalize the clip embedding. Contrastive/cosine loss and word-vocabulary ranking are outside this network." : "The current forward pass also normalizes class scores. Cross-entropy is applied outside the network; there is no softmax layer here.")
        ]
    }

    var attentionBranch: [String] {
        ["LayerNorm", "Multi-head self-attention · \(config.numHeads) heads · no causal mask", "Dropout · p = \(config.dropout)"] + scaleStep
    }
    var mlpBranch: [String] {
        ["LayerNorm", "Linear \(config.modelDim) → \(mlpWidth)", "GELU", "Dropout · p = \(config.dropout)", "Linear \(mlpWidth) → \(config.modelDim)", "Dropout · p = \(config.dropout)"] + scaleStep
    }
    private var scaleStep: [String] { config.useLayerScale ? ["LayerScale · per-channel scaling · initial \(config.layerScaleInit)"] : [] }
}
