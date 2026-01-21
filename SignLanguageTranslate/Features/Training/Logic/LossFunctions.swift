import Foundation
import MLX
import MLXNN

/// Collection of loss functions for training the Sign Language Model
struct LossFunctions {
    
    /// Computes the Cosine Similarity Loss between predicted video embeddings and ground truth text embeddings.
    /// Loss = 1 - CosineSimilarity(pred, target)
    /// This minimizes the angle between the two vectors, effectively aligning them in the semantic space.
    ///
    /// - Parameters:
    ///   - predictions: Video embedding tensor [Batch, Dim]
    ///   - targets: Text embedding tensor [Batch, Dim]
    /// - Returns: Scalar loss value
    static func cosineSimilarityLoss(predictions: MLXArray, targets: MLXArray) -> MLXArray {
        // Ensure inputs are normalized (SignLanguageModel output should already be normalized, but targets rely on extractor)
        // Normalizing here ensures robustness
        
        // Normalize Preds
        let predNorm = sqrt(sum(predictions * predictions, axis: -1, keepDims: true) + 1e-6)
        let predsNormalized = predictions / predNorm
        
        // Normalize Targets
        let targetNorm = sqrt(sum(targets * targets, axis: -1, keepDims: true) + 1e-6)
        let targetsNormalized = targets / targetNorm
        
        // Cosine Similarity = Dot Product of normalized vectors
        // Element-wise multiplication then sum over dim
        let cosineSim = sum(predsNormalized * targetsNormalized, axis: -1) // [Batch]
        
        // Loss = 1 - Mean(CosineSim)
        // Range: 0 (Perfect alignment) to 2 (Opposite direction)
        return 1.0 - mean(cosineSim)
    }
    
    /// Computes Batch Contrastive Loss (like CLIP)
    /// Used if we want to push away incorrect labels in the same batch
    /// - Parameters:
    ///   - predictions: [Batch, Dim]
    ///   - targets: [Batch, Dim]
    ///   - temperature: Scaling factor (default 0.1)
    static func contrastiveLoss(predictions: MLXArray, targets: MLXArray, temperature: Float = 0.1) -> MLXArray {
        // Implementation logic for CLIP-style loss:
        // 1. MatMul(Preds, Targets.T) -> [Batch, Batch] Similarity Matrix
        // 2. Labels are diagonal (i.e., ith video matches ith label)
        // 3. Cross Entropy on rows and columns
        
        let predNorm = sqrt(sum(predictions * predictions, axis: -1, keepDims: true) + 1e-6)
        let predsNormalized = predictions / predNorm
        
        let targetNorm = sqrt(sum(targets * targets, axis: -1, keepDims: true) + 1e-6)
        let targetsNormalized = targets / targetNorm
        
        // Similarity Matrix [B, B]
        let logits = matmul(predsNormalized, targetsNormalized.T) * exp(temperature)
        
        // Ground Truth: 0, 1, 2, ... BatchSize-1
        let batchSize = predictions.dim(0)
        let labels = MLXArray(0..<batchSize)
        
        // Cross Entropy
        let lossI = MLXNN.crossEntropy(logits: logits, targets: labels)
        let lossT = MLXNN.crossEntropy(logits: logits.T, targets: labels)
        
        return (lossI + lossT) / MLXArray(2.0)
    }
}
