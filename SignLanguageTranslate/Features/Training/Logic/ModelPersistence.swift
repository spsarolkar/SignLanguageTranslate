import Foundation
import MLX
import MLXNN

/// Handles saving and loading model weights
///
/// Saves model parameters in MLX's native safetensors format for:
/// - Checkpointing during training
/// - Loading pre-trained models
/// - Model export/sharing
///
/// ## Usage
/// ```swift
/// let persistence = ModelPersistence()
///
/// // Save model
/// try await persistence.saveModel(model, to: checkpointURL)
///
/// // Load model
/// let loadedModel = try await persistence.loadModel(from: checkpointURL)
/// ```
actor ModelPersistence {

    // MARK: - Types

    struct ModelCheckpoint: Codable {
        let configJSON: Data
        let timestamp: Date
        let epoch: Int
        let step: Int
        let loss: Float?
        let modelVersion: String
    }

    enum PersistenceError: LocalizedError {
        case saveFailed(String)
        case loadFailed(String)
        case configMismatch
        case fileNotFound(URL)
        case invalidFormat

        var errorDescription: String? {
            switch self {
            case .saveFailed(let msg):
                return "Failed to save model: \(msg)"
            case .loadFailed(let msg):
                return "Failed to load model: \(msg)"
            case .configMismatch:
                return "Model configuration mismatch"
            case .fileNotFound(let url):
                return "Model file not found: \(url.lastPathComponent)"
            case .invalidFormat:
                return "Invalid model file format"
            }
        }
    }

    // MARK: - Properties

    private let modelsDirectory: URL

    // MARK: - Initialization

    init(modelsDirectory: URL? = nil) {
        if let dir = modelsDirectory {
            self.modelsDirectory = dir
        } else {
            // Default to Documents/Models/
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            self.modelsDirectory = documentsURL.appendingPathComponent("Models")
        }

        // Ensure directory exists
        try? FileManager.default.createDirectory(
            at: self.modelsDirectory,
            withIntermediateDirectories: true
        )
    }

    // MARK: - Save

    /// Save model weights and configuration
    func saveModel(
        _ wrapper: SignLanguageModuleWrapper,
        config: SignLanguageModelConfig,
        epoch: Int,
        step: Int,
        loss: Float?,
        name: String = "checkpoint"
    ) async throws -> URL {
        let checkpointDir = modelsDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: checkpointDir, withIntermediateDirectories: true)

        // Save weights using MLX's save function
        let weightsURL = checkpointDir.appendingPathComponent("weights.safetensors")
        let parameters = wrapper.trainableParameters()
        try saveArrays(parameters.flattened(), url: weightsURL)

        // Save config and metadata
        let configData = try JSONEncoder().encode(config)
        let checkpoint = ModelCheckpoint(
            configJSON: configData,
            timestamp: Date(),
            epoch: epoch,
            step: step,
            loss: loss,
            modelVersion: "1.0"
        )

        let metadataURL = checkpointDir.appendingPathComponent("checkpoint.json")
        let metadataData = try JSONEncoder().encode(checkpoint)
        try metadataData.write(to: metadataURL)

        print("[ModelPersistence] Saved checkpoint to: \(checkpointDir.path)")
        print("[ModelPersistence] Epoch: \(epoch), Step: \(step), Loss: \(loss ?? -1)")

        return checkpointDir
    }

    /// Quick save with auto-generated name
    func saveCheckpoint(
        _ wrapper: SignLanguageModuleWrapper,
        config: SignLanguageModelConfig,
        epoch: Int,
        step: Int,
        loss: Float?
    ) async throws -> URL {
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let name = "checkpoint_e\(epoch)_s\(step)_\(timestamp)"

        return try await saveModel(wrapper, config: config, epoch: epoch, step: step, loss: loss, name: name)
    }

    // MARK: - Load

    /// Load model from checkpoint directory
    func loadModel(from url: URL) async throws -> (SignLanguageModel, SignLanguageModelConfig, ModelCheckpoint) {
        let metadataURL: URL
        let weightsURL: URL
        
        // Handle both directory (standard) and file (legacy flat) URLs
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
             metadataURL = url.appendingPathComponent("checkpoint.json")
             weightsURL = url.appendingPathComponent("weights.safetensors")
        } else {
             // Assume url is the metadata json file
             metadataURL = url
             // Derive weights URL: "xxx_metadata.json" -> "xxx.safetensors"
             let filename = url.deletingPathExtension().lastPathComponent
             if filename.hasSuffix("_metadata") {
                 let basename = filename.replacingOccurrences(of: "_metadata", with: "")
                 weightsURL = url.deletingLastPathComponent().appendingPathComponent("\(basename).safetensors")
             } else {
                 // Fallback/Guess
                 weightsURL = url.deletingPathExtension().appendingPathExtension("safetensors")
             }
        }

        // 1. Load Metadata
        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
             throw PersistenceError.fileNotFound(metadataURL)
        }
        
        let data = try Data(contentsOf: metadataURL)
        
        // Attempt to decode
        let checkpoint: ModelCheckpoint
        let config: SignLanguageModelConfig
        
        // Decoders
        let decoder = JSONDecoder()
        
        // PATH A: Standard Checkpoint (serialized by ModelPersistence)
        if let standardCheckpoint = try? decoder.decode(ModelCheckpoint.self, from: data) {
            checkpoint = standardCheckpoint
            config = try decoder.decode(SignLanguageModelConfig.self, from: standardCheckpoint.configJSON)
        } 
        // PATH B: Callback Checkpoint (serialized by ModelCheckpointCallback - simplified JSON)
        else {
             // We need to find the config.json in the directory (it should be saved at start of training)
             let parentConfigURL = url.deletingLastPathComponent().appendingPathComponent("config.json")
             
             // If config.json doesn't exist, we can't reconstruct the model
             guard FileManager.default.fileExists(atPath: parentConfigURL.path) else {
                 print("[ModelPersistence] Critical: No config found for checkpoint \(url.lastPathComponent)")
                 throw PersistenceError.configMismatch
             }
             
             let configData = try Data(contentsOf: parentConfigURL)
             config = try decoder.decode(SignLanguageModelConfig.self, from: configData)
             
             // Construct valid ModelCheckpoint struct from simplified JSON dict
             guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                 throw PersistenceError.invalidFormat
             }
             
             let epoch = dict["epoch"] as? Int ?? 0
             let loss = dict["value"] as? Float
             let timestampStr = dict["timestamp"] as? String
             let timestamp = ISO8601DateFormatter().date(from: timestampStr ?? "") ?? Date()
             
             checkpoint = ModelCheckpoint(
                configJSON: configData,
                timestamp: timestamp,
                epoch: epoch,
                step: 0,
                loss: loss,
                modelVersion: "1.0"
             )
        }

        // 2. Initialize Model (validate config to fix numHeads if needed)
        let validatedConfig = config.validated()
        if validatedConfig.numHeads != config.numHeads {
            print("[ModelPersistence] Auto-corrected numHeads: \(config.numHeads) → \(validatedConfig.numHeads) for modelDim=\(config.modelDim)")
        }
        let model = SignLanguageModel(config: validatedConfig)

        // 3. Load Weights
        if FileManager.default.fileExists(atPath: weightsURL.path) {
            let loadedParams = try loadArrays(url: weightsURL)
            try applyParameters(loadedParams, to: model)
            print("[ModelPersistence] Loaded model weights from \(weightsURL.lastPathComponent)")
        } else {
            print("[ModelPersistence] Warning: Weights file not found at \(weightsURL.path)")
        }
        
        return (model, validatedConfig, checkpoint)
    }

    /// Load the latest checkpoint
    func loadLatestCheckpoint() async throws -> (SignLanguageModel, SignLanguageModelConfig, ModelCheckpoint)? {
        let checkpoints = listCheckpoints()
        guard let latest = checkpoints.first else {
            return nil
        }
        return try await loadModel(from: latest.url)
    }

    // MARK: - List Checkpoints

    struct CheckpointInfo: Identifiable, Hashable, Sendable {
        var id: URL { url }
        let url: URL
        let epoch: Int
        let step: Int
        let loss: Float?
        let timestamp: Date
    }

    /// List all available checkpoints sorted by timestamp (newest first)
    func listCheckpoints() -> [CheckpointInfo] {
        let fm = FileManager.default
        print("[ModelPersistence] Listing checkpoints in: \(modelsDirectory.path)")
        
        guard let contents = try? fm.contentsOfDirectory(
            at: modelsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            print("[ModelPersistence] Failed to list contents or directory is empty.")
            return []
        }
        
        print("[ModelPersistence] Found \(contents.count) items: \(contents.map { $0.lastPathComponent })")

        let validCheckpoints: [CheckpointInfo] = contents.compactMap { url in
            let metadataURL = url.appendingPathComponent("checkpoint.json")
            
            // Check existence
            if !fm.fileExists(atPath: metadataURL.path) {
                // Not a checkpoint folder (might be a file or random folder)
                // print("[ModelPersistence] No checkpoint.json in \(url.lastPathComponent)") 
                return nil
            }
            
            do {
                let data = try Data(contentsOf: metadataURL)
                let checkpoint = try JSONDecoder().decode(ModelCheckpoint.self, from: data)
                return CheckpointInfo(
                    url: url,
                    epoch: checkpoint.epoch,
                    step: checkpoint.step,
                    loss: checkpoint.loss,
                    timestamp: checkpoint.timestamp
                )
            } catch {
                print("[ModelPersistence] Failed to decode metadata for \(url.lastPathComponent): \(error)")
                return nil
            }
        }
        
        // FLAT FILE SCANNING (New)
        // Scan for *_metadata.json files in the root directory
        if let files = try? fm.contentsOfDirectory(at: modelsDirectory, includingPropertiesForKeys: nil) {
            let jsonFiles = files.filter { $0.pathExtension == "json" && $0.lastPathComponent.hasSuffix("_metadata.json") }
            
            let flatCheckpoints: [CheckpointInfo] = jsonFiles.compactMap { url in
                 // Decode simple metadata
                 guard let data = try? Data(contentsOf: url),
                       let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                     return nil
                 }
                 
                 let epoch = dict["epoch"] as? Int ?? 0
                 let loss = dict["value"] as? Float
                 let timestampStr = dict["timestamp"] as? String
                 let timestamp = ISO8601DateFormatter().date(from: timestampStr ?? "") ?? Date()
                 
                 return CheckpointInfo(
                    url: url, // CheckpointInfo.url now points to the METADATA FILE
                    epoch: epoch,
                    step: 0,
                    loss: loss,
                    timestamp: timestamp
                 )
            }
            
            // Merge valid checkpoints
            var finalCheckpoints = validCheckpoints
            finalCheckpoints.append(contentsOf: flatCheckpoints)
            return finalCheckpoints.sorted { $0.timestamp > $1.timestamp }
        }
        
        return validCheckpoints.sorted { $0.timestamp > $1.timestamp }
    }

    /// Delete old checkpoints, keeping the N most recent
    func pruneCheckpoints(keepCount: Int = 5) {
        let checkpoints = listCheckpoints()
        guard checkpoints.count > keepCount else { return }

        let toDelete = checkpoints.dropFirst(keepCount)
        for checkpoint in toDelete {
            try? FileManager.default.removeItem(at: checkpoint.url)
            print("[ModelPersistence] Pruned old checkpoint: \(checkpoint.url.lastPathComponent)")
        }
    }

    // MARK: - Private Helpers

    private func saveArrays(_ arrays: [(String, MLXArray)], url: URL) throws {
        // Convert to dictionary for MLX save
        var dict: [String: MLXArray] = [:]
        for (key, array) in arrays {
            dict[key] = array
        }

        // MLX save function
        try MLX.save(arrays: dict, url: url)
    }

    private func loadArrays(url: URL) throws -> [String: MLXArray] {
        return try MLX.loadArrays(url: url)
    }

    private func applyParameters(_ params: [String: MLXArray], to model: SignLanguageModel) throws {
        // Get the wrapper to access parameters
        let wrapper = SignLanguageModuleWrapper(model: model)

        // Use MLX's update mechanism
        // Unflatten the parameters to match module structure
        let unflattened = ModuleParameters.unflattened(params)
        wrapper.update(parameters: unflattened)
    }
}

