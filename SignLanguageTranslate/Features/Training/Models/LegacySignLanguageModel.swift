import Foundation
import MLX
import MLXNN

/// Legacy LSTM-based model for sign language translation.
/// Replicates the architecture of the original Keras model:
/// Masking -> BN -> BiLSTM(32) -> Dropout -> BiLSTM(32) -> ELU -> Dense -> BN -> ...
public class LegacySignLanguageModel: @unchecked Sendable {
    
    // Layers
    public let inputNorm: BatchNorm
    public let lstm1: BiLSTM
    public let dropout1: Dropout
    
    public let lstm2: BiLSTM
    
    // Dense block 1
    public let dense1: Linear
    public let bn1: BatchNorm
    public let dropout2: Dropout
    
    // Dense block 2
    public let dense2: Linear
    public let bn2: BatchNorm
    
    // Output block
    public let dropout3: Dropout
    public let outputDense: Linear
    
    public init(inputDim: Int = 180, numClasses: Int, hiddenDim: Int = 32) {
        // Initial BatchNormalization (acts as input scaler)
        self.inputNorm = BatchNorm(featureCount: inputDim)
        
        // Layer 1: Bidirectional LSTM
        self.lstm1 = BiLSTM(inputDim: inputDim, hiddenDim: hiddenDim, dropout: 0.2)
        self.dropout1 = Dropout(p: 0.2)
        
        // Layer 2: Bidirectional LSTM
        // Input to 2nd LSTM is hiddenDim * 2 (because of bidirectional)
        self.lstm2 = BiLSTM(inputDim: hiddenDim * 2, hiddenDim: hiddenDim, dropout: 0.2)
        
        // Dense Block 1
        self.dense1 = Linear(hiddenDim * 2, hiddenDim, bias: false)
        self.bn1 = BatchNorm(featureCount: hiddenDim)
        self.dropout2 = Dropout(p: 0.2)
        
        // Dense Block 2
        self.dense2 = Linear(hiddenDim, hiddenDim, bias: false)
        self.bn2 = BatchNorm(featureCount: hiddenDim)
        
        // Output Block
        self.dropout3 = Dropout(p: 0.2)
        self.outputDense = Linear(hiddenDim, numClasses)
    }
    
    public func callAsFunction(_ x: MLXArray) -> MLXArray {
        // x: [Batch, Time, Features]
        
        // 1. Batch Normalization
        var h = inputNorm(x)
        
        // 2. BiLSTM 1 (Returns sequences = True)
        h = lstm1(h, returnSequences: true)
        
        // 3. Dropout
        h = dropout1(h)
        
        // 4. BiLSTM 2 (Returns sequences = False - i.e., last step)
        h = lstm2(h, returnSequences: false) 
        
        // 5. Dense Block 1
        h = elu(h)
        h = dense1(h)
        h = bn1(h)
        h = dropout2(h)
        
        // 6. Dense Block 2
        h = elu(h)
        h = dense2(h)
        h = bn2(h)
        
        // 7. Output Block
        h = elu(h)
        h = dropout3(h)
        h = outputDense(h)
        
        return h
    }
    
    // ELU Activation helper (Inline)
    private func elu(_ x: MLXArray, alpha: Float = 1.0) -> MLXArray {
        // ELU: x if x > 0 else alpha * (exp(x) - 1)
        return MLX.where(x .> 0, x, alpha * (exp(x) - 1))
    }
    
    nonisolated public func modules() -> [Module] {
        var mods: [Module] = [inputNorm, dropout1]
        mods.append(contentsOf: lstm1.modules())
        mods.append(contentsOf: lstm2.modules())
        
        mods.append(contentsOf: [dense1, bn1, dropout2])
        mods.append(contentsOf: [dense2, bn2])
        mods.append(contentsOf: [dropout3, outputDense])
        
        return mods
    }
}

// MARK: - Helper Classes

/// Bidirectional LSTM wrapper
/// Not a Module itself, but contains modules.
public class BiLSTM: @unchecked Sendable {
    public let forwardLSTM: LSTM
    public let backwardLSTM: LSTM
    public let hiddenDim: Int
    
    public init(inputDim: Int, hiddenDim: Int, dropout: Float = 0.0) {
        self.hiddenDim = hiddenDim
        self.forwardLSTM = LSTM(inputSize: inputDim, hiddenSize: hiddenDim, bias: true)
        self.backwardLSTM = LSTM(inputSize: inputDim, hiddenSize: hiddenDim, bias: true)
    }
    
    public func callAsFunction(_ x: MLXArray, returnSequences: Bool = true) -> MLXArray {
        // x: [Batch, Time, Features]
        
        // Forward pass
        let (outFwd, _) = forwardLSTM(x)
        
        // Helper to reverse along time axis (axis 1)
        func reverseTime(_ array: MLXArray) -> MLXArray {
            let T = array.dim(1)
            let indices = MLXArray(stride(from: T - 1, through: 0, by: -1).map { Int32($0) })
            return take(array, indices, axis: 1)
        }
        
        // Backward pass
        let xRev = reverseTime(x)
        let (outBwdRev, _) = backwardLSTM(xRev)
        
        // Reverse backward output back
        let outBwd: MLXArray
        if returnSequences {
            outBwd = reverseTime(outBwdRev)
        } else {
            outBwd = outBwdRev
        }

        if returnSequences {
            // Concat along feature dimension
            return concatenated([outFwd, outBwd], axis: -1)
        } else {
            // Take last time step from Forward [Batch, -1, Features]
            let T = outFwd.dim(1)
            let lastFwd = outFwd[0..., T-1] 
            
            // Take last processed step from Backward (which corresponds to t=0 input)
            let lastBwd = outBwd[0..., T-1] 
            
            return concatenated([lastFwd, lastBwd], axis: -1)
        }
    }
    
    nonisolated public func modules() -> [Module] {
        return [forwardLSTM, backwardLSTM]
    }
}
