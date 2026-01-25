import Foundation

/// Callback that syncs training progress to Cloudflare R2.
/// Uploads metrics after each epoch for remote monitoring.
///
/// ## Usage
/// ```swift
/// let cloudSync = CloudSyncCallback(
///     r2Service: r2,
///     runRecord: runRecord
/// )
/// callbackManager.register(cloudSync)
/// ```
public final class CloudSyncCallback: TrainingCallback, @unchecked Sendable {
    
    // MARK: - Dependencies
    
    private let r2Service: R2SyncService
    private var runRecord: TrainingRunRecord
    
    // MARK: - Configuration
    
    /// Sync epoch metrics after each epoch.
    public let syncEpochs: Bool
    
    /// Sync batch metrics (can be expensive, disabled by default).
    public let syncBatches: Bool
    
    /// Update the full run record every N epochs.
    public let fullSyncInterval: Int
    
    // MARK: - Initialization
    
    public init(
        r2Service: R2SyncService,
        runRecord: TrainingRunRecord,
        syncEpochs: Bool = true,
        syncBatches: Bool = false,
        fullSyncInterval: Int = 5
    ) {
        self.r2Service = r2Service
        self.runRecord = runRecord
        self.syncEpochs = syncEpochs
        self.syncBatches = syncBatches
        self.fullSyncInterval = fullSyncInterval
    }
    
    // MARK: - TrainingCallback
    
    public func onTrainBegin(run: TrainingRun) async {
        print("[CloudSync] Training started, uploading initial run record...")
        runRecord.status = .running
        
        do {
            try await r2Service.uploadRun(runRecord)
        } catch {
            print("[CloudSync] Failed to upload initial run: \(error)")
        }
    }
    
    public func onEpochEnd(epoch: Int, metrics: EpochMetrics, run: TrainingRun) async -> CallbackAction {
        // Convert to cloud record
        let epochRecord = EpochRecord(from: metrics)
        
        // Update local state
        runRecord.epochs.append(epochRecord)
        runRecord.totalTrainingTime += metrics.epochDuration
        
        // Track best val loss
        if let valLoss = metrics.valLoss {
            if runRecord.bestValLoss == nil || valLoss < runRecord.bestValLoss! {
                runRecord.bestValLoss = valLoss
                runRecord.bestEpoch = epoch
            }
        }
        
        // Sync to cloud
        if syncEpochs {
            do {
                try await r2Service.uploadEpoch(epochRecord, runId: runRecord.runId)
                
                // Full sync periodically
                if (epoch + 1) % fullSyncInterval == 0 {
                    try await r2Service.uploadRun(runRecord)
                }
            } catch {
                print("[CloudSync] Failed to upload epoch \(epoch): \(error)")
            }
        }
        
        return .continue
    }
    
    public func onBatchEnd(batch: Int, metrics: BatchMetrics, run: TrainingRun) async {
        // Batch syncing is expensive, usually disabled
        guard syncBatches else { return }
        
        // Could implement batch-level telemetry here if needed
    }
    
    public func onTrainEnd(run: TrainingRun) async {
        print("[CloudSync] Training ended, uploading final run record...")
        
        runRecord.endedAt = Date()
        
        // Determine final status based on how training ended
        if runRecord.epochs.count >= runRecord.config.maxEpochs {
            runRecord.status = .completed
        }
        // Note: earlyStopped status is set by the manager before calling onTrainEnd
        
        do {
            try await r2Service.uploadRun(runRecord)
            
            // Update global index
            let summary = CloudTrainingRunSummary(from: runRecord)
            var index = (try? await r2Service.downloadIndex()) ?? []
            
            // Update or append
            if let existingIndex = index.firstIndex(where: { $0.runId == runRecord.runId }) {
                index[existingIndex] = summary
            } else {
                index.append(summary)
            }
            
            try await r2Service.updateIndex(runs: index)
            
        } catch {
            print("[CloudSync] Failed to upload final run: \(error)")
        }
    }
    
    // MARK: - Public Methods
    
    /// Update run status (e.g., when backgrounded or paused).
    public func updateStatus(_ status: RunStatus, reason: String? = nil) async {
        runRecord.status = status
        runRecord.stopReason = reason
        
        do {
            try await r2Service.uploadRun(runRecord)
        } catch {
            print("[CloudSync] Failed to update status: \(error)")
        }
    }
    
    /// Get the current run record.
    public var currentRunRecord: TrainingRunRecord {
        runRecord
    }
}
