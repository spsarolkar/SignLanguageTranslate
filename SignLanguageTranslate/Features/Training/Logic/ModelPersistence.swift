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
    func loadModel(from checkpointDir: URL) async throws -> (SignLanguageModel, SignLanguageModelConfig, ModelCheckpoint) {
        // Load metadata
        let metadataURL = checkpointDir.appendingPathComponent("checkpoint.json")
        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            throw PersistenceError.fileNotFound(metadataURL)
        }

        let metadataData = try Data(contentsOf: metadataURL)
        let checkpoint = try JSONDecoder().decode(ModelCheckpoint.self, from: metadataData)

        // Decode config
        let config = try JSONDecoder().decode(SignLanguageModelConfig.self, from: checkpoint.configJSON)

        // Create model with config
        let model = SignLanguageModel(config: config)

        // Load weights
        let weightsURL = checkpointDir.appendingPathComponent("weights.safetensors")
        guard FileManager.default.fileExists(atPath: weightsURL.path) else {
            throw PersistenceError.fileNotFound(weightsURL)
        }

        let loadedParams = try loadArrays(url: weightsURL)

        // Apply loaded parameters to model
        // Note: This requires matching the parameter keys
        try applyParameters(loadedParams, to: model)

        print("[ModelPersistence] Loaded checkpoint from: \(checkpointDir.path)")
        print("[ModelPersistence] Epoch: \(checkpoint.epoch), Loss: \(checkpoint.loss ?? -1)")

        return (model, config, checkpoint)
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

    struct CheckpointInfo {
        let url: URL
        let epoch: Int
        let step: Int
        let loss: Float?
        let timestamp: Date
    }

    /// List all available checkpoints sorted by timestamp (newest first)
    func listCheckpoints() -> [CheckpointInfo] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: modelsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            return []
        }

        return contents.compactMap { url in
            let metadataURL = url.appendingPathComponent("checkpoint.json")
            guard let data = try? Data(contentsOf: metadataURL),
                  let checkpoint = try? JSONDecoder().decode(ModelCheckpoint.self, from: data) else {
                return nil
            }

            return CheckpointInfo(
                url: url,
                epoch: checkpoint.epoch,
                step: checkpoint.step,
                loss: checkpoint.loss,
                timestamp: checkpoint.timestamp
            )
        }.sorted { $0.timestamp > $1.timestamp }
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
        // This matches parameter keys from the saved dictionary
        wrapper.update(parameters: ModuleParameters(values: params as! [String : NestedItem<String, MLXArray>]))
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
