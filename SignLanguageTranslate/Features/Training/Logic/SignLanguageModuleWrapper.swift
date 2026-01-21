import Foundation
import MLX
import MLXNN

// Helper wrapper to make SignLanguageModel compatible with MLX Optimizers.
// This allows us to keep SignLanguageModel as a plain class (avoiding MainActor issues via inheritance)
// while still providing a Module interface for the optimizer to traverse parameters.
public class SignLanguageModuleWrapper: Module {
    public let _model: SignLanguageModel
    // Store modules in a property so generic specific Module.children() finds them via reflection
    public let _trainableModules: [Module]
    
    // Override base init to match isolation
    nonisolated public override init() {
        fatalError("Use init(model:)")
    }
    
    // Explicitly nonisolated to avoid actor mismatch with Module.init
    nonisolated public init(model: SignLanguageModel) {
        self._model = model
        self._trainableModules = model.modules()
        super.init()
    }
    
    // Forward forward pass (Explicitly nonisolated to allow calling from background task)
    nonisolated public func callAsFunction(_ x: MLXArray) -> MLXArray {
        return _model(x)
    }
    
    // No need to override children() if we have a stored property [Module]
}
