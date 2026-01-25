import Foundation
import UIKit
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
    // MARK: - Internal Components
    private var model: (any SignLanguageModelProtocol)?
    private var modelWrapper: SignLanguageModuleWrapper?
    private var optimizer: Adam?
    private var pipeline: TrainingDataPipeline?
    private var cancellables = Set<AnyCancellable>()
    private var isPaused: Bool = false
    private var shouldStop: Bool = false
    
    // MARK: - Callbacks
    public let callbackManager = CallbackManager()
    
    /// Early stopping configuration (set via UI)
    public var earlyStoppingPatience: Int = 10
    public var earlyStoppingEnabled: Bool = true
    
    /// Checkpoints directory
    private var checkpointsDirectory: URL {
        FileManager.default.documentsDirectory.appendingPathComponent("Checkpoints")
    }
    
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
        
        let model: any SignLanguageModelProtocol
        
        if config.useLegacyModel {
            log("Initializing Legacy LSTM Model (Keras reproduction mode)")
            // Match inputDim=180 (Apple Vision) to Legacy Architecture
            model = LegacySignLanguageModel(
                inputDim: 180,
                numClasses: 300, // FIX: Match dataset target embeddings (GloVe 300d) like Transformer
                hiddenDim: 32
            )
        } else {
            log("Initializing Transformer Model")
            model = SignLanguageModel(
                inputDim: 180,
                modelDim: 256,
                outputDim: 300, // FIX: Match dataset target embeddings (GloVe 300d)
                numLayers: 4,
                numHeads: 4,
                dropout: 0.1
            )
        }
        
        self.model = model
        
        // Wrap for optimizer
        let wrapper = SignLanguageModuleWrapper(model: model)
        self.modelWrapper = wrapper
        
        // Initialize Optimizer
        self.optimizer = Adam(learningRate: config.learningRate)
        
        log("Model prepared.")
        
        // Setup Callbacks
        await setupCallbacks()
        
        self.state = .idle
    }
    
    /// Setup training callbacks (EarlyStopping, ModelCheckpoint, etc.)
    private func setupCallbacks() async {
        await callbackManager.clear()
        
        // 1. EarlyStopping (if enabled)
        if earlyStoppingEnabled {
            let earlyStopping = EarlyStoppingCallback(
                patience: earlyStoppingPatience,
                minDelta: 0.0001,
                restoreBestWeights: true,
                monitor: "valLoss",
                mode: .min
            )
            await callbackManager.register(earlyStopping)
            log("Registered EarlyStopping callback (patience: \(earlyStoppingPatience))")
        }
        
        // 2. ModelCheckpoint (always enabled)
        let checkpoint = ModelCheckpointCallback(
            checkpointDirectory: checkpointsDirectory,
            saveBestOnly: true,
            monitor: "valLoss",
            mode: .min
        )
        await callbackManager.register(checkpoint)
        log("Registered ModelCheckpoint callback")
        
        // 3. LR Scheduler (Reduce on Plateau)
        let lrScheduler = LRSchedulerCallback(
            monitor: "valLoss",
            factor: 0.1,
            patience: 5,
            minLR: 1e-6,
            mode: .min
        ) { [weak self] newLR in
            guard let self = self else { return }
            self.optimizer?.learningRate = newLR
            self.log("📉 Learning rate reduced to \(newLR)")
        }
        await callbackManager.register(lrScheduler)
        log("Registered LRScheduler callback")
    }
    
    // MARK: - Control
    
    // MARK: - Persistence
    private var currentRun: TrainingRun?
    private var modelContext: ModelContext?

    public func startTraining(datasetPath: URL, modelContext: ModelContext, targetDatasetName: String? = nil) {
        guard state == .idle || state == .paused else { return }
        
        self.modelContext = modelContext
        self.shouldStop = false
        self.isPaused = false
        self.state = .training
        
        // Prevent screen sleep
        UIApplication.shared.isIdleTimerDisabled = true
        
        // Setup background observers
        setupBackgroundObservers()
        
        // Create new Run if starting fresh
        if self.currentRun == nil {
            let runName = config.useLegacyModel ? "Legacy Run \(Date().formatted(date: .omitted, time: .shortened))" : "Transformer Run \(Date().formatted(date: .omitted, time: .shortened))"
            let newRun = TrainingRun(
                name: runName,
                config: config,
                timestamp: Date(),
                status: "Running"
            )
            self.currentRun = newRun
            modelContext.insert(newRun)
            // Initial save
            try? modelContext.save() 
            log("Created Training Run: \(runName)")
        } else {
            // Resuming
            self.currentRun?.status = "Resumed"
        }
        
        if self.pipeline == nil {
            self.pipeline = TrainingDataPipeline(modelContext: modelContext)
        }
        
        // 1. Fetch and Prepare Data on MainActor
        do {
            log("Fetching training data...")
            var descriptor = FetchDescriptor<VideoSample>()
            if let targetName = targetDatasetName {
                log("Targeting Dataset: \(targetName)")
                descriptor = FetchDescriptor<VideoSample>(
                    predicate: #Predicate { $0.datasetName == targetName }
                )
            }
            let allSamples = try modelContext.fetch(descriptor)
            
            // Convert to lightweight struct for background processing
            let trainingSamples: [TrainingDataPipeline.SampleInfo] = allSamples.compactMap { sample in
                // FIX: Case-insensitive check to match "AppleVision"
                guard let featureSet = sample.featureSets.first(where: { 
                    $0.modelName.localizedCaseInsensitiveContains("vision") || 
                    $0.modelName.localizedCaseInsensitiveContains("mediapipe") 
                }) else {
                    return nil
                }
                
                // Validate file existence
                // FIX: Use FeatureFileManager logic to resolve relative path to absolute URL
                let relativePath = featureSet.filePath
                let url = FileManager.default.datasetsDirectory.appendingPathComponent(relativePath)
                
                guard FileManager.default.fileExists(atPath: url.path) else {
                    // File is missing despite record existing
                    return nil
                }

                guard let label = sample.labels.first,
                      let embedding = label.embedding else {
                    return nil
                }
                
                return TrainingDataPipeline.SampleInfo(
                    id: sample.id,
                    featurePath: url,
                    embedding: embedding,
                    split: sample.split
                )
            }
            
            // VERBOSE DEBUGGING
            if trainingSamples.isEmpty {
                 log("CRITICAL ERROR: No valid samples found out of \(allSamples.count).")
                 if let firstSample = allSamples.first {
                     log("Sample 0 Debug:")
                     log("- ID: \(firstSample.id)")
                     log("- Features count: \(firstSample.featureSets.count)")
                     if let fs = firstSample.featureSets.first {
                         log("- Feature Path (Raw): \(fs.filePath)")
                         let debugURL = FileManager.default.datasetsDirectory.appendingPathComponent(fs.filePath)
                         log("- Resolved URL: \(debugURL.path)")
                         log("- File Exists: \(FileManager.default.fileExists(atPath: debugURL.path))")
                         if !FileManager.default.fileExists(atPath: debugURL.path) {
                             // Try listing directory to see what's there
                             let parent = debugURL.deletingLastPathComponent()
                             if let contents = try? FileManager.default.contentsOfDirectory(atPath: parent.path) {
                                 log("- Dir contents: \(contents)")
                             } else {
                                 log("- Parent Dir not readable: \(parent.path)")
                             }
                         }
                     } else {
                         log("- No FeatureSets found.")
                     }
                     log("- Labels count: \(firstSample.labels.count)")
                 }
                 self.state = .failed
                 return
            }
            
            let skippedCount = allSamples.count - trainingSamples.count
            if skippedCount > 0 {
                log("Warning: Skipped \(skippedCount) samples (missing features/labels). Training with \(trainingSamples.count).")
            }
            // END DEBUGGING
            
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
        self.currentRun?.status = "Paused"
        // Persist metrics
        if let run = currentRun {
            run.metrics = self.metrics
            try? modelContext?.save()
        }
        log("Training paused.")
    }
    
    public func stopTraining() {
        self.shouldStop = true
        self.state = .completing
        self.currentRun?.status = "Stopping"
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
        
        // 1. Split Data logic
        var trainSamples: [TrainingDataPipeline.SampleInfo]
        var valSamples: [TrainingDataPipeline.SampleInfo]
        
        // Check if we have persisted splits
        let hasPersistedSplits = samples.contains { $0.split != nil }
        
        if hasPersistedSplits {
            trainSamples = samples.filter { $0.split == "train" }
            valSamples = samples.filter { $0.split == "validation" }
            
            // If explicit split resulted in empty training set (edge case), fallback or warn?
            // We assume user knows what they did if they ran the splitter.
            if trainSamples.isEmpty {
                log("Warning: Persisted split found but Training Set is empty! Falling back to random split.")
                let split = DatasetSplitter.split(samples, validationRatio: config.validationSplitRatio)
                trainSamples = split.training
                valSamples = split.validation
            } else {
                 log("Using Persisted Stratified Split.")
            }
        } else {
            // Fallback to random split
            let split = DatasetSplitter.split(samples, validationRatio: config.validationSplitRatio)
            trainSamples = split.training
            valSamples = split.validation
            log("Using Random Split (No persisted split found).")
        }
        
        await MainActor.run {
            self.log("Data Split: \(trainSamples.count) Training, \(valSamples.count) Validation")
        }
        
        // Configuration
        let batchSize = config.batchSize
        let epochs = config.epochs
        let validationInterval = config.validationInterval
        let augment = config.augmentData
        
        // Launch detached task for heavy MLX work
        await Task.detached(priority: .userInitiated) { [weak self, wrapper, optimizer, pipeline, trainSamples, valSamples] in
            guard let self = self else { return }
            
            // Define loss function
            func lossFn(m: SignLanguageModuleWrapper, x: MLXArray, y: MLXArray) -> MLXArray {
                let logits = m(x)
                return LossFunctions.cosineSimilarityLoss(predictions: logits, targets: y)
            }
            
            let lg = valueAndGrad(model: wrapper, lossFn)
            
            // CALLBACK: onTrainBegin
            if let run = await self.currentRun {
                await self.callbackManager.notifyTrainBegin(run: run)
            }
            
            var globalStep = 0
            
            for epoch in 1...epochs {
                if await self.shouldStopTraining { break }
                
                await self.updateEpochStart(epoch: epoch)
                
                var epochLoss: Float = 0
                var batchCount = 0
                
                // Stream Batches (Training)
                for await batch in await pipeline.batchStream(samples: trainSamples, batchSize: batchSize, augment: augment) {
                    
                    // Check Pause/Stop
                    while await self.isTrainingPaused {
                        try? await Task.sleep(nanoseconds: 100_000_000)
                        if await self.shouldStopTraining { break }
                    }
                    if await self.shouldStopTraining { break }
                    
                    // Optimization Step
                    let (loss, grads) = lg(wrapper, batch.inputs, batch.targets)
                    optimizer.update(model: wrapper, gradients: grads)
                    MLX.eval(wrapper, optimizer)
                    
                    let lossValue = loss.item(Float.self)
                    epochLoss += lossValue
                    batchCount += 1
                    globalStep += 1
                    
                    // Update Batch Metrics (Training Loss Only)
                    await self.updateBatchProgress(batchIndex: batchCount, loss: lossValue)
                    
                    // Validation Check
                    if globalStep % validationInterval == 0 && !valSamples.isEmpty {
                        // Run Validation
                        let valLoss = await self.runValidation(pipeline: pipeline, samples: valSamples, wrapper: wrapper)
                        
                        // Update Metric with Validation Loss
                        // We append a new metric or update the last one?
                        // Better to append a distinct event or update the state so UI sees it.
                        await self.reportValidationMetric(loss: valLoss, step: batchCount, epoch: epoch)
                    }
                }
                
                // Epoch Validation (Force run at end of epoch)
                let avgLoss = batchCount > 0 ? epochLoss / Float(batchCount) : 0
                
                var finalValLoss: Float = 0.0
                if !valSamples.isEmpty {
                     finalValLoss = await self.runValidation(pipeline: pipeline, samples: valSamples, wrapper: wrapper)
                     // FIX: Report validation metric at end of epoch so graph updates every epoch
                     await self.reportValidationMetric(loss: finalValLoss, step: globalStep, epoch: epoch)
                }
                
                await self.logEpochCompletion(epoch: epoch, trainLoss: avgLoss, valLoss: finalValLoss)
                
                // CALLBACK: onEpochEnd
                if let run = await self.currentRun {
                    let epochMetrics = EpochMetrics(
                        epoch: epoch,
                        trainLoss: avgLoss,
                        valLoss: finalValLoss > 0 ? finalValLoss : nil,
                        trainAccuracy: nil,
                        valAccuracy: nil,
                        epochDuration: 0, // TODO: Track actual duration
                        timestamp: Date(),
                        savedCheckpoint: false,
                        batches: [] // TODO: Collect batch metrics if needed
                    )
                    
                    let action = await self.callbackManager.notifyEpochEnd(
                        epoch: epoch,
                        metrics: epochMetrics,
                        run: run
                    )
                    
                    // Handle early stopping
                    if case .stopTraining(let reason) = action {
                        await self.log("Early stopping: \(reason)")
                        await MainActor.run { self.shouldStop = true }
                        break
                    }
                }
            }
            
            await self.finishSession()
        }.value
    }
    
    // Internal validation runner (runs on background task)
    private func runValidation(pipeline: TrainingDataPipeline, samples: [TrainingDataPipeline.SampleInfo], wrapper: SignLanguageModuleWrapper) async -> Float {
        var totalLoss: Float = 0
        var count = 0
        
        // No Augmentation, No Shuffle
        for await batch in await pipeline.batchStream(samples: samples, batchSize: config.batchSize, shuffle: false, augment: false) {
             let logits = wrapper(batch.inputs)
             let loss = LossFunctions.cosineSimilarityLoss(predictions: logits, targets: batch.targets)
             totalLoss += loss.item(Float.self)
             count += 1
        }
        
        return count > 0 ? totalLoss / Float(count) : 0
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
        
        let metric = TrainingMetrics(
            epoch: currentEpoch,
            batchIndex: batchIndex,
            trainingLoss: loss,
            validationLoss: nil, // Only training loss for this step
            timestamp: Date()
        )
        self.metrics.append(metric)
        
        // Update Run periodically (every 10 batches)
        if batchIndex % 10 == 0 {
             self.currentRun?.metrics = self.metrics
        }
    }
    
    private func reportValidationMetric(loss: Float, step: Int, epoch: Int) {
        // We add a special metric point for validation, or attach it to the latest?
        // Charts usually expect x-axis alignment.
        // We can just emit a metric with nil training loss? No, chart might break.
        // We attach it to the current step.
        // Let's modify the LAST metric if it exists.
        if !self.metrics.isEmpty {
            var last = self.metrics.removeLast()
            // Re-create with validation loss
            let updated = TrainingMetrics(
                epoch: last.epoch,
                batchIndex: last.batchIndex,
                trainingLoss: last.trainingLoss,
                validationLoss: loss,
                timestamp: last.timestamp
            )
            self.metrics.append(updated)
            // Log
            // self.log("Validation: \(String(format: "%.4f", loss))")
        }
    }
    
    private func logEpochCompletion(epoch: Int, trainLoss: Float, valLoss: Float) {
        self.log("Epoch \(epoch) finished. Train: \(String(format: "%.4f", trainLoss)) | Val: \(String(format: "%.4f", valLoss))")
        
        // Force save
        if let run = currentRun {
            run.metrics = self.metrics
            try? modelContext?.save()
        }
    }
    
    private func finishSession() {
        if !shouldStop {
            self.state = .completed
            self.currentRun?.status = "Completed"
            self.log("Training session finished.")
        } else {
            self.state = .idle
            self.currentRun?.status = "Stopped"
            self.log("Training stopped.")
        }
        
        // Re-enable screen sleep
        UIApplication.shared.isIdleTimerDisabled = false
        
        // Final Save
        if let run = currentRun {
            run.metrics = self.metrics
            run.duration = Date().timeIntervalSince(run.timestamp)
            try? modelContext?.save()
            
            // CALLBACK: onTrainEnd
            Task {
                await callbackManager.notifyTrainEnd(run: run)
            }
        }
        
        self.currentRun = nil
    }
    
    // MARK: - Background Processing
    
    private func setupBackgroundObservers() {
        NotificationCenter.default.addObserver(forName: .trainingShouldSaveAndStop, object: nil, queue: .main) { [weak self] _ in
            self?.saveAndStop()
        }
        
        NotificationCenter.default.addObserver(forName: .trainingResumeInBackground, object: nil, queue: .main) { [weak self] _ in
            self?.resumeFromBackground()
        }
    }
    
    /// Called when BG processing task is expiring.
    private func saveAndStop() {
        log("⚠️ BG Task Expiring! Saving resume checkpoint...")
        
        // Save minimal state to resume later
        saveResumeCheckpoint()
        
        // Stop the loop
        self.shouldStop = true
        
        // Force flush metrics
        if let run = currentRun {
            run.metrics = self.metrics
            try? modelContext?.save()
        }
    }
    
    /// Called when BG processing task starts.
    private func resumeFromBackground() {
        log("🔄 Resuming from background...")
        
        // If we have a resume checkpoint, load it
        // Note: For full robustness, we should use 'loadResumeCheckpoint()' 
        // to restore weights/optimizer before calling startTraining.
        // However, startTraining re-initializes models unless we implement dedicated restore logic.
        // For now, we rely on the fact that if app was suspended, memory is intact.
        // If app was terminated, we need to load weights.
        
        if self.state == .idle || self.state == .paused {
             // Just trigger start
             // self.isPausedRef = false // If we had one
             // We need to re-call startTraining?
             // Since we don't have the datasetPath handy here (unless stored), this is tricky.
             // We'll rely on stored config/state if possible.
             
             // HACK: For now, we assume app suspended so we just unpause if needed
             if self.state == .paused {
                 self.isPaused = false
                 self.state = .training
                 log("Resumed from pause.")
             } else {
                 log("App was idle. Can't auto-start without dataset path context yet.")
             }
        }
    }
    
    private func saveResumeCheckpoint() {
        // Save "resume.safetensors"
        guard let wrapper = self.modelWrapper else { return }
        let url = checkpointsDirectory.appendingPathComponent("resume.safetensors")
        do {
            let arrays = Dictionary(uniqueKeysWithValues: wrapper.parameters().flattened())
            try save(arrays: arrays, url: url)
            log("Saved resume checkpoint to \(url.lastPathComponent)")
        } catch {
            log("Failed to save resume checkpoint: \(error)")
        }
    }
    
    // MARK: - Helpers
    
    private func log(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        print("[\(timestamp)] [Training] \(message)")
        logs.append("[\(timestamp)] \(message)")
    }
}
