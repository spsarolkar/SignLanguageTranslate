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
        var specification: CheckpointModelSpecification? = nil
        var weightsSHA256: String? = nil
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
        name: String = "checkpoint",
        classNames: [String] = []
    ) async throws -> URL {
        guard let actualModel = wrapper._model as? SignLanguageModel, actualModel.config == config else {
            throw PersistenceError.configMismatch
        }
        let specification = CheckpointModelSpecification(config: actualModel.config, classNames: classNames)
        _ = try specification.validatedConfig()
        let checkpointDir = modelsDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: checkpointDir, withIntermediateDirectories: true)

        // Save weights using MLX's save function
        let weightsURL = checkpointDir.appendingPathComponent("weights.safetensors")
        let parameters = wrapper.parameters()
        try saveArrays(parameters.flattened(), url: weightsURL)

        // Save config and metadata
        let configData = try JSONEncoder().encode(config)
        let checkpoint = ModelCheckpoint(
            configJSON: configData,
            timestamp: Date(),
            epoch: epoch,
            step: step,
            loss: loss,
            modelVersion: "2.0",
            specification: specification,
            weightsSHA256: try CheckpointCompatibility.fingerprint(weightsURL)
        )

        let metadataURL = checkpointDir.appendingPathComponent("checkpoint.json")
        let metadataData = try JSONEncoder().encode(checkpoint)
        try metadataData.write(to: metadataURL, options: .atomic)

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
    func loadModel(from url: URL, legacyTrainingConfig: Data? = nil) async throws -> (SignLanguageModel, SignLanguageModelConfig, ModelCheckpoint) {
        var isDirectory: ObjCBool = false
        let directory = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        let metadataURL = directory ? url.appendingPathComponent("checkpoint.json") : url
        let parent = metadataURL.deletingLastPathComponent()
        let basename = metadataURL.deletingPathExtension().lastPathComponent
        let weightsURL = directory ? url.appendingPathComponent("weights.safetensors") :
            parent.appendingPathComponent(basename.hasSuffix("_metadata") ?
                String(basename.dropLast("_metadata".count)) + ".safetensors" : basename + ".safetensors")
        guard FileManager.default.fileExists(atPath: metadataURL.path) else { throw PersistenceError.fileNotFound(metadataURL) }
        guard FileManager.default.fileExists(atPath: weightsURL.path) else { throw PersistenceError.fileNotFound(weightsURL) }
        let shapes = try CheckpointCompatibility.readShapes(at: weightsURL)
        let decoder = JSONDecoder()
        let data = try Data(contentsOf: metadataURL)
        let checkpoint: ModelCheckpoint
        let savedConfig: SignLanguageModelConfig
        if let standard = try? decoder.decode(ModelCheckpoint.self, from: data) {
            checkpoint = standard
            savedConfig = try decoder.decode(SignLanguageModelConfig.self, from: standard.configJSON)
        } else {
            guard let values = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let epoch = values["epoch"] as? Int, epoch >= 0,
                  let timestamp = values["timestamp"] as? String,
                  let date = ISO8601DateFormatter().date(from: timestamp),
                  let loss = values["value"] as? Float, loss.isFinite else { throw PersistenceError.invalidFormat }
            let specification = try values["specification"].map {
                try decoder.decode(CheckpointModelSpecification.self, from: JSONSerialization.data(withJSONObject: $0))
            }
            if let specification { _ = try specification.validatedConfig() }
            let configData = try Data(contentsOf: parent.appendingPathComponent("config.json"))
            savedConfig = try decoder.decode(SignLanguageModelConfig.self, from: configData)
            checkpoint = ModelCheckpoint(configJSON: configData, timestamp: date, epoch: epoch,
                                         step: 0, loss: loss, modelVersion: "legacy-flat",
                                         specification: specification, weightsSHA256: values["weightsSHA256"] as? String)
        }
        if let digest = checkpoint.weightsSHA256 {
            guard try CheckpointCompatibility.fingerprint(weightsURL) == digest else {
                throw CheckpointCompatibility.Error.incompatible("Checkpoint weights do not match their metadata; an interrupted save may have occurred.")
            }
        } else if checkpoint.specification != nil {
            throw CheckpointCompatibility.Error.incompatible("Versioned checkpoint is missing its weights digest.")
        }
        let specificationURL = parent.appendingPathComponent("model-specification.json")
        let recordedSpecification = try checkpoint.specification ??
            (FileManager.default.fileExists(atPath: specificationURL.path) ?
                decoder.decode(CheckpointModelSpecification.self, from: Data(contentsOf: specificationURL)) : nil)
        let specification: CheckpointModelSpecification
        let recovered: Bool
        if let recordedSpecification {
            guard checkpoint.weightsSHA256 != nil else {
                throw CheckpointCompatibility.Error.incompatible("Versioned checkpoint is missing its weights digest.")
            }
            let config = try recordedSpecification.validatedConfig()
            guard config == savedConfig else { throw PersistenceError.configMismatch }
            specification = recordedSpecification
            recovered = false
        } else {
            guard let legacyTrainingConfig else {
                throw CheckpointCompatibility.Error.incompatible("This older checkpoint needs its original training-run configuration for verified recovery. Select it under Configuration → Run to Resume.")
            }
            let classesURL = parent.appendingPathComponent("classes.json")
            let classes = FileManager.default.fileExists(atPath: classesURL.path) ?
                try decoder.decode([String].self, from: Data(contentsOf: classesURL)) : []
            let config = try CheckpointCompatibility.legacyConfig(recordedTraining: legacyTrainingConfig, classNames: classes)
            specification = CheckpointModelSpecification(config: config, classNames: classes)
            recovered = true
        }
        let config = try specification.validatedConfig()
        let model = SignLanguageModel(config: config)
        let wrapper = SignLanguageModuleWrapper(model: model)
        let expected = Dictionary(uniqueKeysWithValues: wrapper.parameters().flattened().map { ($0.0, $0.1.shape) })
        try CheckpointCompatibility.validateShapes(expected: expected, actual: shapes)
        let arrays = try loadArrays(url: weightsURL)
        try CheckpointCompatibility.validateShapes(expected: expected, actual: arrays.mapValues { $0.shape })
        try wrapper.update(parameters: ModuleParameters.unflattened(arrays), verify: .all)
        let resolved = ModelCheckpoint(configJSON: try JSONEncoder().encode(config), timestamp: checkpoint.timestamp,
                                       epoch: checkpoint.epoch, step: checkpoint.step, loss: checkpoint.loss,
                                       modelVersion: recovered ? "legacy-recovered-v1" : checkpoint.modelVersion,
                                       specification: specification, weightsSHA256: checkpoint.weightsSHA256)
        print("[ModelPersistence] Verified all \(expected.count) parameters; legacy recovery: \(recovered)")
        return (model, config, resolved)
    }

    /// Metadata selection does not allocate a model or touch tensor values.
    func preferredCheckpointURL() -> URL? {
        let best = modelsDirectory.appendingPathComponent("best")
        if FileManager.default.fileExists(atPath: best.path) { return best }
        let flat = modelsDirectory.appendingPathComponent("best_metadata.json")
        if FileManager.default.fileExists(atPath: flat.path) { return flat }
        return listCheckpoints().first?.url
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
        if FileManager.default.fileExists(atPath: bestDir.path) { return try await loadModel(from: bestDir) }
        let flat = modelsDirectory.appendingPathComponent("best_metadata.json")
        if FileManager.default.fileExists(atPath: flat.path) { return try await loadModel(from: flat) }
        return nil
    }
}
