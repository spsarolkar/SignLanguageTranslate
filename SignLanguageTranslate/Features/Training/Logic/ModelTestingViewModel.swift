import Foundation
import SwiftData
import Combine
import MLX

@MainActor
class ModelTestingViewModel: ObservableObject {
    
    // MARK: - Published State
    
    @Published var isTesting = false
    @Published var progress: Double = 0
    @Published var totalTestSamples = 0
    @Published var processedSamples = 0
    @Published var correctPredictions = 0
    @Published var accuracy: Double = 0.0
    @Published var testResults: [TestResult] = []
    @Published var showingError = false
    @Published var errorMessage = ""
    
    // Single Input Test State
    @Published var currentTestSample: VideoSample?
    @Published var singlePrediction: InferenceEngine.Prediction?
    @Published var isPredictingSingle = false
    
    // Checkpoints
    @Published var availableCheckpoints: [ModelPersistence.CheckpointInfo] = []
    @Published var selectedCheckpoint: ModelPersistence.CheckpointInfo?
    
    // MARK: - Properties
    
    private let inferenceEngine: InferenceEngine
    private let modelsDirectory: URL?
    
    struct TestResult: Identifiable {
        let id = UUID()
        let sampleId: UUID
        let expectedLabel: String
        let predictedLabel: String
        let confidence: Float
        let isCorrect: Bool
    }
    
    // MARK: - Initialization
    
    init(inferenceEngine: InferenceEngine, modelsDirectory: URL? = nil) {
        self.inferenceEngine = inferenceEngine
        self.modelsDirectory = modelsDirectory
    }
    
    // MARK: - Actions
    
    func fetchCheckpoints() async {
        guard let modelsDirectory = modelsDirectory else {
            print("[ModelTestingViewModel] No modelsDirectory provided.")
            return
        }
        
        print("[ModelTestingViewModel] Fetching checkpoints from: \(modelsDirectory.path)")
        
        // Ensure directory exists (create if needed, though usually it should exist)
        // If it doesn't exist, listCheckpoints will just return empty, but let's check
        if !FileManager.default.fileExists(atPath: modelsDirectory.path) {
            print("[ModelTestingViewModel] Directory does not exist: \(modelsDirectory.path)")
        }
        
        let persistence = ModelPersistence(modelsDirectory: modelsDirectory)
        let checkpoints = await persistence.listCheckpoints()
        
        print("[ModelTestingViewModel] Found \(checkpoints.count) checkpoints.")
        
        await MainActor.run {
            self.availableCheckpoints = checkpoints
            // Default to latest if not set
            if self.selectedCheckpoint == nil {
                self.selectedCheckpoint = checkpoints.first
            }
        }
        
        // Auto-load the selected checkpoint if available and engine not loaded
        if let first = checkpoints.first {
            print("[ModelTestingViewModel] Auto-selecting first checkpoint: \(first.url.lastPathComponent)")
            if !inferenceEngine.isModelLoaded {
                print("[ModelTestingViewModel] Engine not loaded. Triggering loadCheckpoint.")
                await loadCheckpoint(first)
            } else {
                print("[ModelTestingViewModel] Engine already loaded. Skipping load.")
            }
        } else {
            print("[ModelTestingViewModel] No checkpoints to auto-load.")
        }
    }
    
    func loadCheckpoint(_ checkpoint: ModelPersistence.CheckpointInfo) async {
        print("[ModelTestingViewModel] loadCheckpoint called for: \(checkpoint.url.lastPathComponent)")
        do {
            try await inferenceEngine.loadModel(from: checkpoint.url)
            print("[ModelTestingViewModel] Successfully loaded checkpoint.")
            await MainActor.run {
                self.selectedCheckpoint = checkpoint
            }
        } catch {
            print("[ModelTestingViewModel] Error loading checkpoint: \(error)")
            await MainActor.run {
                self.errorMessage = "Failed to load checkpoint: \(error.localizedDescription)"
                self.showingError = true
            }
        }
    }
    
