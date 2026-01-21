import Foundation
import MLX
import MLXNN

/// Training logger providing TensorBoard-like logging functionality for MLX training
///
/// Logs training metrics, model statistics, and gradient information to enable
/// debugging and analysis of training runs.
///
/// ## Usage
/// ```swift
/// let logger = TrainingLogger(logDirectory: documentsURL.appendingPathComponent("logs"))
/// logger.logScalar("loss/train", value: 0.5, step: 100)
/// logger.logHistogram("gradients/layer1", values: gradientArray, step: 100)
/// ```
actor TrainingLogger {

    // MARK: - Types

    struct LogEntry: Codable, Sendable {
        let timestamp: Date
        let step: Int
        let tag: String
        let value: Double
    }

    struct HistogramEntry: Codable, Sendable {
        let timestamp: Date
        let step: Int
        let tag: String
        let min: Double
        let max: Double
        let mean: Double
        let std: Double
        let count: Int
    }

    struct TrainingRunInfo: Codable, Sendable {
        let runId: String
        let startTime: Date
        var endTime: Date?
        var epochs: Int
        var finalLoss: Double?
        var config: [String: String]
    }

    // MARK: - Properties

    private let logDirectory: URL
    private let runId: String
    private var scalarLogs: [LogEntry] = []
    private var histogramLogs: [HistogramEntry] = []
    private var runInfo: TrainingRunInfo
    private var lastFlushTime: Date = Date()
    private let flushInterval: TimeInterval = 30 // Flush every 30 seconds

    // MARK: - Initialization

    init(logDirectory: URL, runId: String = UUID().uuidString) {
        self.logDirectory = logDirectory
        self.runId = runId
        self.runInfo = TrainingRunInfo(
            runId: runId,
            startTime: Date(),
            epochs: 0,
            config: [:]
        )

        // Create log directory
        try? FileManager.default.createDirectory(
            at: logDirectory,
            withIntermediateDirectories: true
        )

        print("[TrainingLogger] Initialized with run ID: \(runId)")
        print("[TrainingLogger] Log directory: \(logDirectory.path)")
    }

    // MARK: - Scalar Logging

    /// Log a scalar value (loss, accuracy, learning rate, etc.)
    func logScalar(_ tag: String, value: Double, step: Int) {
        let entry = LogEntry(
            timestamp: Date(),
            step: step,
            tag: tag,
            value: value
        )
        scalarLogs.append(entry)

        // Print for console visibility
        print("[Train] Step \(step) | \(tag): \(String(format: "%.6f", value))")

        // Auto-flush if needed
        checkAutoFlush()
    }

    /// Log a scalar value from MLXArray
    func logScalar(_ tag: String, value: MLXArray, step: Int) {
        let floatValue = Double(value.item(Float.self))
        logScalar(tag, value: floatValue, step: step)
    }

    // MARK: - Histogram Logging

    /// Log a histogram of values (useful for weight/gradient distributions)
    func logHistogram(_ tag: String, values: MLXArray, step: Int) {
        // Compute statistics
        let flatValues = values.reshaped([-1])
        let minVal = Double(MLX.min(flatValues).item(Float.self))
        let maxVal = Double(MLX.max(flatValues).item(Float.self))
        let meanVal = Double(MLX.mean(flatValues).item(Float.self))

        // Compute std: sqrt(mean((x - mean)^2))
        let centered = flatValues - MLXArray(Float(meanVal))
        let variance = MLX.mean(centered * centered)
        let stdVal = Double(sqrt(variance).item(Float.self))

        let entry = HistogramEntry(
            timestamp: Date(),
            step: step,
            tag: tag,
            min: minVal,
            max: maxVal,
            mean: meanVal,
            std: stdVal,
            count: flatValues.dim(0)
        )
        histogramLogs.append(entry)

        print("[Train] Step \(step) | \(tag): mean=\(String(format: "%.4f", meanVal)), std=\(String(format: "%.4f", stdVal))")
    }

    // MARK: - Model Statistics

    /// Log model parameter statistics
    func logModelStats(_ model: SignLanguageModuleWrapper, step: Int) {
        // Log weight norms and distributions for key layers
        // This helps detect vanishing/exploding gradients

        let modules = model._model.modules()
        for (index, module) in modules.enumerated() {
            if let linear = module as? MLXNN.Linear {
                // Log weight statistics
                logHistogram("weights/layer_\(index)", values: linear.weight, step: step)

                // Log weight norm
                let weightNorm = sqrt(MLX.sum(linear.weight * linear.weight))
                logScalar("weight_norm/layer_\(index)", value: weightNorm, step: step)
            }
        }
    }

    /// Log gradient statistics
    func logGradientStats(_ gradients: ModuleParameters, step: Int) {
        // Iterate through gradient parameters
        var totalGradNorm: Float = 0
        var layerCount = 0

        for (key, value) in gradients.flattened() {
            if let gradArray = value as? MLXArray {
                let gradNorm = sqrt(MLX.sum(gradArray * gradArray)).item(Float.self)
                totalGradNorm += gradNorm * gradNorm
                layerCount += 1

                // Log individual layer gradient norms (sample every few steps)
                if step % 10 == 0 {
                    logScalar("grad_norm/\(key)", value: Double(gradNorm), step: step)
                }
            }
        }

        // Log total gradient norm
        let totalNorm = sqrt(totalGradNorm)
        logScalar("grad_norm/total", value: Double(totalNorm), step: step)
    }

    // MARK: - Training Run Management

    /// Update training configuration info
    func setConfig(_ config: TrainingConfig) {
        runInfo.config["batch_size"] = String(config.batchSize)
        runInfo.config["learning_rate"] = String(config.learningRate)
        runInfo.config["epochs"] = String(config.epochs)
        runInfo.config["device"] = config.device
    }

    /// Mark epoch completion
    func logEpochEnd(epoch: Int, loss: Double) {
        runInfo.epochs = epoch
        runInfo.finalLoss = loss
        logScalar("epoch/loss", value: loss, step: epoch)

        // Force flush at epoch boundaries
        Task {
            await flush()
        }
    }

    /// Mark training run complete
    func finishRun(finalLoss: Double?) async {
        runInfo.endTime = Date()
        runInfo.finalLoss = finalLoss
        await flush()
        print("[TrainingLogger] Run \(runId) completed")
    }

    // MARK: - Persistence

    /// Flush logs to disk
    func flush() async {
        let runDirectory = logDirectory.appendingPathComponent(runId)
        try? FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)

        // Save scalar logs
        let scalarsURL = runDirectory.appendingPathComponent("scalars.json")
        if let data = try? JSONEncoder().encode(scalarLogs) {
            try? data.write(to: scalarsURL, options: .atomic)
        }

        // Save histogram logs
        let histogramsURL = runDirectory.appendingPathComponent("histograms.json")
        if let data = try? JSONEncoder().encode(histogramLogs) {
            try? data.write(to: histogramsURL, options: .atomic)
        }

        // Save run info
        let runInfoURL = runDirectory.appendingPathComponent("run_info.json")
        if let data = try? JSONEncoder().encode(runInfo) {
            try? data.write(to: runInfoURL, options: .atomic)
        }

        lastFlushTime = Date()
        print("[TrainingLogger] Flushed \(scalarLogs.count) scalar logs, \(histogramLogs.count) histogram logs")
    }

    private func checkAutoFlush() {
        if Date().timeIntervalSince(lastFlushTime) > flushInterval {
            Task {
                await flush()
            }
        }
    }

    // MARK: - Reading Logs

    /// Load scalar logs from a previous run
    static func loadScalarLogs(runId: String, from logDirectory: URL) -> [LogEntry]? {
        let scalarsURL = logDirectory
            .appendingPathComponent(runId)
            .appendingPathComponent("scalars.json")

        guard let data = try? Data(contentsOf: scalarsURL),
              let logs = try? JSONDecoder().decode([LogEntry].self, from: data) else {
            return nil
        }
        return logs
    }

    /// List all training runs
    static func listRuns(in logDirectory: URL) -> [TrainingRunInfo] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: logDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            return []
        }

        return contents.compactMap { url in
            let runInfoURL = url.appendingPathComponent("run_info.json")
            guard let data = try? Data(contentsOf: runInfoURL),
                  let info = try? JSONDecoder().decode(TrainingRunInfo.self, from: data) else {
                return nil
            }
            return info
        }.sorted { $0.startTime > $1.startTime }
    }
}

