import Foundation
import MLX
import MLXNN

/// Model configuration for sign language recognition
public struct SignLanguageModelConfig: Codable, Sendable {
    public var inputDim: Int
    public var modelDim: Int
    public var outputDim: Int       // Embedding dimension (used in embedding mode)
    public var numClasses: Int      // Number of classes for classification mode
    public var numLayers: Int
    public var numHeads: Int
    public var dropout: Float
    public var useLayerScale: Bool
    public var layerScaleInit: Float
    public var poolingType: PoolingType
    public var useRelativePositionBias: Bool
    public var outputMode: OutputMode

    public enum PoolingType: String, Codable, Sendable {
        case mean       // Average all timesteps
        case cls        // Use [CLS] token (first position)
        case attention  // Learned attention pooling
    }

    /// Output mode: embedding for contrastive learning, classification for softmax
    public enum OutputMode: String, Codable, Sendable {
        case embedding      // Output L2-normalized embeddings for contrastive loss
        case classification // Output logits for cross-entropy loss
    }

    public static let `default` = SignLanguageModelConfig(
        inputDim: 180,
        modelDim: 384,        // Increased from 256 for better capacity
        outputDim: 384,
        numClasses: 100,      // Default, will be set based on actual labels
        numLayers: 6,         // Increased from 4 for deeper representations
        numHeads: 6,          // Increased from 4 (384 / 6 = 64 dim per head)
        dropout: 0.15,        // Slightly higher for regularization
        useLayerScale: true,
        layerScaleInit: 1e-4,
        poolingType: .attention,
        useRelativePositionBias: true,  // Enable for better temporal understanding
        outputMode: .classification     // Default to classification for direct supervision
    )

    /// Smaller model for faster experimentation
    public static let small = SignLanguageModelConfig(
        inputDim: 180,
        modelDim: 192,        // Increased from 128
        outputDim: 384,
        numClasses: 100,
        numLayers: 3,         // Increased from 2
        numHeads: 4,
        dropout: 0.1,
        useLayerScale: true,
        layerScaleInit: 1e-4,
        poolingType: .mean,
        useRelativePositionBias: false,
        outputMode: .classification
    )

    /// Larger model for better accuracy
    public static let large = SignLanguageModelConfig(
        inputDim: 180,
        modelDim: 512,
        outputDim: 384,
        numClasses: 100,
        numLayers: 8,         // Increased from 6
        numHeads: 8,
        dropout: 0.2,         // Higher dropout for larger model
        useLayerScale: true,
        layerScaleInit: 1e-4,
        poolingType: .attention,
        useRelativePositionBias: true,
        outputMode: .classification
    )

    /// T5 Small architecture (approx 60M params)
    public static let t5_small = SignLanguageModelConfig(
        inputDim: 180,
        modelDim: 512,
        outputDim: 384,
        numClasses: 100,
        numLayers: 6,
        numHeads: 8,
        dropout: 0.1,
        useLayerScale: true,
        layerScaleInit: 1e-4,
        poolingType: .attention,
        useRelativePositionBias: true,
        outputMode: .classification
    )

    /// T5 Base architecture (approx 220M params)
    public static let t5_base = SignLanguageModelConfig(
        inputDim: 180,
        modelDim: 768,
        outputDim: 384,
        numClasses: 100,
        numLayers: 12,
        numHeads: 12,
        dropout: 0.1,
        useLayerScale: true,
        layerScaleInit: 1e-4,
        poolingType: .attention,
        useRelativePositionBias: true,
        outputMode: .classification
    )

    /// Helper to find valid number of heads for a given modelDim
    public static func findValidHeads(for modelDim: Int) -> Int {
        let preferred = [4, 6, 8, 2, 1]
        for heads in preferred {
            if modelDim % heads == 0 {
                return heads
            }
        }
        return 1 // Fallback
    }

    /// Validate and auto-correct numHeads if needed
    public func validated() -> SignLanguageModelConfig {
        var copy = self
        if modelDim % numHeads != 0 {
            copy.numHeads = SignLanguageModelConfig.findValidHeads(for: modelDim)
        }
        return copy
    }
}