// MARK: - Best Model Tracking

extension ModelPersistence {

    /// Save as best model if loss is lower than previous best
    func saveBestModel(
        _ wrapper: SignLanguageModuleWrapper,
        config: SignLanguageModelConfig,
        epoch: Int,
        step: Int,
        loss: Float
    ) async throws -> Bool {
        let bestDir = modelsDirectory.appendingPathComponent("best")
        let metadataURL = bestDir.appendingPathComponent("checkpoint.json")

        // Check if this is better than existing best
        if FileManager.default.fileExists(atPath: metadataURL.path) {
            let data = try Data(contentsOf: metadataURL)
            let existing = try JSONDecoder().decode(ModelCheckpoint.self, from: data)
            if let existingLoss = existing.loss, existingLoss <= loss {
                // Existing is better or equal
                return false
            }
        }

        // Save as new best
        _ = try await saveModel(wrapper, config: config, epoch: epoch, step: step, loss: loss, name: "best")
        print("[ModelPersistence] New best model saved! Loss: \(loss)")
        return true
    }

    /// Load the best model
    func loadBestModel() async throws -> (SignLanguageModel, SignLanguageModelConfig, ModelCheckpoint)? {
        let bestDir = modelsDirectory.appendingPathComponent("best")
        guard FileManager.default.fileExists(atPath: bestDir.path) else {
            return nil
        }
        return try await loadModel(from: bestDir)
    }
}
