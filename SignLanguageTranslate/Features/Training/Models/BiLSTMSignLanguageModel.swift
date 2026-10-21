import Foundation
import MLX
import MLXNN

nonisolated struct BiLSTMModelConfig: Codable, Sendable, Equatable {
    var version = 2
    var inputDim = 180
    var hiddenDim: Int
    var numLayers: Int
    var dropout: Float
    var outputDim = 384
    var numClasses: Int
    var outputMode: SignLanguageModelConfig.OutputMode

    static func effective(training: TrainingConfig, numClasses: Int) throws -> Self {
        guard training.useLegacyModel, training.bilstmVersion == 2 else {
            throw CheckpointCompatibility.Error.incompatible("BiLSTM v2 settings are required.")
        }
        let config = Self(hiddenDim: training.hiddenDim, numLayers: training.numLayers,
                          dropout: training.dropout, numClasses: numClasses,
                          outputMode: training.lossFunction == .crossEntropy ? .classification : .embedding)
        try config.validate()
        return config
    }

    func validate() throws {
        guard version == 2, inputDim == 180, (32...512).contains(hiddenDim),
              (1...2).contains(numLayers), dropout.isFinite, dropout >= 0, dropout < 1,
              outputDim == 384, outputMode != .classification || numClasses > 0 else {
            throw CheckpointCompatibility.Error.incompatible("Invalid BiLSTM v2 dimensions, dropout or class count.")
        }
    }
}

/// Versioned recurrent experiment. The v1 Keras-style model remains unchanged.
nonisolated final class BiLSTMSignLanguageModel: @unchecked Sendable, SignLanguageModelProtocol {
    let config: BiLSTMModelConfig
    let projection: Linear
    let frameNorm: LayerNorm
    let recurrent: [BiLSTM]
    let interLayerDropout: Dropout
    let attentionScore: Linear
    let pooledNorm: LayerNorm
    let outputDropout: Dropout
    let outputProjection: Linear

    init(config: BiLSTMModelConfig) throws {
        try config.validate()
        self.config = config
        projection = Linear(config.inputDim, config.hiddenDim)
        frameNorm = LayerNorm(dimensions: config.hiddenDim)
        recurrent = (0..<config.numLayers).map { index in
            BiLSTM(inputDim: index == 0 ? config.hiddenDim : config.hiddenDim * 2, hiddenDim: config.hiddenDim)
        }
        interLayerDropout = Dropout(p: config.dropout)
        attentionScore = Linear(config.hiddenDim * 2, 1, bias: false)
        pooledNorm = LayerNorm(dimensions: config.hiddenDim * 2)
        outputDropout = Dropout(p: config.dropout)
        outputProjection = Linear(config.hiddenDim * 2, config.outputMode == .classification ? config.numClasses : config.outputDim)
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        var sequence = gelu(frameNorm(projection(x)))
        for (index, layer) in recurrent.enumerated() {
            sequence = layer(sequence, returnSequences: true)
            if index + 1 < recurrent.count { sequence = interLayerDropout(sequence) }
        }
        let attention = softmax(attentionScore(sequence), axis: 1)
        let pooled = sum(sequence * attention, axis: 1)
        let output = outputProjection(outputDropout(pooledNorm(pooled)))
        if config.outputMode == .classification { return output }
        return output / sqrt(sum(output * output, axis: -1, keepDims: true) + 1e-6)
    }

    nonisolated func modules() -> [Module] {
        [projection, frameNorm] + recurrent.flatMap { $0.modules() } +
            [interLayerDropout, attentionScore, pooledNorm, outputDropout, outputProjection]
    }
}
