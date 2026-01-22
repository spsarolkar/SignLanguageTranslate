---
name: MLX Swift Optimization
description: Guidelines for building and training Neural Networks using MLX Swift on iOS.
---

# MLX Swift Expert

You are an expert in using the MLX framework (by Apple) for efficient Machine Learning on Apple Silicon (iOS/macOS).

## Key Capabilities
- **Unified Memory**: MLX uses unified memory. No explicit "data transfer" to GPU needed, but be mindful of retaining large arrays.
- **Lazy Evaluation**: Operations are lazy. Use `eval()` to force computation when timing or debugging.

## Model Architecture Pattern

To avoid Swift Actor isolation issues with `MLXNN.Module`, follow this composition pattern:

```swift
import MLX
import MLXNN

// 1. Define Config as Sendable Struct
public struct ModelConfig: Sendable {
    let inputDim: Int
    let hiddenDim: Int
}

// 2. Define Model as Plain Class (or Struct)
// Do NOT inherit from Module if it causes Actor issues, or ensure it is nonisolated.
// @unchecked Sendable is often needed if it holds MLX Modules which aren't strictly Sendable yet.
public class MyModel: @unchecked Sendable {
    public let layer1: Linear
    public let layer2: Linear
    
    public init(config: ModelConfig) {
        self.layer1 = Linear(config.inputDim, config.hiddenDim)
        self.layer2 = Linear(config.hiddenDim, config.inputDim)
    }
    
    public func callAsFunction(_ x: MLXArray) -> MLXArray {
        return layer2(relu(layer1(x)))
    }
    
    // 3. Expose Modules for Optimizer
    // Mark nonisolated to allow access from background training loop
    nonisolated public func modules() -> [Module] {
        return [layer1, layer2]
    }
}
```

## Training Loop Pattern

Run training on a background thread (`Task.detached`) to keep UI smooth.

```swift
func train() {
    Task.detached(priority: .userInitiated) {
        let optimizer = Adam(learningRate: 1e-3)
        
        // Define loss function
        func lossFn(model: MyModel, x: MLXArray, y: MLXArray) -> MLXArray {
            let pred = model(x)
            return mse_loss(pred, y)
        }
        
        // Compile logical step
        let step = valueAndGrad(model: model, fn: lossFn)
        
        for epoch in 1...100 {
            let (loss, grads) = step(model, x, y)
            optimizer.update(model: model, gradients: grads)
            eval(model, optimizer) // Ensure computation happens
        }
    }
}
```

## Performance Tips
1.  **Batching**: Always process data in batches (e.g., `[32, 60, 180]`).
2.  **`eval()`**: Call `eval(loss, model.parameters())` at the end of a step to ensure graphs don't explode in memory.
3.  **Stream Evaluation**: For inference, use `MLX.compile` on the forward pass function if dimensions are static.
