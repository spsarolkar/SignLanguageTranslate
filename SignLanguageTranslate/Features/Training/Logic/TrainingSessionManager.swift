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

    // MARK: - Singleton

    /// Shared instance to persist training state across view navigations
    public static let shared = TrainingSessionManager()

    // MARK: - Types

    /// Represents a learning rate change event for chart annotation
    public struct LRChangeEvent: Identifiable, Sendable {
        public let id = UUID()
        public let epoch: Int
        public let batchIndex: Int
        public let oldLR: Float
        public let newLR: Float
        public let reason: String
        public let timestamp: Date

        public var description: String {
            "LR: \(String(format: "%.2e", oldLR)) → \(String(format: "%.2e", newLR))"
        }
    }

    // MARK: - Published State
    @Published public var state: TrainingState = .idle
    @Published public var metrics: [TrainingMetrics] = []
    @Published public var currentEpoch: Int = 0
    @Published public var currentBatch: Int = 0
    @Published public var progress: Double = 0.0
    @Published public var logs: [String] = []
    // NEW: Phase 8 Insights
    @Published public var currentInsight: TrainingAnalyzer.AnalysisResult?
    private let trainingAnalyzer = TrainingAnalyzer()
    @Published public var lastLoss: Float = 0.0
    /// Learning rate change events for chart annotation
    @Published public var lrChangeEvents: [LRChangeEvent] = []
    /// Current learning rate (updated by callbacks)
    @Published public var currentLearningRate: Float = 0
    @Published public private(set) var workPhase: TrainingWorkPhase = .idle
    @Published public private(set) var validationBatchesCompleted = 0
    private var phaseBeforePause: TrainingWorkPhase = .training

    public var activityDescription: String {
        if workPhase == .validating {
            return "Validating · \(validationBatchesCompleted) batches processed"
        }
        return workPhase.rawValue
    }

    public var hasLiveWorker: Bool { workerLifecycle.hasWorker }
    public var isPreparingCheckpoint: Bool { checkpointPreparationID != nil }
    private var checkpointPreparationID: UUID?

    // MARK: - Configuration
    public var config: TrainingConfig

    // MARK: - Internal Components
    private var model: (any SignLanguageModelProtocol)?
    private var modelWrapper: SignLanguageModuleWrapper?
    private var checkpointSpecification: CheckpointModelSpecification?
    private var optimizer: Adam?
    private var pipeline: TrainingDataPipeline?
    private var cancellables = Set<AnyCancellable>()
    private let workerLifecycle: TrainingWorkerLifecycle
    private let notificationCenter: NotificationCenter
    private var backgroundObserversInstalled = false
    private var resumeWhenForegrounded = false
    private var isPaused: Bool { workerLifecycle.isPaused }
    private var shouldStop: Bool { workerLifecycle.isStopping }

    // MARK: - Current Run Context (for resume)
    private var currentDatasetName: String?

    // MARK: - Callbacks
    public let callbackManager = CallbackManager()

    /// Early stopping configuration (set via UI)
    public var earlyStoppingEnabled: Bool = true

    /// Checkpoints directory
    private var checkpointsDirectory: URL {
        FileManager.default.documentsDirectory.appendingPathComponent("Checkpoints")
    }

    // MARK: - Init

    /// Private initializer to enforce singleton pattern
    private init() {
        self.config = .default
        self.workerLifecycle = TrainingWorkerLifecycle()
        self.notificationCenter = .default
    }

    /// For testing purposes only
    internal init(config: TrainingConfig, workerLifecycle: TrainingWorkerLifecycle? = nil,
                  notificationCenter: NotificationCenter = .default) {
        self.config = config
        self.workerLifecycle = workerLifecycle ?? TrainingWorkerLifecycle()
        self.notificationCenter = notificationCenter
    }

    nonisolated deinit {}
    
    // MARK: - Setup
    
    public func prepare() async {
        guard !workerLifecycle.hasWorker, !isPreparingCheckpoint else {
            log("A training operation already exists; preparation skipped.")
            return
        }
        self.state = .preparing
        log("Preparing training session...")
        
        // Allocate only after the real label mapping is available in startTraining.
        model = nil
        modelWrapper = nil
        optimizer = nil
        checkpointSpecification = nil
        currentRun = nil
        currentEpoch = 0
        currentBatch = 0
        metrics = []
        // Callbacks will be setup in startTraining once run name is known
        self.state = .idle
    }
    
    private func initializeModel(numClasses: Int, classNames: [String]) throws {
        log("Initializing model (Classes: \(numClasses), Loss: \(config.lossFunction.rawValue))...")
        
        // Force free existing MLX graphs/parameters before allocating new massive models
        self.model = nil
        self.modelWrapper = nil
        self.optimizer = nil
        
        let model: any SignLanguageModelProtocol
        if config.useLegacyModel {
            guard config.lossFunction != .crossEntropy else {
                throw CheckpointCompatibility.Error.incompatible("BiLSTM classification checkpoints are unsupported; use Transformer classification.")
            }
            model = LegacySignLanguageModel(inputDim: 180, numClasses: 384, hiddenDim: config.hiddenDim)
            checkpointSpecification = CheckpointModelSpecification(config: nil, classNames: [], family: "bilstm")
        } else {
            let effective = try CheckpointCompatibility.effectiveConfig(training: config, numClasses: numClasses)
            model = SignLanguageModel(config: effective)
            checkpointSpecification = CheckpointModelSpecification(config: effective,
                classNames: effective.outputMode == .classification ? classNames : [])
        }
        self.model = model
        self.modelWrapper = SignLanguageModuleWrapper(model: model)
        self.optimizer = Adam(learningRate: config.learningRate)
        log("Model initialized.")
    }
    

    
    /// Get the checkpoint directory for the current run
    public func getRunCheckpointDirectory(runName: String) -> URL {
        // Sanitize name for file system
        let safeName = runName.components(separatedBy: .init(charactersIn: "/\\?%*|\"<>:")).joined(separator: "_")
        return checkpointsDirectory.appendingPathComponent(safeName)
    }

    /// Setup training callbacks (Run specific)
    private func setupCallbacks(for runName: String) async {
        await callbackManager.clear()
        
        let runDir = getRunCheckpointDirectory(runName: runName)
        
        // 1. EarlyStopping (if enabled)
        if earlyStoppingEnabled {
            let earlyStopping = EarlyStoppingCallback(
                patience: config.patience,
                minDelta: 0.0001,
                restoreBestWeights: true,
                monitor: "valLoss",
                mode: .min
            )
            await callbackManager.register(earlyStopping)
            log("Registered EarlyStopping callback (patience: \(config.patience))")
        }
        
        // 2. ModelCheckpoint (Run Specific)
        let checkpoint = ModelCheckpointCallback(
            checkpointDirectory: runDir,
            saveBestOnly: true,
            monitor: "valLoss",
            mode: .min
        )
        
        // IMPORTANT: Wire up the actual weight saving
        checkpoint.onCheckpointSaved = { [weak self] url, epoch, val in
            guard let self = self, let wrapper = self.modelWrapper else { return }
            self.setWorkPhase(.checkpointing)
            self.log("Saving epoch \(epoch) checkpoint...")
            print("[TrainingSessionManager] Saving weights for epoch \(epoch)")
            // Use the callback's helper to save weights structure
            try checkpoint.saveModelWeights(wrapper.parameters(), epoch: epoch)
            self.setWorkPhase(.epochCallbacks)
            self.log("Epoch checkpoint callback finished.")
            // Sync status
            self.currentRun?.status = "Training (Best: \(String(format: "%.4f", val)))"
            try? self.modelContext?.save()
        }
        
        await callbackManager.register(checkpoint)
        log("Registered ModelCheckpoint callback at \(runDir.lastPathComponent)")
        
        // 3. LR Scheduler
        switch config.scheduler {
        case .cosineDecay:
            let cosineScheduler = CosineLRScheduler(
                baseLR: config.learningRate,
                totalEpochs: config.epochs,
                minLR: 1e-6,
                warmupEpochs: config.warmupEpochs,
                updateLR: { [weak self] newLR in
                    guard let self = self else { return }
                    Task { @MainActor in
                        self.optimizer?.learningRate = newLR
                        // Cosine updates every epoch silently, maybe allow verbose logs?
                        // self.log("Cosine Scheduler: LR -> \(newLR)") 
                    }
                },
                logger: { [weak self] msg in
                     Task { @MainActor in self?.log(msg) }
                }
            )
            await callbackManager.register(cosineScheduler)
            log("Registered CosineDecay Scheduler (Warmup: \(config.warmupEpochs))")
            
        case .reduceOnPlateau:
            let lrScheduler = LRSchedulerCallback(
                monitor: "valLoss",
                factor: 0.1,
                patience: config.patienceLR,
                minLR: 1e-6,
                mode: .min,
                onLog: { [weak self] msg in
                    Task { @MainActor in self?.log(msg) }
                }
            ) { [weak self] newLR in
                guard let self = self else { return }
                Task { @MainActor in
                    self.optimizer?.learningRate = newLR
                    self.log("📉 Learning rate reduced to \(newLR)")
                }
            }
            await callbackManager.register(lrScheduler)
            log("Registered ReduceOnPlateau Scheduler")
        }
    }
    
    // MARK: - Control

    // MARK: - Persistence
    private var currentRun: TrainingRun?
    private var modelContext: ModelContext?

    /// Public accessor for current run ID (used for stale run cleanup)
    public var currentRunId: UUID? {
        currentRun?.id
    }
    
    public var currentRunName: String? {
        currentRun?.name
    }
    
    public var currentRunCheckpointDirectory: URL? {
        guard let name = currentRun?.name else { return nil }
        return getRunCheckpointDirectory(runName: name)
    }
    
    /// Finds the most recently modified run directory in Checkpoints
    public var latestRunCheckpointDirectory: URL? {
        let fm = FileManager.default
        guard let validURLs = try? fm.contentsOfDirectory(
            at: checkpointsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey]
        ) else { return nil }
        
        // Filter for directories and sort by modification date (newest first)
        return validURLs
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false }
            .sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                return date1 > date2
            }
            .first
    }

    public func startTraining(datasetPath: URL, modelContext: ModelContext, targetDatasetName: String? = nil) {
        guard !isPreparingCheckpoint else {
            log("Checkpoint loading is still in progress; start skipped.")
            return
        }
        if state == .paused {
            resumeTraining()
            return
        }
        guard !workerLifecycle.hasWorker else {
            log("A training worker already exists; duplicate start ignored.")
            return
        }
        guard state == .idle else {
            log("Cannot start training while session is \(state.rawValue).")
            return
        }

        self.modelContext = modelContext
        self.currentDatasetName = targetDatasetName ?? "All" // Store for state persistence
        self.state = .training
        self.workPhase = .preparing

        // Prevent screen sleep
        UIApplication.shared.isIdleTimerDisabled = true

        // Setup background observers
        installBackgroundObservers()
        
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
            try? modelContext.save()
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
            

            
            // 2. Class Label Mapping (for Classification)
            var labelMap: [String: Int] = [:]
            let classNames = Set(allSamples.compactMap { $0.wordName }.filter { !$0.isEmpty }).sorted()
            if config.lossFunction == .crossEntropy {
                labelMap = Dictionary(uniqueKeysWithValues: classNames.enumerated().map { ($0.element, $0.offset) })
                log("Identified \(classNames.count) classes for classification.")
            }
            if checkpointSpecification == nil {
                try initializeModel(numClasses: classNames.count, classNames: classNames)
            } else if let specification = checkpointSpecification,
                      specification.config?.outputMode == .classification,
                      specification.classNames != classNames {
                throw CheckpointCompatibility.Error.incompatible("This dataset's class order differs from the saved classifier. Resume with its original dataset.")
            }
            if let run = currentRun { try persistEffectiveSpecification(for: run) }

            // Convert to lightweight struct
            let trainingSamples: [TrainingDataPipeline.SampleInfo] = allSamples.compactMap { sample -> TrainingDataPipeline.SampleInfo? in
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
                    return nil
                }

                // Get embedding for Contrastive
                guard let label = sample.labels.first,
                      let embedding = label.embedding else {
                    // For Classification, embedding might not be needed if not using contrastive loss, 
                    // but we keep consistent struct.
                    if config.lossFunction == .contrastive { return nil }
                    // If classification, we can survive without embedding IF we have a label index
                    // But SampleInfo requires embedding field. Pass empty or zero?
                    // Let's enforce embedding existence for now to avoid breaking other logic.
                     return nil
                }
                
                var labelIndex: Int? = nil
                if let name = sample.wordName, let idx = labelMap[name] {
                    labelIndex = idx
                }
                
                return TrainingDataPipeline.SampleInfo(
                    id: sample.id,
                    featurePath: url,
                    embedding: embedding,
                    labelIndex: labelIndex,
                    split: sample.split
                )
            }
            
            // Validate Classification Data
            if config.lossFunction == .crossEntropy {
                let validCount = trainingSamples.filter { $0.labelIndex != nil }.count
                if validCount < trainingSamples.count {
                     log("Warning: \(trainingSamples.count - validCount) samples missing label indices (wordName not in map).")
                }
                
                // Save classes.json
                if let run = self.currentRun {
                     let runDir = getRunCheckpointDirectory(runName: run.name)
                     let classesURL = runDir.appendingPathComponent("classes.json")
                     try? JSONEncoder().encode(classNames).write(to: classesURL)
                }
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
                 self.workPhase = .failed
                 UIApplication.shared.isIdleTimerDisabled = false
                 return
            }
            
            let skippedCount = allSamples.count - trainingSamples.count
            if skippedCount > 0 {
                log("Warning: Skipped \(skippedCount) samples (missing features/labels). Training with \(trainingSamples.count).")
            }
            // END DEBUGGING
            
            log("Found \(trainingSamples.count) samples. Starting training...")
            
            // CHECK: Continuation / Fine-tuning
            // 2. Launch Background Training
            workerLifecycle.start(onCompletion: { self.objectWillChange.send() }) {
                if let run = self.currentRun {
                    await self.setupCallbacks(for: run.name)
                }
                guard await self.workerLifecycle.waitUntilRunnable() else {
                    await self.finishSession()
                    return
                }
                // CHECK: Continuation / Fine-tuning (Async load inside Task)
                if let sourceRun = self.continuationSourceRun {
                    await MainActor.run { self.log("🔄 FINE-TUNING MODE: Initializing weights from run: \(sourceRun.name)") }
                    await self.loadWeightsForContinuation(sourceRun: sourceRun)
                }

                await self.runTrainingLoop(samples: trainingSamples)
            }
        } catch {
            log("Error fetching data: \(error)")
            self.state = .failed
            self.workPhase = .failed
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
    
    public func pauseTraining() {
        guard workerLifecycle.pause() else { return }
        phaseBeforePause = workPhase
        workPhase = .paused
        resumeWhenForegrounded = false
        self.state = .paused
        self.currentRun?.status = "Paused"
        // Persist metrics
        if let run = currentRun {
            run.metrics = self.metrics
            try? modelContext?.save()
        }
        log("Training paused.")
    }

    /// Resume the existing in-memory worker, without rebuilding data, model,
    /// optimizer, splits or callbacks, and without advancing the epoch.
    public func resumeTraining() {
        guard workerLifecycle.resume() else {
            log("No paused live worker to resume. Disk restoration is a separate action.")
            return
        }
        resumeWhenForegrounded = false
        state = .training
        workPhase = phaseBeforePause
        currentRun?.status = "Resumed"
        UIApplication.shared.isIdleTimerDisabled = true
        log("Resumed existing worker at epoch \(currentEpoch), batch \(currentBatch).")
    }
    
    public func stopTraining() {
        if isPreparingCheckpoint || (state == .preparing && !workerLifecycle.hasWorker) {
            checkpointPreparationID = nil
            state = .idle
            workPhase = .idle
            UIApplication.shared.isIdleTimerDisabled = false
            log("Checkpoint preparation stopped. Saved files were not changed.")
            return
        }
        guard workerLifecycle.stop() else { return }
        resumeWhenForegrounded = false
        self.state = .completing
        self.workPhase = .stopping
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
            self.workPhase = .failed
            UIApplication.shared.isIdleTimerDisabled = false
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
        let config = self.config // Capture struct copy for detached task
        let startEpoch = self.currentEpoch + 1 // Capture current epoch for resuming
        
        // Launch detached task for heavy MLX work
        await Task.detached(priority: .userInitiated) { [weak self, wrapper, optimizer, pipeline, trainSamples, valSamples, config] in
            guard let self = self else { return }
            
            // Define loss function with label smoothing support
            func lossFn(m: SignLanguageModuleWrapper, x: MLXArray, y: MLXArray) -> MLXArray {
                let logits = m(x)

                // Loss Function Selection
                if config.lossFunction == .contrastive {
                    return LossFunctions.contrastiveLoss(
                        predictions: logits,
                        targets: y,
                        temperature: config.contrastiveTemperature,
                        labelSmoothing: config.labelSmoothing
                    )
                } else if config.lossFunction == .crossEntropy {
                    // y contains indices in this case (passed as MLXArray)
                    // MLX cross_entropy expects logits [B, C] and targets [B] (indices)
                    return MLXNN.crossEntropy(logits: logits, targets: y, reduction: .mean)
                } else {
                    return LossFunctions.cosineSimilarityLoss(predictions: logits, targets: y)
                }
            }
            
            let lg = valueAndGrad(model: wrapper, lossFn)

            // CALLBACK: onTrainBegin
            if let run = await self.currentRun {
                await self.callbackManager.notifyTrainBegin(run: run)
            }

            var globalStep = 0
            let baseLR = config.learningRate
            let warmupEpochs = config.warmupEpochs
            let gradClipNorm = config.gradientClipping

            // Helper: Clip gradients by global norm
            // Returns the gradients unchanged - actual clipping was causing optimizer crashes
            // due to ModuleParameters structure issues. The contrastive loss naturally bounds gradients.
            func clipGradients(_ grads: ModuleParameters, maxNorm: Float) -> ModuleParameters {
                // Compute global norm for logging
                var totalNormSq: Float = 0
                for (_, arr) in grads.flattened() {
                    let normSq = (arr * arr).sum().item(Float.self)
                    totalNormSq += normSq
                }
                let globalNorm = sqrt(totalNormSq)

                if globalNorm > maxNorm {
                    #if DEBUG
                    print("[GradClip] Norm \(String(format: "%.2f", globalNorm)) > \(maxNorm) (not clipping to avoid optimizer issues)")
                    #endif
                }

                // Return unchanged - MLX's optimizer expects the original structure
                return grads
            }

            guard startEpoch <= epochs else {
                await self.log("Training already completed \(epochs) epochs. Nothing to do.")
                await self.finishSession()
                return
            }

            for epoch in startEpoch...epochs {
                guard await self.waitForTrainingWork() else { break }

                // Learning Rate Warmup
                if epoch <= warmupEpochs {
                    let warmupFactor = Float(epoch) / Float(warmupEpochs)
                    optimizer.learningRate = baseLR * warmupFactor
                    await MainActor.run {
                        self.log("Warmup LR: \(optimizer.learningRate)")
                    }
                }

                await self.updateEpochStart(epoch: epoch)

                var epochLoss: Float = 0
                var batchCount = 0

                // Stream Batches (Training)
                // Pass augment + temporalAugment
                for await batch in await pipeline.batchStream(
                    samples: trainSamples,
                    batchSize: batchSize,
                    augment: augment,
                    temporalAugment: config.enableTemporalAugmentation // Pass config
                ) {
                    
                    guard await self.waitForTrainingWork() else { break }
                    await self.setWorkPhase(.training)

                    // Autoreleasepool to ensure temporary tensors are freed
                    let batchMetric: (loss: Float, accuracy: Float) = await autoreleasepool {
                        // Optimization Step
                        // Choose targets based on loss function
                        let targetTensor: MLXArray
                        if config.lossFunction == .crossEntropy {
                             if let labels = batch.labels {
                                 targetTensor = labels
                             } else {
                                 // Should not happen if validation passed
                                 targetTensor = MLXArray.zeros([batchSize], type: Int32.self) // Fallback
                             }
                        } else {
                             targetTensor = batch.targets
                        }

                        let (loss, rawGrads) = lg(wrapper, batch.inputs, targetTensor)

                        // Apply gradient clipping
                        let grads = clipGradients(rawGrads, maxNorm: gradClipNorm)

                        optimizer.update(model: wrapper, gradients: grads)
                        
                        // Force evaluation of updates to free graph
                        MLX.eval(wrapper, optimizer, loss)
                        
                        let lossValue = loss.item(Float.self)
                        
                        // ACCURACY Tracking
                        // We need logits again? lossFn computed them but valueAndGrad hides them.
                        // To avoid re-computing forward pass (expensive), we could:
                        // 1. Return logits from lossFn (but valueAndGrad expects scalar).
                        // 2. Just re-compute for now (safer, less code refactor).
                        // Re-computing is fine for this scale if batch size is small.
                        let logits = wrapper(batch.inputs)
                        var accuracyValue: Float = 0.0
                        
                        if config.lossFunction == .contrastive || config.lossFunction == .cosine {
                            // Use Mean Cosine Similarity distance as the "Accuracy" metric 
                            // for continuous embedding spaces, since exact match is impossible
                            let sim = LossFunctions.cosineSimilarity(predictions: logits, targets: batch.targets)
                            accuracyValue = sim.item(Float.self)
                        } else if config.lossFunction == .crossEntropy {
                            if let labels = batch.labels {
                                // Argmax accuracy for fixed vocab classification
                                let preds = logits.argMax(axis: -1)
                                let match = preds .== labels
                                let acc = match.mean()
                                accuracyValue = acc.item(Float.self)
                            }
                        } else {
                            // Default to 0 if accuracy is not defined for the loss function
                            accuracyValue = 0.0
                        }
                        
                        // Explicitly free logits graph
                        MLX.eval(logits)
                        
                        return (lossValue, accuracyValue)
                    }
                    epochLoss += batchMetric.loss
                    batchCount += 1
                    globalStep += 1
                    await self.updateBatchProgress(batchIndex: batchCount, loss: batchMetric.loss,
                                                   accuracy: batchMetric.accuracy)
                    
                    // Validation Check
                    if globalStep % validationInterval == 0 && !valSamples.isEmpty {
                        // Run Validation
                        guard let (valLoss, valAcc) = await self.runValidation(pipeline: pipeline, samples: valSamples, wrapper: wrapper, config: config) else { break }
                        
                        // Update Metric with Validation Loss
                        await self.reportValidationMetric(loss: valLoss, accuracy: valAcc, step: batchCount, epoch: epoch)
                    }
                }
                guard await self.waitForTrainingWork() else { break }
                
                // Epoch Validation (Force run at end of epoch)
                let avgLoss = batchCount > 0 ? epochLoss / Float(batchCount) : 0
                
                var finalValLoss: Float = 0.0
                var finalValAcc: Float = 0.0
                if !valSamples.isEmpty {
                     guard let (vLoss, vAcc) = await self.runValidation(pipeline: pipeline, samples: valSamples, wrapper: wrapper, config: config) else { break }
                     finalValLoss = vLoss
                     finalValAcc = vAcc
                     // FIX: Report validation metric at end of epoch so graph updates every epoch
                     await self.reportValidationMetric(loss: finalValLoss, accuracy: finalValAcc, step: globalStep, epoch: epoch)
                }
                
                await self.logEpochCompletion(epoch: epoch, trainLoss: avgLoss, valLoss: finalValLoss)
                guard await self.waitForTrainingWork() else { break }
                await self.setWorkPhase(.epochCallbacks)
                
                // CALLBACK: onEpochEnd
                if let run = await self.currentRun {
                    let epochMetrics = EpochMetrics(
                        epoch: epoch,
                        trainLoss: avgLoss,
                        valLoss: finalValLoss > 0 ? finalValLoss : nil,
                        trainAccuracy: nil,
                        valAccuracy: finalValAcc > 0 ? finalValAcc : nil,
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
                        await self.stopTraining()
                        break
                    }
                }
            }
            
            await self.finishSession()
        }.value
    }
    
    // Internal validation runner (runs on background task)
    nonisolated private func runValidation(pipeline: TrainingDataPipeline, samples: [TrainingDataPipeline.SampleInfo], wrapper: SignLanguageModuleWrapper, config: TrainingConfig) async -> (loss: Float, accuracy: Float)? {
        var totalLoss: Float = 0
        var totalAcc: Float = 0
        var count = 0
        await self.beginValidation()
        
        // No Augmentation, No Shuffle
        for await batch in await pipeline.batchStream(samples: samples, batchSize: config.batchSize, shuffle: false, augment: false, temporalAugment: false) {
             guard await self.waitForTrainingWork() else { return nil }
             await self.setWorkPhase(.validating)
             let logits = wrapper(batch.inputs)
             if config.lossFunction == .contrastive {
                 let loss = LossFunctions.contrastiveLoss(predictions: logits, targets: batch.targets, temperature: config.contrastiveTemperature)
                 totalLoss += loss.item(Float.self)
                 
                 let acc = LossFunctions.cosineSimilarity(predictions: logits, targets: batch.targets)
                 totalAcc += acc.item(Float.self)
             } else if config.lossFunction == .crossEntropy {
                 if let labels = batch.labels {
                     let loss = MLXNN.crossEntropy(logits: logits, targets: labels, reduction: .mean)
                     totalLoss += loss.item(Float.self)
                     
                     let preds = logits.argMax(axis: -1)
                     let match = preds .== labels
                     let acc = match.mean()
                     totalAcc += acc.item(Float.self)
                 }
             } else {
                 let loss = LossFunctions.cosineSimilarityLoss(predictions: logits, targets: batch.targets)
                 totalLoss += loss.item(Float.self)
                 let acc = LossFunctions.cosineSimilarity(predictions: logits, targets: batch.targets)
                 totalAcc += acc.item(Float.self)
             }
             count += 1
             await self.reportValidationProgress(count)
        }
        
        let finalLoss = count > 0 ? totalLoss / Float(count) : 0
        let finalAcc = count > 0 ? totalAcc / Float(count) : 0
        return (finalLoss, finalAcc)
    }
    
    // MARK: - Helpers (MainActor for UI)
    
    private func waitForTrainingWork() async -> Bool {
        await workerLifecycle.waitUntilRunnable()
    }

    private func setWorkPhase(_ phase: TrainingWorkPhase) {
        if state == .training { workPhase = phase }
    }

    private func beginValidation() {
        validationBatchesCompleted = 0
        setWorkPhase(.validating)
        log("Validation started at epoch \(currentEpoch), batch \(currentBatch).")
    }

    private func reportValidationProgress(_ count: Int) {
        validationBatchesCompleted = count
    }
    
    private func updateEpochStart(epoch: Int) {
        setWorkPhase(.training)
        self.currentEpoch = epoch
        self.currentBatch = 0
        self.log("Epoch \(epoch) started.")

        // Check thermal state at start of each epoch
        checkThermalState()
    }

    /// Check device thermal state and log warnings
    private func checkThermalState() {
        let thermalState = ProcessInfo.processInfo.thermalState
        switch thermalState {
        case .serious:
            log("⚠️ Device is running hot. Training may be throttled.")
        case .critical:
            log("🔥 CRITICAL: Device is thermal throttling! Consider pausing training.")
        default:
            break
        }
    }
    
    private func updateBatchProgress(batchIndex: Int, loss: Float, accuracy: Float? = nil) {
        self.currentBatch = batchIndex
        self.lastLoss = loss
        
        let metric = TrainingMetrics(
            epoch: currentEpoch,
            batchIndex: batchIndex,
            trainingLoss: loss,
            validationLoss: nil, 
            accuracy: accuracy, // Store accuracy
            timestamp: Date()
        )
        self.metrics.append(metric)
        
        // Update Run periodically (every 10 batches)
        if batchIndex % 10 == 0 {
             self.currentRun?.metrics = self.metrics
        }
    }
    
    private func reportValidationMetric(loss: Float, accuracy: Float, step: Int, epoch: Int) {
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
                accuracy: accuracy, // Passed from validation
                timestamp: last.timestamp
            )
            self.metrics.append(updated)
        }
    }
    
    private func logEpochCompletion(epoch: Int, trainLoss: Float, valLoss: Float) {
        self.log("Epoch \(epoch) finished. Train: \(String(format: "%.4f", trainLoss)) | Val: \(String(format: "%.4f", valLoss))")
        
        // Analyze Training Health
        self.currentInsight = trainingAnalyzer.analyze(history: self.metrics)
        if let insight = self.currentInsight, insight.health != .healthy {
            self.log("Analysis: \(insight.health.rawValue) - \(insight.suggestions.first ?? "")")
        }
        
        // Force save
        if let run = currentRun {
            run.metrics = self.metrics
            run.logs = self.logs // Sync logs
            try? modelContext?.save()
        }
    }
    
    private func finishSession() async {
        if !shouldStop {
            self.state = .completed
            self.workPhase = .completed
            self.currentRun?.status = "Completed"
            self.log("Training session finished.")
        } else {
            self.state = .idle
            self.workPhase = .idle
            self.currentRun?.status = "Stopped"
            self.log("Training stopped.")
        }

        // Re-enable screen sleep
        UIApplication.shared.isIdleTimerDisabled = false

        // Final Save
        if let run = currentRun {
            run.metrics = self.metrics
            run.logs = self.logs // Save logs
            run.duration = Date().timeIntervalSince(run.timestamp)
            try? modelContext?.save()

            // CALLBACK: onTrainEnd
            await callbackManager.notifyTrainEnd(run: run)
        }

        // Clear persisted state since training completed/stopped normally
        clearPersistedState()

        self.currentRun = nil
        self.currentDatasetName = nil
        self.continuationSourceRun = nil // Clear fine-tuning source
    }
    
    // MARK: - Continuation / Fine-tuning
    
    /// The run being fine-tuned (if any)
    public var continuationSourceRun: TrainingRun?
    
    /// Prepares the session for fine-tuning based on a previous run
    public func prepareFineTuning(run: TrainingRun) {
        guard !workerLifecycle.hasWorker, !isPreparingCheckpoint else {
            log("Finish the live worker before preparing another run.")
            return
        }
        log("Preparing to fine-tune from run: \(run.name)")
        self.continuationSourceRun = run
        
        // Pre-fill config from previous run, but keep new defaults for experimentation?
        // Usually fine-tuning implies LOWER learning rate and fewer epochs.
        if let oldConfig = run.config {
            self.config = oldConfig
            // Suggest lower LR
            self.config.learningRate = oldConfig.learningRate * 0.1
            // Suggest small epoch count
            self.config.epochs = 10
            // Reset patience?
            self.config.patience = 5
        }
    }
    
    private func loadWeightsForContinuation(sourceRun: TrainingRun) async {
        guard let wrapper = self.modelWrapper else { return }
        
        // Try to find the best checkpoint
        // Path: Documents/Checkpoints/<RunName>/best.safetensors (or epoch_X)
        // We used ModelCheckpoint callback which saves to run-specific folder.
        
        let runDir = getRunCheckpointDirectory(runName: sourceRun.name)
        
        // Use ModelPersistence to handle reading the checkpoint directory
        let persistence = ModelPersistence(modelsDirectory: runDir)
        
        do {
            // Try to load "best" first, then latest
            var result = try await persistence.loadBestModel()
            if result == nil {
                result = try await persistence.loadLatestCheckpoint()
            }
            
            if let (loadedModel, _, _) = result {
                log("Restoring weights from checkpoint...")
                
                // Update current wrapper with loaded parameters
                // loadedModel is SignLanguageModel, need to ensure type compatibility
                // We assume loadedModel is same architecture as self.model
                
                let loadedWrapper = SignLanguageModuleWrapper(model: loadedModel)
                wrapper.update(parameters: loadedWrapper.parameters())
                
                log("Weights restored successfully.")
            } else {
                log("⚠️ No valid checkpoint found in \(runDir.path)")
            }
        } catch {
            log("Failed to load continuation weights: \(error)")
        }
    }
    
    // MARK: - Background Processing
    
    internal func installBackgroundObservers() {
        guard !backgroundObserversInstalled else { return }
        backgroundObserversInstalled = true
        notificationCenter.publisher(for: .trainingShouldSaveAndStop).sink { @Sendable [weak self] _ in
            Task { @MainActor in await self?.saveAndStop() }
        }.store(in: &cancellables)

        notificationCenter.publisher(for: .trainingResumeInBackground).sink { @Sendable [weak self] _ in
            Task { @MainActor in self?.resumeFromBackground() }
        }.store(in: &cancellables)
    }
    
    /// Called when BG processing task is expiring or app goes to background.
    private func saveAndStop() async {
        guard workerLifecycle.hasWorker, state == .training || state == .paused else { return }
        let wasUserPaused = state == .paused && !resumeWhenForegrounded
        if !isPaused { phaseBeforePause = workPhase }
        workerLifecycle.pause()
        resumeWhenForegrounded = !wasUserPaused
        state = .paused
        workPhase = .paused
        log("⚠️ Saving training state...")

        // Never snapshot live parameters concurrently with an update. If the
        // worker is stuck inside a GPU operation, preserve the previous file.
        let acknowledged = await workerLifecycle.waitUntilPaused()
        // Resume/Stop may have arrived while this task awaited acknowledgement.
        // Recheck synchronously on MainActor immediately before reading weights.
        let parked = acknowledged && workerLifecycle.isPaused && workerLifecycle.isParked && !workerLifecycle.isStopping
        if parked {
            saveResumeCheckpoint()
            saveTrainingState()
        } else {
            log("Worker did not reach a safe pause boundary; previous checkpoint preserved.")
        }

        // Force flush metrics to SwiftData
        if let run = currentRun {
            run.metrics = self.metrics
            run.logs = self.logs // Sync logs
            try? modelContext?.save()
        }

        log(parked ? "Background save callback finished; live worker remains paused." : "Pause requested; no new weight checkpoint was written.")
    }

    /// Called when BG processing task starts or app returns to foreground.
    private func resumeFromBackground() {
        log("🔄 Attempting to resume training...")

        // If already training, nothing to do
        if self.state == .training && !self.isPaused {
            log("Training already active, no action needed")
            return
        }

        if workerLifecycle.hasWorker, isPaused {
            guard resumeWhenForegrounded else {
                log("Training was paused by the user; waiting for explicit Resume.")
                return
            }
            resumeTraining()
            return
        }

        // If idle, check for persisted state to restore
        if self.state == .idle {
            log("App was idle. Checking for resumable session...")
            // Note: Full restoration requires modelContext which we may not have here
            // The TrainingDashboardView will handle full restoration when it appears
        }
    }

    /// Save full training state to disk for recovery after app termination
    private func saveTrainingState() {
        guard let run = currentRun,
              let datasetName = currentDatasetName else {
            log("No active run to save state for")
            return
        }

        let persistedState = TrainingStatePersistence.PersistedState(
            runId: run.id,
            runName: run.name,
            currentEpoch: currentEpoch,
            currentBatch: currentBatch,
            globalStep: currentBatch, // Approximate
            config: config,
            datasetName: datasetName,
            lastTrainingLoss: lastLoss,
            lastValidationLoss: metrics.last(where: { $0.validationLoss != nil })?.validationLoss,
            metricsCount: metrics.count,
            startedAt: run.timestamp,
            lastCheckpointAt: Date(),
            wasTraining: state == .training,
            wasPaused: isPaused
        )

        TrainingStatePersistence.shared.save(persistedState)
    }

    private func saveResumeCheckpoint() {
        // Save model weights to "resume.safetensors"
        guard let wrapper = self.modelWrapper else { return }

        // Ensure checkpoint directory exists
        try? FileManager.default.createDirectory(at: checkpointsDirectory, withIntermediateDirectories: true)

        let url = checkpointsDirectory.appendingPathComponent("resume.safetensors")
        do {
            let arrays = Dictionary(uniqueKeysWithValues: wrapper.parameters().flattened())
            try save(arrays: arrays, url: url)
            log("Saved model checkpoint to \(url.lastPathComponent)")
        } catch {
            log("Failed to save checkpoint: \(error)")
        }
    }

    // MARK: - State Restoration

    /// Check if there's a resumable training session from disk
    public var hasResumableSession: Bool {
        TrainingStatePersistence.shared.hasResumableSession
    }

    /// Get summary of resumable session for UI
    public func getResumableSummary() -> (datasetName: String, epoch: Int, progress: String)? {
        TrainingStatePersistence.shared.getResumableSummary()
    }

    /// Restore training state from disk and resume
    /// Call this from TrainingDashboardView when user wants to resume
    public func restoreAndResume(modelContext: ModelContext) async {
        guard !workerLifecycle.hasWorker, !isPreparingCheckpoint else {
            log("A live worker already exists; disk restoration skipped. Use Resume for a paused session.")
            return
        }
        guard let persistedState = TrainingStatePersistence.shared.load() else {
            log("No persisted state to restore")
            return
        }

        log("Restoring training session: \(persistedState.runName)")

        // Old raw snapshots have neither a verified model specification nor an
        // atomic metadata/weight pair. Do not force-cast or silently guess a head.
        state = .failed
        workPhase = .failed
        log("This interrupted-session snapshot cannot be verified. Select its saved run under Configuration → Run to Resume to recover a validated epoch checkpoint. Saved files were preserved.")
    }

    // MARK: - Manual Resume (From Dashboard)

    /// Own checkpoint preparation until its result can be handed to the normal
    /// Idle-only start path. Stop invalidates the result without deleting files.
    /// Loading may finish after Stop, but cannot apply a model or start work.
    internal func prepareCheckpointResume<Loaded>(
        load: @MainActor () async throws -> Loaded,
        start: @MainActor (Loaded) -> Void
    ) async throws {
        guard !workerLifecycle.hasWorker, !isPreparingCheckpoint else {
            throw ModelPersistence.PersistenceError.loadFailed("A training operation is already active.")
        }
        let preparationID = UUID()
        checkpointPreparationID = preparationID
        state = .preparing
        workPhase = .preparing
        do {
            let loaded = try await load()
            guard checkpointPreparationID == preparationID, !Task.isCancelled else {
                throw CancellationError()
            }
            // No suspension between releasing preparation and invoking start.
            // startTraining's Idle guard must accept this successful handoff.
            checkpointPreparationID = nil
            state = .idle
            workPhase = .idle
            start(loaded)
        } catch {
            guard checkpointPreparationID == preparationID else { throw CancellationError() }
            checkpointPreparationID = nil
            state = error is CancellationError ? .idle : .failed
            workPhase = error is CancellationError ? .idle : .failed
            UIApplication.shared.isIdleTimerDisabled = false
            log("Checkpoint preparation \(error is CancellationError ? "cancelled" : "failed"): \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Resumes an arbitrary previous training run from its last checkpoint
    public func resumeFromRun(_ run: TrainingRun, modelContext: ModelContext, targetDatasetName: String?) async throws {
        guard let originalConfig = run.config else {
            throw ModelPersistence.PersistenceError.loadFailed("The original training-run configuration is missing.")
        }
        try await prepareCheckpointResume(load: {
            self.log("Manual resume from run: \(run.name)")
            let persistence = ModelPersistence(modelsDirectory: self.getRunCheckpointDirectory(runName: run.name))
            guard let url = await persistence.preferredCheckpointURL() else {
                throw ModelPersistence.PersistenceError.loadFailed("No checkpoint found for \(run.name)")
            }
            return try await persistence.loadModel(from: url, legacyTrainingConfig: run.configData)
        }, start: { loadedModel, loadedConfig, checkpoint in
            self.model = loadedModel
            self.modelWrapper = SignLanguageModuleWrapper(model: loadedModel)
            self.checkpointSpecification = checkpoint.specification
            self.config = originalConfig
            self.optimizer = Adam(learningRate: originalConfig.learningRate)
            self.currentEpoch = checkpoint.epoch
            self.currentBatch = 0
            self.metrics = [] // New optimizer/run: do not mix later unsaved metrics with epoch-8 weights.
            self.lastLoss = checkpoint.loss ?? 0
            let recoveredRun = TrainingRun(
                name: "Resume \(Date().formatted(date: .omitted, time: .shortened)) \(UUID().uuidString.prefix(8))",
                config: originalConfig, status: "Resuming")
            self.currentRun = recoveredRun
            modelContext.insert(recoveredRun)
            self.modelContext = modelContext
            self.log("Verified checkpoint at epoch \(checkpoint.epoch); \(loadedConfig.poolingType.rawValue) pooling, \(loadedConfig.numHeads) heads, \(loadedConfig.outputMode.rawValue) output.")
            self.log("Source run preserved: \(run.name). Continuing in \(recoveredRun.name).")
            self.log("Starting at the next epoch with a new optimizer and new metrics; optimizer state was not restored.")
            self.startTraining(datasetPath: FileManager.default.documentsDirectory, modelContext: modelContext, targetDatasetName: targetDatasetName)
        })
    }

    /// Clear persisted state (call when training completes normally or is explicitly stopped)
    public func clearPersistedState() {
        TrainingStatePersistence.shared.clear()
    }
    
    // MARK: - Helpers
    
    private func log(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        print("[\(timestamp)] [Training] \(message)")
        logs.append("[\(timestamp)] \(message)")
    }
    
    /// Delete all training runs from database and disk
    public func deleteAllRuns(modelContext: ModelContext) {
        do {
            // 1. Fetch all runs
            let runs = try modelContext.fetch(FetchDescriptor<TrainingRun>())
            
            // 2. Delete files
            for run in runs {
                let dir = getRunCheckpointDirectory(runName: run.name)
                try? FileManager.default.removeItem(at: dir)
            }
            
            // 3. Delete from DB
            for run in runs {
                modelContext.delete(run)
            }
            
            try modelContext.save()
            log("Deleted all training runs.")
            
            // Reset current run if it was deleted
            if let current = currentRun, runs.contains(where: { $0.id == current.id }) {
                currentRun = nil
                state = .idle
            }
            
        } catch {
            log("Failed to delete runs: \(error)")
        }
    }
    
    // MARK: - Self-Healing
    
    /// Audit missing metadata; never manufacture an architecture for old weights.
    public func ensureConfigsAreSaved(modelContext: ModelContext) {
        guard let runs = try? modelContext.fetch(FetchDescriptor<TrainingRun>()) else { return }
        let missing = runs.filter {
            !FileManager.default.fileExists(atPath: getRunCheckpointDirectory(runName: $0.name).appendingPathComponent("config.json").path)
        }
        if !missing.isEmpty { log("\(missing.count) saved runs lack model configuration; verified recovery is required.") }
    }

    private func persistEffectiveSpecification(for run: TrainingRun) throws {
        guard let specification = checkpointSpecification else { throw ModelPersistence.PersistenceError.configMismatch }
        let folder = getRunCheckpointDirectory(runName: run.name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        try encoder.encode(specification).write(to: folder.appendingPathComponent("model-specification.json"), options: .atomic)
        if let effective = specification.config {
            try encoder.encode(effective).write(to: folder.appendingPathComponent("config.json"), options: .atomic)
        }
        if specification.config?.outputMode == .classification {
            try encoder.encode(specification.classNames).write(to: folder.appendingPathComponent("classes.json"), options: .atomic)
        }
    }
}
