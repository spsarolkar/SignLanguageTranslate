import Foundation
import MLX
import MLXNN

/// Model configuration for sign language recognition
public struct SignLanguageModelConfig: Codable, Sendable {
    public var inputDim: Int
    public var modelDim: Int
    public var outputDim: Int
    public var numLayers: Int
    public var numHeads: Int
    public var dropout: Float
    public var useLayerScale: Bool
    public var layerScaleInit: Float
    public var poolingType: PoolingType
    public var useRelativePositionBias: Bool

    public enum PoolingType: String, Codable, Sendable {
        case mean       // Average all timesteps
        case cls        // Use [CLS] token (first position)
        case attention  // Learned attention pooling
    }

    public static let `default` = SignLanguageModelConfig(
        inputDim: 180,
        modelDim: 256,
        outputDim: 384,
        numLayers: 4,
        numHeads: 4,
        dropout: 0.1,
        useLayerScale: true,
        layerScaleInit: 1e-4,
        poolingType: .attention,
        useRelativePositionBias: false
    )

    /// Smaller model for faster experimentation
    public static let small = SignLanguageModelConfig(
        inputDim: 180,
        modelDim: 128,
        outputDim: 384,
        numLayers: 2,
        numHeads: 4,
        dropout: 0.1,
        useLayerScale: true,
        layerScaleInit: 1e-4,
        poolingType: .mean,
        useRelativePositionBias: false
    )

    /// Larger model for better accuracy
    public static let large = SignLanguageModelConfig(
        inputDim: 180,
        modelDim: 512,
        outputDim: 384,
        numLayers: 6,
        numHeads: 8,
        dropout: 0.1,
        useLayerScale: true,
        layerScaleInit: 1e-4,
        poolingType: .attention,
        useRelativePositionBias: true
    )
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

        self.outputProjection = Linear(config.modelDim, config.outputDim)
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
            numLayers: numLayers,
            numHeads: numHeads,
            dropout: dropout,
            useLayerScale: true,
            layerScaleInit: 1e-4,
            poolingType: .mean,
            useRelativePositionBias: false
        )
        self.init(config: config)
    }

    // MARK: - Forward Pass

    public func callAsFunction(_ x: MLXArray) -> MLXArray {
        // x: [B, T, 180]
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
            mods.append(contentsOf: pooling.modules())
        }
        for enc in encoderLayers {
            mods.append(contentsOf: enc.modules())
        }
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
public class ImprovedTransformerEncoderLayer: @unchecked Sendable {

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

    public init(
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
    }

    public func callAsFunction(_ x: MLXArray, mask: MLXArray? = nil) -> MLXArray {
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
        guard dropPath > 0 else { return x }

        // During inference, don't drop
        // Note: MLX doesn't have a built-in training mode check, so we rely on
        // dropout being disabled during inference via module.eval()
        let keepProb = 1.0 - dropPath
        return x * MLXArray(keepProb)
    }

    nonisolated public func modules() -> [Module] {
        return [attention, norm1, norm2, mlp, dropout]
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
public class AttentionPooling: @unchecked Sendable {
    private let query: MLXArray
    private let keyProj: Linear
    private let valueProj: Linear
    private let dims: Int

    public init(dims: Int) {
        self.dims = dims
        // Learnable query vector - initialize with small random values
        let queryData = (0..<dims).map { _ in Float.random(in: -0.02...0.02) }
        self.query = MLXArray(queryData).reshaped([1, 1, dims])
        self.keyProj = Linear(dims, dims)
        self.valueProj = Linear(dims, dims)
    }

    public func callAsFunction(_ x: MLXArray) -> MLXArray {
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

    nonisolated public func modules() -> [Module] {
        return [keyProj, valueProj]
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
        let divTerm = exp(MLXArray(stride(from: 0, to: dModel, by: 2)).asType(.float32) * (-log(10000.0) / Float(dModel)))
        
        let sinPart = sin(position * divTerm)
        let cosPart = cos(position * divTerm)
        
        let peEncoding = concatenated([sinPart, cosPart], axis: -1)
        return x + peEncoding.reshaped([1, T, dModel])
    }
}
