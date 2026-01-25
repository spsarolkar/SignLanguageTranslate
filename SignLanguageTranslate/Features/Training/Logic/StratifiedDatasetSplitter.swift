import Foundation
import SwiftData

/// Utility for performing stratified splits on the dataset
public struct StratifiedDatasetSplitter {
    
    public enum SplitType: String {
        case train = "train"
        case validation = "validation"
        case test = "test"
    }
    
    /// Perform a stratified split and update the samples in the database
    /// - Parameters:
    ///   - context: The ModelContext to save changes
    ///   - trainRatio: Percentage for Training (e.g., 0.8)
    ///   - valRatio: Percentage for Validation (e.g., 0.1)
    ///   - testRatio: Percentage for Test (e.g., 0.1)
    public static func performSplit(
        context: ModelContext,
        trainRatio: Double,
        valRatio: Double,
        testRatio: Double
    ) throws {
        // Fetch all samples
        let descriptor = FetchDescriptor<VideoSample>()
        let allSamples = try context.fetch(descriptor)
        
        // Group by Stratification Key (Word Label or Category)
        // Prefer Word Label for detailed balance, fallback to Category
        let grouped = Dictionary(grouping: allSamples) { sample -> String in
            if let word = sample.wordName { return "word_\(word)" }
            if let cat = sample.categoryName { return "cat_\(cat)" }
            return "unknown"
        }
        
        var trainCount = 0
        var valCount = 0
        var testCount = 0
        
        // Process each group
        for (_, samples) in grouped {
            var shuffled = samples
            shuffled.shuffle()
            
            let total = samples.count
            let nTrain = Int(Double(total) * trainRatio)
            let nVal = Int(Double(total) * valRatio)
            // Test gets the rest to ensure sum = count
            // However, for small classes (<3 items), this logic needs safeguards.
            // Rule: Each non-empty group should ideally have representatives if possible, 
            // but strict stratification requires sufficient data.
            // Fallback: If total < 3, put all in Train? Or 1 in Train/Val?
            // Simple logic for now: Arithmetic split.
            
            // Assign Train
            for i in 0..<nTrain {
                shuffled[i].split = SplitType.train.rawValue
            }
            trainCount += nTrain
            
            // Assign Val
            for i in nTrain..<(nTrain + nVal) {
                if i < total {
                    shuffled[i].split = SplitType.validation.rawValue
                }
            }
            valCount += min(nVal, max(0, total - nTrain))
            
            // Assign Test
            for i in (nTrain + nVal)..<total {
                shuffled[i].split = SplitType.test.rawValue
            }
            testCount += max(0, total - (nTrain + nVal))
        }
        
        try context.save()
        print("[Splitter] Stratified Split Complete. Train: \(trainCount), Val: \(valCount), Test: \(testCount)")
    }
    
    /// Clear all split assignments
    public static func resetSplits(context: ModelContext) throws {
        let descriptor = FetchDescriptor<VideoSample>()
        let allSamples = try context.fetch(descriptor)
        for sample in allSamples {
            sample.split = nil
        }
        try context.save()
    }
}
