import Foundation
import MLX
import MLXNN

/// Collection of loss functions for training the Sign Language Model
struct LossFunctions {

    /// Label smoothing factor (can be configured via TrainingConfig)
    private static var labelSmoothingFactor: Float = 0.0

    /// Set label smoothing factor (call before training starts)
    static func setLabelSmoothing(_ factor: Float) {
        labelSmoothingFactor = max(0, min(0.5, factor)) // Clamp to [0, 0.5]
    }

    /// Create one-hot encoding from integer labels
    private nonisolated static func oneHot(_ indices: MLXArray, numClasses: Int) -> MLXArray {
        let batchSize = indices.dim(0)
        // Create identity matrix and index it
        let identity = MLX.eye(numClasses)
        // Gather rows based on indices
        var result = [Float]()
        result.reserveCapacity(batchSize * numClasses)

        let indicesArray = indices.asArray(Int32.self)
        for idx in indicesArray {
            for j in 0..<numClasses {
                result.append(Int(idx) == j ? 1.0 : 0.0)
            }
        }
        return MLXArray(result, [batchSize, numClasses])
    }

    /// Computes Batch Accuracy for Contrastive Learning (InfoNCE)
    /// Checks if the highest dot product for each query is the diagonal element.
    nonisolated static func contrastiveAccuracy(predictions: MLXArray, targets: MLXArray) -> MLXArray {
        // Flatten
        let batchSize = predictions.dim(0)
        let _preds = predictions.reshaped([batchSize, -1])
        let _targets = targets.reshaped([batchSize, -1])
        
        // Normalize
        let predNorm = sqrt(sum(_preds * _preds, axis: -1, keepDims: true) + 1e-6)
        let predsNormalized = _preds / predNorm
        
        let targetNorm = sqrt(sum(_targets * _targets, axis: -1, keepDims: true) + 1e-6)
        let targetsNormalized = _targets / targetNorm
        
        // Similarities [B, B]
        let logits = matmul(predsNormalized, targetsNormalized.T)
        
        // Ground Truth indices: 0, 1, 2...
        let labels = MLXArray(0..<batchSize)
        
        // Preds = argmax of logits along axis 1 (rows)
        let preds = logits.argMax(axis: -1)
        
        // Accuracy = Mean(Preds == Labels)
        // Convert bool mask to float for mean
        // MLX: (a .== b).mean() works
        // Note: MLX swift wrapper might require cast
        let matches = (preds .== labels)
        // MLX Swift: cast boolean array to float/int to compute mean? 
        // Usually .mean() works on numeric. Let's cast using astype if needed or MLXArray(matches).
        // Let's assume matches is int/bool and can be cast.
        // Actually, let's keep it safe.
        // `matches` is boolean MLXArray.
        // `matches.sum()` gives count.
        return matches.sum() / MLXArray(Float(batchSize))
    }
    
    /// Computes the Cosine Similarity Loss between predicted video embeddings and ground truth text embeddings.
    /// Loss = 1 - CosineSimilarity(pred, target)
    /// This minimizes the angle between the two vectors, effectively aligning them in the semantic space.
    ///
    /// - Parameters:
    ///   - predictions: Video embedding tensor [Batch, Dim]
    ///   - targets: Text embedding tensor [Batch, Dim]
    /// - Returns: Scalar loss value
    nonisolated static func cosineSimilarityLoss(predictions: MLXArray, targets: MLXArray) -> MLXArray {
        // Flatten to [Batch, Dim] to avoid broadcasting issues if targets have extra dimension (e.g. [Batch, 1, Dim])
        let batchSize = predictions.dim(0)
        let _preds = predictions.reshaped([batchSize, -1])
        let _targets = targets.reshaped([batchSize, -1])
        
        // Normalize Preds
        let predNorm = sqrt(sum(_preds * _preds, axis: -1, keepDims: true) + 1e-6)
        let predsNormalized = _preds / predNorm
        
        // Normalize Targets
        let targetNorm = sqrt(sum(_targets * _targets, axis: -1, keepDims: true) + 1e-6)
        let targetsNormalized = _targets / targetNorm
        
        // Cosine Similarity = Dot Product of normalized vectors
        let cosineSim = sum(predsNormalized * targetsNormalized, axis: -1) // [Batch]
        
        // Loss = 1 - Mean(CosineSim)
        return 1.0 - mean(cosineSim)
    }