/// A Transformer-based model for translating sign language pose sequences into semantic embeddings.
///
/// ## Architecture Improvements
/// - **Layer Scale**: Stabilizes training for deep networks (from CaiT paper)
/// - **Pre-Norm**: LayerNorm before attention/MLP (more stable than post-norm)
/// - **Attention Pooling**: Learned pooling instead of mean (optional)
/// - **Stochastic Depth**: Progressive dropout across layers (optional)
///
/// ## Input/Output
/// - Input: `[Batch, Time=60, Features=180]` (pose keypoints)
/// - Output: `[Batch, 384]` (normalized embedding for cosine similarity)
///
/// Defined as a plain class to avoid MainActor isolation issues with MLXNN.Module inheritance in Swift 6.
public class SignLanguageModel: @unchecked Sendable {

    // MARK: - Properties

    public let config: SignLanguageModelConfig

    // MARK: - Layers

    public let inputProjection: Linear
    public let inputNorm: LayerNorm
    public let positionalEncoding: SinusoidalPositionalEncoding
    public let encoderLayers: [ImprovedTransformerEncoderLayer]
    public let outputNorm: LayerNorm
    public let poolingLayer: AttentionPooling?
    public let outputProjection: Linear
    public let dropoutLayer: Dropout

    // MARK: - Initialization

    public init(config: SignLanguageModelConfig = .default) {
        // Validate that modelDim is divisible by numHeads
        precondition(
            config.modelDim % config.numHeads == 0,
            "modelDim (\(config.modelDim)) must be divisible by numHeads (\(config.numHeads)). Try numHeads=\(SignLanguageModelConfig.findValidHeads(for: config.modelDim))"
        )

        self.config = config

        // Input projection with normalization
        self.inputProjection = Linear(config.inputDim, config.modelDim)
        self.inputNorm = LayerNorm(dimensions: config.modelDim)

        self.positionalEncoding = SinusoidalPositionalEncoding(dModel: config.modelDim)

        // Build encoder layers with stochastic depth
        let dropPathRates = Self.linspace(0, 0.1, config.numLayers)
        self.encoderLayers = (0..<config.numLayers).map { i in
            ImprovedTransformerEncoderLayer(
                dims: config.modelDim,
                numHeads: config.numHeads,
                mlpDims: config.modelDim * 4,
                dropout: config.dropout,
                dropPath: dropPathRates[i],
                useLayerScale: config.useLayerScale,
                layerScaleInit: config.layerScaleInit
            )
        }

        self.outputNorm = LayerNorm(dimensions: config.modelDim)

        // Pooling strategy
        if config.poolingType == .attention {
            self.poolingLayer = AttentionPooling(dims: config.modelDim)
        } else {
            self.poolingLayer = nil
        }

        let finalOutputDim = config.outputMode == .classification ? config.numClasses : config.outputDim
        self.outputProjection = Linear(config.modelDim, finalOutputDim)
        self.dropoutLayer = Dropout(p: config.dropout)
    }

    /// Convenience initializer for backward compatibility
    public convenience init(
        inputDim: Int = 180,
        modelDim: Int = 256,
        outputDim: Int = 384,
        numLayers: Int = 4,
        numHeads: Int = 4,
        dropout: Float = 0.1
    ) {
        let config = SignLanguageModelConfig(
            inputDim: inputDim,
            modelDim: modelDim,
            outputDim: outputDim,
            numClasses: 100,
            numLayers: numLayers,
            numHeads: numHeads,
            dropout: dropout,
            useLayerScale: true,
            layerScaleInit: 1e-4,
            poolingType: .mean,
            useRelativePositionBias: false,
            outputMode: .classification
        )
        self.init(config: config)
    }

    // MARK: - Forward Pass