    func startEvaluation(modelContext: ModelContext) async {
        guard !isTesting else { return }
        guard inferenceEngine.isModelLoaded else {
            errorMessage = "Model not loaded. Please train or load a model first."
            showingError = true
            return
        }
        
        isTesting = true
        progress = 0
        processedSamples = 0
        correctPredictions = 0
        testResults = []
        
        do {
            // 1. Fetch test samples
            // Explicitly type the comparison variable
            let targetSplit: String? = "test"
            let descriptor = FetchDescriptor<VideoSample>(
                predicate: #Predicate<VideoSample> { sample in
                    sample.split == targetSplit
                }
            )
            let samples = try modelContext.fetch(descriptor)
            
            totalTestSamples = samples.count
            
            if totalTestSamples == 0 {
                // Fallback: if no split defined, take random 10%
                // In a real app, we should enforce splits
                let allDescriptor = FetchDescriptor<VideoSample>()
                let allSamples = try modelContext.fetch(allDescriptor)
                let testCount = max(1, Int(Double(allSamples.count) * 0.1))
                let randomSamples = Array(allSamples.shuffled().prefix(testCount))
                await runEvaluation(on: randomSamples)
            } else {
                await runEvaluation(on: samples)
            }
            
        } catch {
            errorMessage = "Failed to fetch samples: \(error.localizedDescription)"
            showingError = true
        }
        
    }
    
    // MARK: - Single Sample Testing
    
    func pickRandomOneOffSample(modelContext: ModelContext) {
        do {
            // Predicate for test split (explicitly using Optional(string))
            let targetSplit: String? = "test"
            let descriptor = FetchDescriptor<VideoSample>(
                predicate: #Predicate<VideoSample> { sample in
                    sample.split == targetSplit
                }
            )
            let samples = try modelContext.fetch(descriptor)
            
            if let random = samples.randomElement() {
                self.currentTestSample = random
                self.singlePrediction = nil
            } else {
                errorMessage = "No test samples found in database."
                showingError = true
            }
        } catch {
            errorMessage = "Failed to fetch sample: \(error.localizedDescription)"
            showingError = true
        }
    }
    
    func testSingleSample() async {
        guard let sample = currentTestSample else { return }
        guard inferenceEngine.isModelLoaded else {
            errorMessage = "Model not loaded."
            showingError = true
            return
        }

        isPredictingSingle = true
        defer { isPredictingSingle = false }

        print("[ModelTesting] Testing sample: \(sample.fileName)")

        do {
            // 1. Load features from the sample's feature set
            guard let featureSet = sample.featureSets.first(where: {
                $0.modelName.localizedCaseInsensitiveContains("vision") ||
                $0.modelName.localizedCaseInsensitiveContains("mediapipe")
            }) else {
                await MainActor.run {
                    self.errorMessage = "No feature set found for sample"
                    self.showingError = true
                }
                return
            }

            // Resolve feature file path
            let featureURL = FileManager.default.datasetsDirectory.appendingPathComponent(featureSet.filePath)

            guard FileManager.default.fileExists(atPath: featureURL.path) else {
                await MainActor.run {
                    self.errorMessage = "Feature file not found: \(featureURL.lastPathComponent)"
                    self.showingError = true
                }
                return
            }

            // Load frame features
            let data = try Data(contentsOf: featureURL)
            let frames = try JSONDecoder().decode([FrameFeatures].self, from: data)

            guard !frames.isEmpty else {
                await MainActor.run {
                    self.errorMessage = "No frames found in feature file"
                    self.showingError = true
                }
                return
            }

            // 2. Load vocabulary from sample's label
            let expectedLabel = sample.wordName ?? sample.labels.first?.name ?? "Unknown"
            await inferenceEngine.addLabel(expectedLabel)

            // 3. Run actual inference
            let prediction = try await inferenceEngine.predict(frames: frames, topK: 5)

            await MainActor.run {
                self.singlePrediction = prediction
            }

            print("[ModelTesting] Prediction: \(prediction.label) (\(prediction.confidence)%) Expected: \(expectedLabel)")

        } catch {
            await MainActor.run {
                self.errorMessage = "Inference failed: \(error.localizedDescription)"
                self.showingError = true
            }
        }
    }
    
    private func runEvaluation(on samples: [VideoSample]) async {
        totalTestSamples = samples.count

        // Ensure vocabulary is loaded with all unique labels
        let uniqueLabels = Set(samples.compactMap { $0.wordName ?? $0.labels.first?.name })
        await inferenceEngine.addLabels(Array(uniqueLabels))

        for sample in samples {
            guard let expectedLabel = sample.wordName ?? sample.labels.first?.name else {
                await MainActor.run {
                    self.processedSamples += 1
                    self.progress = Double(self.processedSamples) / Double(self.totalTestSamples)
                }
                continue
            }

            // Find feature set
            guard let featureSet = sample.featureSets.first(where: {
                $0.modelName.localizedCaseInsensitiveContains("vision") ||
                $0.modelName.localizedCaseInsensitiveContains("mediapipe")
            }) else {
                await MainActor.run {
                    self.processedSamples += 1
                    self.progress = Double(self.processedSamples) / Double(self.totalTestSamples)
                }
                continue
            }

            // Load features from file
            let featureURL = FileManager.default.datasetsDirectory.appendingPathComponent(featureSet.filePath)

            guard FileManager.default.fileExists(atPath: featureURL.path) else {
                await MainActor.run {
                    self.processedSamples += 1
                    self.progress = Double(self.processedSamples) / Double(self.totalTestSamples)
                }
                continue
            }

            do {
                let data = try Data(contentsOf: featureURL)
                let frames = try JSONDecoder().decode([FrameFeatures].self, from: data)

                guard !frames.isEmpty else {
                    await MainActor.run {
                        self.processedSamples += 1
                        self.progress = Double(self.processedSamples) / Double(self.totalTestSamples)
                    }
                    continue
                }

                // Run actual inference
                let prediction = try await inferenceEngine.predict(frames: frames, topK: 5)
                let isCorrect = prediction.label.lowercased() == expectedLabel.lowercased()

                // Store result
                let result = TestResult(
                    sampleId: sample.id,
                    expectedLabel: expectedLabel,
                    predictedLabel: prediction.label,
                    confidence: prediction.confidence,
                    isCorrect: isCorrect
                )

                await MainActor.run {
                    self.testResults.append(result)
                    if isCorrect { self.correctPredictions += 1 }
                    self.processedSamples += 1
                    self.progress = Double(self.processedSamples) / Double(self.totalTestSamples)

                    if self.processedSamples > 0 {
                        self.accuracy = Double(self.correctPredictions) / Double(self.processedSamples) * 100
                    }
                }

            } catch {
                print("[ModelTesting] Error processing sample \(sample.id): \(error)")
                await MainActor.run {
                    self.processedSamples += 1
                    self.progress = Double(self.processedSamples) / Double(self.totalTestSamples)
                }
            }
        }

        await MainActor.run {
            self.isTesting = false
            print("[ModelTesting] Evaluation complete: \(self.correctPredictions)/\(self.processedSamples) correct (\(String(format: "%.1f", self.accuracy))%)")
        }
    }
}
