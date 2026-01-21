import Foundation
import MLX
import MLXNN

/// A Transformer-based model for translating sign language pose sequences into semantic embeddings.
/// Defined as a plain class to avoid MainActor isolation issues with MLXNN.Module inheritance in Swift 6.
public class SignLanguageModel: @unchecked Sendable {
    
    // MARK: - Properties
    
    let inputDim: Int
    let modelDim: Int
    let outputDim: Int
    let numLayers: Int
    let numHeads: Int
    let dropout: Float
    
    // MARK: - Layers
    
    public let inputProjection: Linear
    public let positionalEncoding: SinusoidalPositionalEncoding
    public let encoderLayers: [CustomTransformerEncoderLayer]
    public let outputProjection: Linear
    public let dropoutLayer: Dropout
    
    // MARK: - Initialization
    
    public init(
        inputDim: Int = 180,
        modelDim: Int = 256,
        outputDim: Int = 384,
        numLayers: Int = 4,
        numHeads: Int = 4,
        dropout: Float = 0.1
    ) {
        self.inputDim = inputDim
        self.modelDim = modelDim
        self.outputDim = outputDim
        self.numLayers = numLayers
        self.numHeads = numHeads
        self.dropout = dropout
        
        self.inputProjection = Linear(inputDim, modelDim)
        self.positionalEncoding = SinusoidalPositionalEncoding(dModel: modelDim)
        
        self.encoderLayers = (0..<numLayers).map { _ in
            CustomTransformerEncoderLayer(
                dims: modelDim,
                numHeads: numHeads,
                mlpDims: modelDim * 4,
                dropout: dropout
            )
        }
        
        self.outputProjection = Linear(modelDim, outputDim)
        self.dropoutLayer = Dropout(p: dropout)
    }
    
    // MARK: - Forward Pass
    
    public func callAsFunction(_ x: MLXArray) -> MLXArray {
        // x: [B, T, 180]
        var h = inputProjection(x)
        
        h = positionalEncoding(h)
        h = dropoutLayer(h)
        
        for layer in encoderLayers {
            h = layer(h, mask: nil)
        }
        
        // Mean Pooling: [B, T, D] -> [B, D]
        h = mean(h, axis: 1)
        
        h = outputProjection(h)
        
        // Normalize for Cosine Similarity
        let norm = sqrt(sum(h * h, axis: -1, keepDims: true) + 1e-6)
        h = h / norm
        
        return h
    }
    
    // MARK: - Parameter Access (Manual)
    
    /// Collects all modules for optimizer usage
    public func modules() -> [Module] {
        var mods: [Module] = [inputProjection, outputProjection, dropoutLayer]
        for enc in encoderLayers {
            mods.append(contentsOf: enc.modules())
        }
        return mods
    }
}

// MARK: - Components

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
    
    public func modules() -> [Module] {
        return [attention, norm1, norm2, mlp, dropout]
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