    public func callAsFunction(_ x: MLXArray) -> MLXArray {
        // x: [B, T, 180]
        #if DEBUG
        if x.shape.count >= 2 && x.shape[1] != 60 {
             print("⚠️ Transformer Input Shape Warning: \(x.shape). Expected T=60.")
        }
        #endif
        
        var h = inputProjection(x)
        h = inputNorm(h)

        h = positionalEncoding(h)
        h = dropoutLayer(h)

        // Transformer encoder
        for layer in encoderLayers {
            h = layer(h, mask: nil)
        }

        // Final normalization
        h = outputNorm(h)

        // Pooling: [B, T, D] -> [B, D]
        switch config.poolingType {
        case .mean:
            h = mean(h, axis: 1)
        case .cls:
            // Use first token as CLS
            h = h[0..., 0, 0...]
        case .attention:
            if let pooling = poolingLayer {
                h = pooling(h)
            } else {
                h = mean(h, axis: 1)
            }
        }

        // Output projection
        h = outputProjection(h)

        // L2 Normalize for Cosine Similarity loss
        let norm = sqrt(sum(h * h, axis: -1, keepDims: true) + 1e-6)
        h = h / norm

        return h
    }

    // MARK: - Parameter Access

    /// Collects all modules for optimizer usage
    nonisolated public func modules() -> [Module] {
        var mods: [Module] = [inputProjection, inputNorm, outputNorm, outputProjection, dropoutLayer]
        if let pooling = poolingLayer {
            mods.append(pooling)
        }
        mods.append(contentsOf: encoderLayers)
        return mods
    }

    // MARK: - Helpers

    private static func linspace(_ start: Float, _ end: Float, _ count: Int) -> [Float] {
        guard count > 1 else { return [start] }
        let step = (end - start) / Float(count - 1)
        return (0..<count).map { start + Float($0) * step }
    }
}

// MARK: - Components

/// Improved Transformer Encoder Layer with Layer Scale and Stochastic Depth
///
/// Key improvements over vanilla transformer:
/// - **Layer Scale**: Learnable per-channel scaling (from CaiT paper) for training stability
/// - **Stochastic Depth**: Random layer dropout during training for regularization
/// - **Pre-Norm**: LayerNorm before attention/MLP (more stable gradients)
public class ImprovedTransformerEncoderLayer: Module, @unchecked Sendable {

    public let attention: MultiHeadAttention
    public let norm1: LayerNorm
    public let norm2: LayerNorm
    public let mlp: Sequential
    public let dropout: Dropout

    // Layer scale parameters
    private let useLayerScale: Bool
    private let gamma1: MLXArray?
    private let gamma2: MLXArray?

    // Stochastic depth
    private let dropPath: Float

    nonisolated public override init() {
        fatalError("Use init(dims:...)")
    }

    nonisolated public init(
        dims: Int,
        numHeads: Int,
        mlpDims: Int,
        dropout: Float = 0.1,
        dropPath: Float = 0.0,
        useLayerScale: Bool = true,
        layerScaleInit: Float = 1e-4
    ) {
        self.attention = MultiHeadAttention(dimensions: dims, numHeads: numHeads)
        self.norm1 = LayerNorm(dimensions: dims)
        self.norm2 = LayerNorm(dimensions: dims)
        self.dropout = Dropout(p: dropout)
        self.dropPath = dropPath
        self.useLayerScale = useLayerScale

        // Layer scale: small initial values help with deep network training
        if useLayerScale {
            self.gamma1 = MLXArray(Array(repeating: layerScaleInit, count: dims))
            self.gamma2 = MLXArray(Array(repeating: layerScaleInit, count: dims))
        } else {
            self.gamma1 = nil
            self.gamma2 = nil
        }

        self.mlp = Sequential(layers: [
            Linear(dims, mlpDims),
            GELU(),
            Dropout(p: dropout),
            Linear(mlpDims, dims),
            Dropout(p: dropout)
        ])
        super.init()
    }

    nonisolated public func callAsFunction(_ x: MLXArray, mask: MLXArray? = nil) -> MLXArray {
        // Pre-norm attention block
        var y = norm1(x)
        y = attention(y, keys: y, values: y, mask: mask)
        y = dropout(y)

        // Apply layer scale
        if useLayerScale, let gamma1 = gamma1 {
            y = y * gamma1
        }

        // Stochastic depth (drop entire residual path)
        y = dropPathForward(y)

        var out = x + y

        // Pre-norm MLP block
        y = norm2(out)
        y = mlp(y)

        // Apply layer scale
        if useLayerScale, let gamma2 = gamma2 {
            y = y * gamma2
        }

        // Stochastic depth
        y = dropPathForward(y)

        out = out + y

        return out
    }

