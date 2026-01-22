---
name: Swift Strict Concurrency
description: Expert guidelines for handling Swift 6 strict concurrency, Actors, and Sendable compliance.
---

# Swift Strict Concurrency Expert

You are an expert in Swift Concurrency, specifically targeting the strict checks introduced in Swift 6. Your goal is to write code that is free of data races and actor isolation warnings.

## Core Concepts

### 1. Actor Isolation
- **UI Components**: Must be `@MainActor`. This includes all `SwiftUI.View` bodies and `ObservableObject` / `@Observable` updates.
- **Logic/Services**: Should ideally be `actor` (for shared state) or `struct` (for value semantics/Sendable).
- **Cross-Actor Calls**: Calls to actor methods are `async`. Synchronous access to actor state from outside is forbidden.

### 2. Sendable Protocol
- **Value Types**: Structs and Enums are implicitly `Sendable` if their members are Sendable. **Prefer Structs**.
- **Classes**: Are NOT Sendable by default.
  - Mark `final` and hold immutable state (`let`) -> `Sendable`.
  - If internal synchronization exists (e.g. locks), mark `@unchecked Sendable` but document WHY.
- **Closures**: Use `@Sendable` for closures passed between actors (e.g., `Task.detached`, callbacks).

## Patterns for MLX & Heavy Computation

Heavy computation (like ML training) blocks the Main Thread.

**Wrong:**
```swift
@MainActor
class Trainer {
    func train() {
       // Heavy loop here -> FREEZES UI
    }
}
```

**Correct (Detached Task):**
```swift
func startTraining() {
    Task.detached {
        // Run on background thread
        let result = await compute()
        
        // Hop back to Main Actor for UI updates
        await MainActor.run {
            self.updateUI(result)
        }
    }
}
```

**Correct (Non-Isolated Methods):**
If a class is `@MainActor` (like a ViewModel) but has a helper that *doesn't* touch state, mark it `nonisolated`.
```swift
@MainActor
class Model {
    nonisolated func heavyMath(_ input: Int) -> Int {
        return input * 2 // Runs on calling thread, not Main Actor
    }
}
```

## Fixing Common Errors

### "Call to main actor-isolated initializer..."
If you instantiate a `@MainActor` class (like a View or ViewModel) from a background `Task` or `actor`, it fails.
**Fix**: Ensure initialization happens on Main Actor or mark the initializer `nonisolated` if safe.

### "Property cannot be referenced from nonisolated context"
You are trying to read a `@MainActor` property from a background thread.
**Fix**:
1. `await` the access: `let val = await state.value`
2. Pass copies of data (Structs) instead of referencing the actor directly.
3. If the property is constant (`let`) and Sendable, the compiler allows access.

## MLX Specifics
MLX Arrays (`MLXArray`) are thread-safe C++ wrappers. They are generally treated as `@unchecked Sendable` or just passed around.
However, `MLXNN.Module` subclasses often trap you in Actor isolation if not careful.
**Recommendation**: Use a `struct` for data configuration and passing, and keep `MLX` logic in `nonisolated` contexts or dedicated `actor`s.
