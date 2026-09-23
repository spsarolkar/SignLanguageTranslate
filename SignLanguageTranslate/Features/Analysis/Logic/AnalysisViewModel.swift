import Foundation
import SwiftData
import MLX
import Combine
import SwiftUI // For ObservableObject

@MainActor
class AnalysisViewModel: ObservableObject {
    
    // MARK: - State
    
    @Published var isAnalyzing = false
    @Published var progress: Double = 0
    @Published var result: FeatureAnalyzer.AnalysisResult?
    @Published var errorMessage: String?
    
    private let analyzer = FeatureAnalyzer()
    private var dataset: Dataset?
    
    // We need ModelContext to fetch videos since Dataset doesn't hold a reference
    // This will be passed from the View or via init if improved.
    // For now, let's assume we can pass it in startAnalysis or use a passed closure.
    // Actually, simpler: pass a closure or just fetch using the container if possible.
    // But View has the context. Let's add a parameter to startAnalysis.
    
    // MARK: - Public API
    
    func setcanDataset(_ dataset: Dataset) {
        self.dataset = dataset
        // Try load existing analysis
        loadAnalysis(for: dataset)
    }
    
    func startAnalysis(modelContext: ModelContext) {
        guard let dataset = dataset else { return }
        
        Task {
            isAnalyzing = true
            errorMessage = nil
            
            do {
                // Fetch FeatureSets on MainActor
                let featureSets = try await MainActor.run {
                    // Fetch all videos for this dataset
                    let datasetName = dataset.name
                    let descriptor = FetchDescriptor<VideoSample>(
                        predicate: #Predicate { $0.datasetName == datasetName }
                    )
                    let videos = try modelContext.fetch(descriptor)
                    
                    // Collect flat list of feature sets
                    // Prefer AppleVision, fallback to others
                    return videos.compactMap { video in
                        video.featureSets.first(where: { $0.modelName == "AppleVision" }) ?? video.featureSets.first
                    }
                }
                
                guard !featureSets.isEmpty else {
                    throw NSError(domain: "AnalysisViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "No features extracted for this dataset."])
                }
                
                let result = try await analyzer.analyze(featureSets: featureSets)
                self.result = result
                
                // Save to disk
                saveAnalysis(result, for: dataset)
                
            } catch {
                errorMessage = error.localizedDescription
            }
            
            isAnalyzing = false
        }
    }
    
    // MARK: - Persistence
    
    private struct PersistedAnalysis: Codable {
        let variances: [Float]
        let correlation: [Float]
        let mean: Float
        let std: Float
        let deadCount: Int
        let pcaPoints: [FeatureAnalyzer.Point]
    }
    
    private func saveAnalysis(_ result: FeatureAnalyzer.AnalysisResult, for dataset: Dataset) {
        let persisted = PersistedAnalysis(
            variances: result.featureVariances,
            correlation: result.correlationMatrix,
            mean: result.globalMean,
            std: result.globalStd,
            deadCount: result.deadFeatureCount,
            pcaPoints: result.pcaPoints
        )
        
        // Use storageDirectory
        let url = dataset.storageDirectory.appendingPathComponent("analysis.json")
        do {
            let data = try JSONEncoder().encode(persisted)
            try data.write(to: url)
        } catch {
            print("Failed to save analysis: \(error)")
        }
    }
    
    private func loadAnalysis(for dataset: Dataset) {
        let url = dataset.storageDirectory.appendingPathComponent("analysis.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        
        do {
            let data = try Data(contentsOf: url)
            let persisted = try JSONDecoder().decode(PersistedAnalysis.self, from: data)
            
            self.result = FeatureAnalyzer.AnalysisResult(
                featureVariances: persisted.variances,
                correlationMatrix: persisted.correlation,
                globalMean: persisted.mean,
                globalStd: persisted.std,
                deadFeatureCount: persisted.deadCount,
                pcaPoints: persisted.pcaPoints
            )
        } catch {
            print("Failed to load analysis: \(error)")
        }
    }
}