    /// Stochastic depth: randomly drop the entire residual path
    private func dropPathForward(_ x: MLXArray) -> MLXArray {
        // FIXME: MLX doesn't expose a clean 'training' flag here, so proper stochastic depth 
        // (dropping with probability p during training, identity during inference) is hard 
        // without API changes. For now, disable it to prevent signal attenuation bug.
        return x
    }
}

/// Legacy transformer layer for backward compatibility
public class CustomTransformerEncoderLayer: @unchecked Sendable {

    public let attention: MultiHeadAttention
    public let norm1: LayerNorm
    public let norm2: LayerNorm
    public let mlp: Sequential
    public let dropout: Dropout

    public init(dims: Int, numHeads: Int, mlpDims: Int, dropout: Float = 0.1) {
        self.attention = MultiHeadAttention(dimensions: dims, numHeads: numHeads)
        self.norm1 = LayerNorm(dimensions: dims)
        self.norm2 = LayerNorm(dimensions: dims)
        self.dropout = Dropout(p: dropout)

        self.mlp = Sequential(layers: [
            Linear(dims, mlpDims),
            GELU(),
            Dropout(p: dropout),
            Linear(mlpDims, dims),
            Dropout(p: dropout)
        ])
    }

    public func callAsFunction(_ x: MLXArray, mask: MLXArray? = nil) -> MLXArray {
        var y = norm1(x)
        y = attention(y, keys: y, values: y, mask: mask)
        y = dropout(y)
        var out = x + y

        y = norm2(out)
        y = mlp(y)
        out = out + y

        return out
    }

    nonisolated public func modules() -> [Module] {
        return [attention, norm1, norm2, mlp, dropout]
    }
}

/// Attention-based pooling layer
///
/// Learns to weight different timesteps instead of simple mean pooling.
/// Uses a learnable query vector that attends to all positions.
public class AttentionPooling: Module, @unchecked Sendable {
    private let query: MLXArray
    private let keyProj: Linear
    private let valueProj: Linear
    private let dims: Int

    nonisolated public override init() {
        fatalError("Use init(dims:...)")
    }

    nonisolated public init(dims: Int) {
        self.dims = dims
        // Learnable query vector - initialize with small random values
        let queryData = (0..<dims).map { _ in Float.random(in: -0.02...0.02) }
        self.query = MLXArray(queryData).reshaped([1, 1, dims])
        self.keyProj = Linear(dims, dims)
        self.valueProj = Linear(dims, dims)
        super.init()
    }

    nonisolated public func callAsFunction(_ x: MLXArray) -> MLXArray {
        // x: [B, T, D]
        let batchSize = x.dim(0)

        // Expand query for batch
        let q = broadcast(query, to: [batchSize, 1, dims]) // [B, 1, D]
        let k = keyProj(x) // [B, T, D]
        let v = valueProj(x) // [B, T, D]

        // Attention scores: [B, 1, T]
        let scale = MLXArray(1.0 / sqrt(Float(dims)))
        var attnWeights = matmul(q, k.transposed(0, 2, 1)) * scale
        attnWeights = softmax(attnWeights, axis: -1)

        // Weighted sum: [B, 1, D] -> [B, D]
        let pooled = matmul(attnWeights, v)
        return pooled.squeezed(axis: 1)
    }
}

public class SinusoidalPositionalEncoding: @unchecked Sendable {
    let dModel: Int
    
    public init(dModel: Int) {
        self.dModel = dModel
    }
    
    public func callAsFunction(_ x: MLXArray) -> MLXArray {
        let T = x.dim(1)
        let position = MLXArray(0..<T).asType(.float32).reshaped([T, 1])
        let halfDim = dModel / 2
        let divTermRaw = exp(MLXArray(stride(from: 0, to: dModel, by: 2)).asType(.float32) * (-log(10000.0) / Float(dModel)))
        let divTerm = divTermRaw.reshaped([1, halfDim])
        
        // Broadcasts [T, 1] * [1, halfDim] -> [T, halfDim]
        let sinPart = sin(position * divTerm)
        let cosPart = cos(position * divTerm)
        
        let peEncoding = concatenated([sinPart, cosPart], axis: -1)
        return x + peEncoding.reshaped([1, T, dModel])
    }
}
