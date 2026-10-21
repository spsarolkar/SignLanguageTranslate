import MLX
import MLXNN

nonisolated enum RecurrentTrainingStep {
    typealias Gradient = (SignLanguageModuleWrapper, [MLXArray]) -> ([MLXArray], ModuleParameters)

    static func gradient(model: SignLanguageModuleWrapper, config: TrainingConfig) -> Gradient {
        // MLX 0.30.6 differentiates only output[0]; subsequent outputs are
        // stop-gradient auxiliaries. Keep the transformed closure across batches.
        valueAndGrad(model: model) { (model: SignLanguageModuleWrapper, arrays: [MLXArray]) in
            let predictions = model(arrays[0])
            return [loss(predictions: predictions, targets: arrays[1], config: config), predictions]
        }
    }

    static func loss(predictions: MLXArray, targets: MLXArray, config: TrainingConfig) -> MLXArray {
        switch config.lossFunction {
        case .contrastive:
            return LossFunctions.contrastiveLoss(predictions: predictions, targets: targets,
                temperature: config.contrastiveTemperature, labelSmoothing: config.labelSmoothing)
        case .cosine: return LossFunctions.cosineSimilarityLoss(predictions: predictions, targets: targets)
        case .crossEntropy: return crossEntropy(logits: predictions, targets: targets, reduction: .mean)
        }
    }

    static func metric(predictions: MLXArray, targets: MLXArray, config: TrainingConfig) -> MLXArray {
        if config.lossFunction == .crossEntropy { return (predictions.argMax(axis: -1) .== targets).mean() }
        return LossFunctions.cosineSimilarity(predictions: predictions, targets: targets)
    }

    /// One graph reduction/host read, preserving the original gradient tree.
    /// Like the existing trainer, this reports norm without applying clipping.
    static func gradientNorm(_ gradients: ModuleParameters) -> MLXArray {
        let sums = gradients.flattened().map { (_, array) in sum(array * array) }
        return sums.isEmpty ? MLXArray(Float(0)) : sqrt(sum(stacked(sums)))
    }
}
