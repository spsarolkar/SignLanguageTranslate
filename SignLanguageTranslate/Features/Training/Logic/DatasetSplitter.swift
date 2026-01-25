import Foundation

/// Utility for splitting datasets into Training and Validation sets
/// Uses random shuffling with optional seed for reproducibility
public struct DatasetSplitter {
    
    public struct SplitResult<T> {
        public let training: [T]
        public let validation: [T]
    }
    
    /// Split an array of items into train/val
    /// - Parameters:
    ///   - items: The items to split
    ///   - validationRatio: Percentage of items to use for validation (0.0 - 1.0)
    ///   - seed: Optional seed for shuffling (not implemented fully in Swift random yet without custom generator, utilizing simple shuffle for now)
    /// - Returns: SplitResult
    public static func split<T>(_ items: [T], validationRatio: Double) -> SplitResult<T> {
        guard !items.isEmpty else {
            return SplitResult(training: [], validation: [])
        }
        
        // Simple Shuffle
        var shuffled = items
        shuffled.shuffle() // Use SystemRandomNumberGenerator
        
        let valCount = Int(Double(items.count) * validationRatio)
        let trainCount = items.count - valCount
        
        let validation = Array(shuffled.prefix(valCount))
        let training = Array(shuffled.suffix(trainCount))
        
        return SplitResult(training: training, validation: validation)
    }
}