    /// Computes the Mean Cosine Similarity between predictions and targets.
    /// This is used as the evaluation "Accuracy" metric when training continuous embeddings.
    /// - Returns: Scalar value from -1.0 to 1.0, where 1.0 is a perfect match.
    nonisolated static func cosineSimilarity(predictions: MLXArray, targets: MLXArray) -> MLXArray {
        // Flatten
        let batchSize = predictions.dim(0)
        let _preds = predictions.reshaped([batchSize, -1])
        let _targets = targets.reshaped([batchSize, -1])
        
        let predNorm = sqrt(sum(_preds * _preds, axis: -1, keepDims: true) + 1e-6)
        let predsNormalized = _preds / predNorm
        
        let targetNorm = sqrt(sum(_targets * _targets, axis: -1, keepDims: true) + 1e-6)
        let targetsNormalized = _targets / targetNorm
        
        // Cosine Similarity = Dot Product of normalized vectors
        let cosineSim = sum(predsNormalized * targetsNormalized, axis: -1) // [Batch]
        
        // Return exactly the mean similarity (-1.0 to 1.0)
        return mean(cosineSim)
    }
    
    /// Computes Batch Contrastive Loss (like CLIP) with optional label smoothing
    /// Used if we want to push away incorrect labels in the same batch
    /// - Parameters:
    ///   - predictions: [Batch, Dim]
    ///   - targets: [Batch, Dim]
    ///   - temperature: Scaling factor (default 0.1)
    ///   - labelSmoothing: Smoothing factor (0 = no smoothing, typically 0.1)
    nonisolated static func contrastiveLoss(
        predictions: MLXArray,
        targets: MLXArray,
        temperature: Float = 0.07,
        labelSmoothing: Float = 0.0
    ) -> MLXArray {
        let batchSize = predictions.dim(0)
        let _preds = predictions.reshaped([batchSize, -1])
        let _targets = targets.reshaped([batchSize, -1])

        let predNorm = sqrt(sum(_preds * _preds, axis: -1, keepDims: true) + 1e-6)
        let predsNormalized = _preds / predNorm

        let targetNorm = sqrt(sum(_targets * _targets, axis: -1, keepDims: true) + 1e-6)
        let targetsNormalized = _targets / targetNorm

        // Similarity Matrix [B, B]
        // Scale: logits range [-1, 1]. Divide by small temp (0.07) -> [-14, 14]. Good for Softmax.
        let logits = matmul(predsNormalized, targetsNormalized.T) / MLXArray(temperature)

        // Ground Truth: 0, 1, 2, ... BatchSize-1
        let labels = MLXArray(0..<batchSize)

        // Apply label smoothing if specified
        let smoothing = labelSmoothing > 0 ? labelSmoothing : labelSmoothingFactor
        if smoothing > 0 {
            // Soft label cross entropy with smoothing
            // target_soft = (1 - smoothing) * one_hot + smoothing / num_classes
            let numClasses = Float(batchSize)
            let oneHotLabels = oneHot(labels, numClasses: batchSize)
            let smoothLabels = oneHotLabels * MLXArray(1.0 - smoothing) + MLXArray(smoothing / numClasses)

            // Log softmax
            let logProbs = log(softmax(logits, axis: -1) + 1e-8)
            let logProbsT = log(softmax(logits.T, axis: -1) + 1e-8)

            // Soft cross entropy: -sum(soft_target * log_prob)
            let lossI = -mean(sum(smoothLabels * logProbs, axis: -1))
            let lossT = -mean(sum(smoothLabels * logProbsT, axis: -1))

            return (lossI + lossT) / MLXArray(2.0)
        }

        // Standard cross entropy (no smoothing)
        let lossI = MLXNN.crossEntropy(logits: logits, targets: labels)
        let lossT = MLXNN.crossEntropy(logits: logits.T, targets: labels)

        return mean((lossI + lossT) / MLXArray(2.0))
    }

    nonisolated static func topKAccuracy(predictions: MLXArray, targets: MLXArray, k: Int = 5) -> MLXArray {
        let batchSize = predictions.dim(0)
        let _preds = predictions.reshaped([batchSize, -1])
        let _targets = targets.reshaped([batchSize, -1])

        // Normalize
        let predNorm = sqrt(sum(_preds * _preds, axis: -1, keepDims: true) + 1e-6)
        let predsNormalized = _preds / predNorm

        let targetNorm = sqrt(sum(_targets * _targets, axis: -1, keepDims: true) + 1e-6)
        let targetsNormalized = _targets / targetNorm

        // Similarities [B, B]
        let logits = matmul(predsNormalized, targetsNormalized.T)

        // Ground Truth indices: 0, 1, 2...
        // Get top-k predictions
        // Use argsort in descending order (negate for descending)
        let sortedIndices = argSort(-logits, axis: -1)

        // Check if true label is in top-k
        var correctCount: Float = 0
        for i in 0..<batchSize {
            let effectiveK = min(k, batchSize)
            let topKIndices = sortedIndices[i, 0..<effectiveK].asArray(Int32.self)
            if topKIndices.contains(Int32(i)) {
                correctCount += 1
            }
        }

        return MLXArray(correctCount / Float(batchSize))
    }
}
