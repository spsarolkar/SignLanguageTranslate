import Foundation

/// Helper structure to manage dataset splits
struct SplitResult {
    let train: [VideoSample]
    let validation: [VideoSample]
}

/// Helper to split dataset into training and validation sets
enum ValidationSplitter {
    
    /// Splits the array of samples into training and validation
    /// - Parameters:
    ///   - samples: Complete list of video samples
    ///   - validationRatio: Ratio of validation set (default 0.2 i.e., 20%)
    ///   - stratified: If true, attempts to keep label distribution equal (simplest implementation: shuffle)
    /// - Returns: SplitResult containing train and validation arrays
    static func split(_ samples: [VideoSample], validationRatio: Double = 0.2, stratified: Bool = true) -> SplitResult {
        guard !samples.isEmpty else {
            return SplitResult(train: [], validation: [])
        }
        
        var processingSamples = samples
        
        if stratified {
            // A true stratified split groups by label and splits each group.
            // For now, a random shuffle is a robust approximation for large datasets.
            processingSamples.shuffle()
        }
        
        // Ensure at least 1 validation sample if enough data
        let totalCount = processingSamples.count
        let validationCount = max(1, Int(Double(totalCount) * validationRatio))
        
        // If dataset is tiny (1 item), just put it in train
        if totalCount == 1 {
            return SplitResult(train: processingSamples, validation: [])
        }
        
        let splitIndex = totalCount - validationCount
        let trainSamples = Array(processingSamples.prefix(splitIndex))
        let validationSamples = Array(processingSamples.suffix(validationCount))
        
        print("[Splitter] Total: \(totalCount) | Train: \(trainSamples.count) | Val: \(validationSamples.count)")
        
        return SplitResult(train: trainSamples, validation: validationSamples)
    }
}
