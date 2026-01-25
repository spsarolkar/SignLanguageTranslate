import Foundation
import MLX
import MLXNN

// Protocol to abstract different model architectures
public protocol SignLanguageModelProtocol: AnyObject, Sendable {
    func callAsFunction(_ x: MLXArray) -> MLXArray
    func modules() -> [Module]
}

// Conformance for models
extension SignLanguageModel: SignLanguageModelProtocol {}
extension LegacySignLanguageModel: SignLanguageModelProtocol {}

// Helper wrapper to make SignLanguageModel compatible with MLX Optimizers.
// This allows us to keep SignLanguageModel as a plain class (avoiding MainActor issues via inheritance)
// while still providing a Module interface for the optimizer to traverse parameters.
public class SignLanguageModuleWrapper: Module {
    public let _model: any SignLanguageModelProtocol
    // Store modules in a property so generic specific Module.children() finds them via reflection
    // Renamed to remove underscore, hoping Mirror picks it up
    public let trainableLayers: [Module]
    
    // Override base init to match isolation
    nonisolated public override init() {
        fatalError("Use init(model:)")
    }
    
    // Explicitly nonisolated to avoid actor mismatch with Module.init
    nonisolated public init(model: any SignLanguageModelProtocol) {
        self._model = model
        self.trainableLayers = model.modules()
        super.init()
    }
    
    // Forward forward pass (Explicitly nonisolated to allow calling from background task)
    nonisolated public func callAsFunction(_ x: MLXArray) -> MLXArray {
        return _model(x)
    }
}