// MARK: - Training Metrics Summary

/// Summary statistics for a training run
struct TrainingRunSummary: Sendable {
    let runId: String
    let duration: TimeInterval
    let epochs: Int
    let finalLoss: Double?
    let minLoss: Double?
    let convergenceStep: Int? // Step where loss first dropped below threshold
    let averageStepTime: TimeInterval?
}

extension TrainingLogger {

    /// Generate a summary of the current training run
    func generateSummary() -> TrainingRunSummary {
        let lossLogs = scalarLogs.filter { $0.tag.contains("loss") }
        let minLoss = lossLogs.map { $0.value }.min()

        // Find convergence point (first time loss < 0.1)
        let convergenceStep = lossLogs.first { $0.value < 0.1 }?.step

        // Calculate duration
        let duration = (runInfo.endTime ?? Date()).timeIntervalSince(runInfo.startTime)

        // Calculate average step time
        var avgStepTime: TimeInterval? = nil
        if lossLogs.count > 1 {
            let totalSteps = lossLogs.last!.step - lossLogs.first!.step
            let totalTime = lossLogs.last!.timestamp.timeIntervalSince(lossLogs.first!.timestamp)
            if totalSteps > 0 {
                avgStepTime = totalTime / Double(totalSteps)
            }
        }

        return TrainingRunSummary(
            runId: runId,
            duration: duration,
            epochs: runInfo.epochs,
            finalLoss: runInfo.finalLoss,
            minLoss: minLoss,
            convergenceStep: convergenceStep,
            averageStepTime: avgStepTime
        )
    }
}
