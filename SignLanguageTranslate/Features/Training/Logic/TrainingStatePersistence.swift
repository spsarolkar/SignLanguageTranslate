import Foundation

/// Persists training session state to disk for recovery after app termination.
/// This allows training to resume from where it left off when the app restarts.
public struct TrainingStatePersistence {

    // MARK: - Singleton

    public static let shared = TrainingStatePersistence()

    // MARK: - File Paths

    private var stateFileURL: URL {
        FileManager.default.documentsDirectory
            .appendingPathComponent("TrainingState")
            .appendingPathExtension("json")
    }

    private var checkpointURL: URL {
        FileManager.default.documentsDirectory
            .appendingPathComponent("Checkpoints")
            .appendingPathComponent("resume.safetensors")
    }

    // MARK: - Persisted State Model

    /// Lightweight state that can be persisted to disk
    public struct PersistedState: Codable {
        // Run identification
        public var runId: UUID
        public var runName: String

        // Progress tracking
        public var currentEpoch: Int
        public var currentBatch: Int
        public var globalStep: Int

        // Configuration
        public var config: TrainingConfig
        public var datasetName: String

        // Metrics snapshot
        public var lastTrainingLoss: Float
        public var lastValidationLoss: Float?
        public var metricsCount: Int

        // Timestamps
        public var startedAt: Date
        public var lastCheckpointAt: Date

        // State flags
        public var wasTraining: Bool
        public var wasPaused: Bool

        public init(
            runId: UUID,
            runName: String,
            currentEpoch: Int,
            currentBatch: Int,
            globalStep: Int,
            config: TrainingConfig,
            datasetName: String,
            lastTrainingLoss: Float,
            lastValidationLoss: Float?,
            metricsCount: Int,
            startedAt: Date,
            lastCheckpointAt: Date = Date(),
            wasTraining: Bool,
            wasPaused: Bool
        ) {
            self.runId = runId
            self.runName = runName
            self.currentEpoch = currentEpoch
            self.currentBatch = currentBatch
            self.globalStep = globalStep
            self.config = config
            self.datasetName = datasetName
            self.lastTrainingLoss = lastTrainingLoss
            self.lastValidationLoss = lastValidationLoss
            self.metricsCount = metricsCount
            self.startedAt = startedAt
            self.lastCheckpointAt = lastCheckpointAt
            self.wasTraining = wasTraining
            self.wasPaused = wasPaused
        }
    }

    // MARK: - Save

    /// Save current training state to disk
    public func save(_ state: PersistedState) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted

            let data = try encoder.encode(state)
            try data.write(to: stateFileURL, options: .atomic)

            print("[TrainingState] Saved state: epoch=\(state.currentEpoch), batch=\(state.currentBatch)")
        } catch {
            print("[TrainingState] Failed to save state: \(error)")
        }
    }

    // MARK: - Load

    /// Load persisted training state from disk
    public func load() -> PersistedState? {
        guard FileManager.default.fileExists(atPath: stateFileURL.path) else {
            print("[TrainingState] No saved state found")
            return nil
        }

        do {
            let data = try Data(contentsOf: stateFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let state = try decoder.decode(PersistedState.self, from: data)
            print("[TrainingState] Loaded state: epoch=\(state.currentEpoch), batch=\(state.currentBatch), dataset=\(state.datasetName)")
            return state
        } catch {
            print("[TrainingState] Failed to load state: \(error)")
            return nil
        }
    }

    // MARK: - Clear

    /// Clear persisted state (call when training completes or is stopped)
    public func clear() {
        do {
            if FileManager.default.fileExists(atPath: stateFileURL.path) {
                try FileManager.default.removeItem(at: stateFileURL)
                print("[TrainingState] Cleared saved state")
            }
        } catch {
            print("[TrainingState] Failed to clear state: \(error)")
        }
    }

    // MARK: - Check

    /// Check if there's a resumable training session
    public var hasResumableSession: Bool {
        guard let state = load() else { return false }

        // Check if checkpoint file exists
        let hasCheckpoint = FileManager.default.fileExists(atPath: checkpointURL.path)

        // Session is resumable if it was training/paused and has checkpoint
        return (state.wasTraining || state.wasPaused) && hasCheckpoint
    }

    /// Get summary of resumable session for UI display
    public func getResumableSummary() -> (datasetName: String, epoch: Int, progress: String)? {
        guard let state = load() else { return nil }

        let progress = "Epoch \(state.currentEpoch)/\(state.config.epochs), Batch \(state.currentBatch)"
        return (state.datasetName, state.currentEpoch, progress)
    }
}
