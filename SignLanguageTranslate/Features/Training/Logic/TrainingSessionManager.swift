import Foundation
import Combine
import MLX
import MLXNN
import MLXOptimizers
import SwiftData

// Helper wrapper (moved to SignLanguageModuleWrapper.swift)


@MainActor
public class TrainingSessionManager: ObservableObject {
    
    // MARK: - Published State
    @Published public var state: TrainingState = .idle
    @Published public var metrics: [TrainingMetrics] = []
    @Published public var currentEpoch: Int = 0
    @Published public var currentBatch: Int = 0
    @Published public var progress: Double = 0.0
    @Published public var logs: [String] = []
    @Published public var lastLoss: Float = 0.0
    
    // MARK: - Configuration
    public var config: TrainingConfig
    
    // MARK: - Internal Components
    private var model: SignLanguageModel?
    private var modelWrapper: SignLanguageModuleWrapper?
    private var optimizer: Adam?
    private var pipeline: TrainingDataPipeline?
    private var cancellables = Set<AnyCancellable>()
    private var isPaused: Bool = false
    private var shouldStop: Bool = false
    
    // MARK: - Init
    public init(config: TrainingConfig) {
        self.config = config
    }
    
    public convenience init() {
        self.init(config: .default)
    }
    
    // MARK: - Setup
    
    public func prepare() async {
        self.state = .preparing
        log("Preparing training session...")
        
        let model = SignLanguageModel(
            inputDim: 180,
            modelDim: 256,
            outputDim: 384,
            numLayers: 4,
            numHeads: 4,
            dropout: 0.1
        )
        self.model = model
        
        // Wrap for optimizer
        let wrapper = SignLanguageModuleWrapper(model: model)
        self.modelWrapper = wrapper
        
        // Initialize Optimizer
        self.optimizer = Adam(learningRate: config.learningRate)
        
        log("Model prepared.")
        self.state = .idle
    }
    
    // MARK: - Control
    
    public func startTraining(datasetPath: URL, modelContext: ModelContext) {
        guard state == .idle || state == .paused else { return }
        
        self.shouldStop = false
        self.isPaused = false
        self.state = .training
        
        if self.pipeline == nil {
            self.pipeline = TrainingDataPipeline(modelContext: modelContext)
        }
        
        // 1. Fetch and Prepare Data on MainActor
        do {
            log("Fetching training data...")
            let descriptor = FetchDescriptor<VideoSample>()
            let allSamples = try modelContext.fetch(descriptor)
            
            // Convert to lightweight struct for background processing
            let trainingSamples: [TrainingDataPipeline.SampleInfo] = allSamples.compactMap { sample in
                guard let featureSet = sample.featureSets.first(where: { $0.modelName.contains("vision") || $0.modelName.contains("mediapipe") }),
                      let label = sample.labels.first,
                      let embedding = label.embedding else {
                    return nil
                }
                return TrainingDataPipeline.SampleInfo(id: sample.id, featurePath: URL(fileURLWithPath: featureSet.filePath), embedding: embedding)
            }
            
            if trainingSamples.isEmpty {
                log("Error: No valid training samples found.")
                self.state = .failed
                return
            }
            
            log("Found \(trainingSamples.count) samples. Starting training...")
            
            // 2. Launch Background Training
            Task {
                await runTrainingLoop(samples: trainingSamples)
            }
        } catch {
            log("Error fetching data: \(error)")
            self.state = .failed
        }
    }
    
    public func pauseTraining() {
        self.isPaused = true
        self.state = .paused
        log("Training paused.")
    }
    
    public func stopTraining() {
        self.shouldStop = true
        self.state = .completing
        log("Stopping training...")
    }
    
    // MARK: - Training Loop
    
    private func runTrainingLoop(samples: [TrainingDataPipeline.SampleInfo]) async {
        guard let wrapper = self.modelWrapper,
              let optimizer = self.optimizer,
              let pipeline = self.pipeline else {
            log("Error: Components not initialized.")
            self.state = .failed
            return
        }
        
        // Configuration
        let batchSize = config.batchSize
        let epochs = config.epochs
        let validationInterval = config.validationInterval
        
        // Launch detached task for heavy MLX work
        // We capture 'self' weakly to update UI, and necessary components strongly.
        await Task.detached(priority: .userInitiated) { [weak self, wrapper, optimizer, pipeline, samples] in
            guard let self = self else { return }
            
            // Define loss function
            func lossFn(m: SignLanguageModuleWrapper, x: MLXArray, y: MLXArray) -> MLXArray {
                let logits = m(x)
                return LossFunctions.cosineSimilarityLoss(predictions: logits, targets: y)
            }
            
            let lg = valueAndGrad(model: wrapper, lossFn)
            
            for epoch in 1...epochs {
                if await self.shouldStopTraining { break }
                
                await self.updateEpochStart(epoch: epoch)
                
                var epochLoss: Float = 0
                var batchCount = 0
                
                // Stream Batches from Pipeline
                for await batch in await pipeline.batchStream(samples: samples, batchSize: batchSize) {
                    // Check Pause/Stop
                    while await self.isTrainingPaused {
                        try? await Task.sleep(nanoseconds: 100_000_000)
                        if await self.shouldStopTraining { break }
                    }
                    if await self.shouldStopTraining { break }
                    
                    // Optimization Step
                    let (loss, grads) = lg(wrapper, batch.inputs, batch.targets)
                    optimizer.update(model: wrapper, gradients: grads)
                    MLX.eval(wrapper, optimizer) // Check if this is needed or if loss.item handles it
                    
                    let lossValue = loss.item(Float.self)
                    epochLoss += lossValue
                    batchCount += 1
                    
                    // Update Batch Metrics
                    await self.updateBatchProgress(batchIndex: batchCount, loss: lossValue)
                }
                
                // Epoch Validation
                let avgLoss = batchCount > 0 ? epochLoss / Float(batchCount) : 0
                await self.logEpochCompletion(epoch: epoch, avgLoss: avgLoss)
            }
            
            await self.finishSession()
        }.value
    }
    
    // MARK: - Helpers (MainActor for UI)
    
    // Safe accessors for state
    private var shouldStopTraining: Bool { shouldStop }
    private var isTrainingPaused: Bool { isPaused }
    
    private func updateEpochStart(epoch: Int) {
        self.currentEpoch = epoch
        self.currentBatch = 0
        self.log("Epoch \(epoch) started.")
    }
    
    private func updateBatchProgress(batchIndex: Int, loss: Float) {
        self.currentBatch = batchIndex
        self.lastLoss = loss
        // Ideally calculate progress based on total batches if known
    }
    
    private func logEpochCompletion(epoch: Int, avgLoss: Float) {
        let metric = TrainingMetrics(epoch: epoch, batchIndex: 0, trainingLoss: avgLoss)
        self.metrics.append(metric)
        self.log("Epoch \(epoch) finished. Avg Loss: \(String(format: "%.4f", avgLoss))")
    }
    
    private func finishSession() {
        if !shouldStop {
            self.state = .completed
            self.log("Training session finished.")
        } else {
            self.state = .idle
            self.log("Training stopped.")
        }
    }
    
    // MARK: - Helpers
    
    private func log(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logs.append("[\(timestamp)] \(message)")
    }
}
