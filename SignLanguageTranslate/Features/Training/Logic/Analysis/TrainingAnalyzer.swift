import Foundation

/// Analyzes training metrics to detect health issues like overfitting or underfitting.
public struct TrainingAnalyzer {
    
    // MARK: - Types
    
    public enum Trend: String, Sendable {
        case improving = "Improving"
        case stalling = "Stalling"
        case degrading = "Degrading"
        case oscillating = "Oscillating"
        case unknown = "Insufficient Data"
        
        var icon: String {
            switch self {
            case .improving: return "arrow.down.right.circle.fill" // Loss going down is good
            case .stalling: return "arrow.right.circle.fill"
            case .degrading: return "arrow.up.right.circle.fill" // Loss going up is bad
            case .oscillating: return "waveform.path.ecg"
            case .unknown: return "questionmark.circle"
            }
        }
    }
    
    public enum Health: String, Sendable {
        case healthy = "Healthy"
        case overfitting = "Overfitting"
        case underfitting = "Underfitting"
        case divergent = "Divergent"
        case unknown = "Analyzing..."
        
        var colorName: String {
            switch self {
            case .healthy: return "green"
            case .overfitting: return "orange"
            case .underfitting: return "yellow"
            case .divergent: return "red"
            case .unknown: return "gray"
            }
        }
    }
    
    public struct AnalysisResult: Sendable {
        public let trainTrend: Trend
        public let valTrend: Trend
        public let health: Health
        public let suggestions: [String]
        public let confidence: Float // 0..1
        public let diagnostics: Diagnostics?
    }
    
    public struct Diagnostics: Sendable {
        /// Bias indicator: Training loss (high = underfitting, model can't learn patterns)
        public let bias: Float
        /// Variance indicator: |Val - Train| gap (high = overfitting, model memorizing)
        public let variance: Float
        /// Generalization gap as percentage of training loss
        public let gapRatio: Float
        /// Average loss over recent window (for plateau detection)
        public let avgRecentLoss: Float
        /// Loss standard deviation (for oscillation detection)
        public let lossStdDev: Float
    }
    
    // MARK: - Configuration

    private let windowSize: Int
    private let overfitThreshold: Float  // Gap ratio (val-train)/train
    private let highLossThreshold: Float // Considered "high" loss (underfitting indicator)
    private let plateauThreshold: Float  // Max change to consider "plateau"

    public init(
        windowSize: Int = 5,
        overfitThreshold: Float = 0.15,    // 15% gap indicates overfitting
        highLossThreshold: Float = 2.0,     // Loss > 2.0 is "high" for contrastive
        plateauThreshold: Float = 0.005     // <0.5% change = plateau
    ) {
        self.windowSize = windowSize
        self.overfitThreshold = overfitThreshold
        self.highLossThreshold = highLossThreshold
        self.plateauThreshold = plateauThreshold
    }
    
    // MARK: - Analysis
    
    /// Analyze the recent history of metrics to determine training state.
    public func analyze(history: [TrainingMetrics]) -> AnalysisResult {
        guard history.count >= windowSize else {
            return AnalysisResult(
                trainTrend: .unknown,
                valTrend: .unknown,
                health: .unknown,
                suggestions: ["Training needs more data points to analyze trends."],
                confidence: 0.0,
                diagnostics: nil
            )
        }

        // Filter to only metrics that have validation loss (epoch-end or validation checkpoint metrics)
        let metricsWithValidation = history.filter { $0.validationLoss != nil }

        // For training trend, use recent batch metrics (larger window for smoother trend)
        let recentBatches = Array(history.suffix(windowSize * 2))
        let trainTrend = detectTrend(values: recentBatches.map { $0.trainingLoss })

        // For validation trend, use only metrics with validation data
        guard metricsWithValidation.count >= 2 else {
            // Not enough validation points yet - still provide training trend info
            return AnalysisResult(
                trainTrend: trainTrend,
                valTrend: .unknown,
                health: .unknown,
                suggestions: ["Waiting for more validation checkpoints (run more epochs)..."],
                confidence: 0.3,
                diagnostics: nil
            )
        }

        // Use recent validation metrics for trend analysis
        let recentValidation = Array(metricsWithValidation.suffix(windowSize))
        let valLosses = recentValidation.compactMap { $0.validationLoss }
        let valTrend = valLosses.count >= 2 ? detectTrend(values: valLosses) : .unknown

        // Use the most recent metric with validation for health diagnosis
        guard let lastWithVal = metricsWithValidation.last,
              let currentVal = lastWithVal.validationLoss else {
            return AnalysisResult(
                trainTrend: trainTrend,
                valTrend: valTrend,
                health: .unknown,
                suggestions: ["Waiting for validation metrics..."],
                confidence: 0.5,
                diagnostics: nil
            )
        }

        let currentTrain = lastWithVal.trainingLoss

        // Compute statistics for diagnostics
        let recentTrainLosses = recentBatches.map { $0.trainingLoss }
        let avgRecentLoss = recentTrainLosses.reduce(0, +) / Float(recentTrainLosses.count)
        let lossStdDev = computeStdDev(recentTrainLosses)

        // Gap metrics
        let rawGap = currentVal - currentTrain
        let gapRatio = currentTrain > 0.001 ? rawGap / currentTrain : rawGap

        // Diagnose Health
        var health: Health = .healthy
        var suggestions: [String] = []
        var confidence: Float = 0.8

        // 1. Divergence Check (Loss exploded or NaN)
        if currentTrain.isNaN || currentVal.isNaN || currentTrain > 50 || currentVal > 50 {
            health = .divergent
            suggestions.append("Loss is exploding or unstable.")
            suggestions.append("Reduce learning rate by 10x (e.g., 3e-5 instead of 3e-4).")
            suggestions.append("Check for corrupted data samples.")
            if lossStdDev > 1.0 {
                suggestions.append("High variance detected - try smaller batch size or gradient clipping.")
            }
            confidence = 1.0
        }
        // 2. Overfitting Check - Multiple conditions
        else if detectOverfitting(
            trainTrend: trainTrend,
            valTrend: valTrend,
            gapRatio: gapRatio,
            currentTrain: currentTrain,
            currentVal: currentVal,
            valLosses: valLosses
        ) {
            health = .overfitting
            suggestions.append("Model is memorizing training data instead of learning patterns.")

            if gapRatio > 0.3 {
                suggestions.append("Large train/val gap (\(Int(gapRatio * 100))%). Increase dropout to 0.3-0.5.")
            } else {
                suggestions.append("Validation loss rising. Consider early stopping.")
            }

            suggestions.append("Enable data augmentation if not already enabled.")
            suggestions.append("Try adding weight decay (L2 regularization).")
            confidence = 0.9
        }
        // 3. Underfitting Check - Multiple conditions
        else if detectUnderfitting(
            trainTrend: trainTrend,
            valTrend: valTrend,
            currentTrain: currentTrain,
            avgLoss: avgRecentLoss
        ) {
            health = .underfitting
            suggestions.append("Model is not learning effectively.")

            if currentTrain > highLossThreshold {
                suggestions.append("Training loss is high (\(String(format: "%.2f", currentTrain))). Model may be too simple.")
                suggestions.append("Try increasing model capacity (more layers or larger hidden dim).")
            }

            if trainTrend == .stalling {
                suggestions.append("Loss plateaued. Try increasing learning rate or using LR scheduler.")
            }

            if trainTrend == .oscillating {
                suggestions.append("Loss is oscillating. Learning rate may be too high.")
            }

            confidence = 0.75
        }
        // 4. Oscillating (potential LR issue)
        else if trainTrend == .oscillating && valTrend == .oscillating {
            health = .underfitting
            suggestions.append("Both losses are oscillating unstably.")
            suggestions.append("Try reducing learning rate or using gradient clipping.")
            suggestions.append("Consider using a learning rate scheduler (e.g., cosine annealing).")
            confidence = 0.7
        }
        // 5. Healthy
        else {
            health = .healthy
            if trainTrend == .improving && valTrend == .improving {
                suggestions.append("Training is progressing well. Both losses decreasing.")
            } else if gapRatio < 0.05 {
                suggestions.append("Good generalization - train/val gap is small.")
            } else {
                suggestions.append("Training appears stable.")
            }
        }

        // Compute Quantitative Diagnostics (Bias/Variance decomposition)
        // Bias ≈ Training Error (high = model can't fit training data = underfitting)
        // Variance ≈ |Val - Train| gap (high = model doesn't generalize = overfitting)
        let bias = currentTrain
        let variance = abs(rawGap)  // Use absolute value to handle early training where val < train

        let diagnostics = Diagnostics(
            bias: bias,
            variance: variance,
            gapRatio: gapRatio,
            avgRecentLoss: avgRecentLoss,
            lossStdDev: lossStdDev
        )
        
        return AnalysisResult(
            trainTrend: trainTrend,
            valTrend: valTrend,
            health: health,
            suggestions: suggestions,
            confidence: confidence,
            diagnostics: diagnostics
        )
    }
    
    // MARK: - Helpers

    /// Detect overfitting using multiple signals
    private func detectOverfitting(
        trainTrend: Trend,
        valTrend: Trend,
        gapRatio: Float,
        currentTrain: Float,
        currentVal: Float,
        valLosses: [Float]
    ) -> Bool {
        // Classic overfitting: val increasing while train decreasing
        if (valTrend == .degrading || valTrend == .stalling) && trainTrend == .improving {
            if gapRatio > overfitThreshold {
                return true
            }
        }

        // Val loss consistently increasing over recent windows
        if valLosses.count >= 3 {
            let recentIncrease = valLosses.suffix(3).enumerated().allSatisfy { i, val in
                i == 0 || val >= valLosses[valLosses.count - 3 + i - 1]
            }
            if recentIncrease && currentVal > currentTrain * 1.2 {
                return true
            }
        }

        // Large gap even if both improving (early overfitting sign)
        if gapRatio > 0.25 && trainTrend == .improving {
            return true
        }

        return false
    }

    /// Detect underfitting using multiple signals
    private func detectUnderfitting(
        trainTrend: Trend,
        valTrend: Trend,
        currentTrain: Float,
        avgLoss: Float
    ) -> Bool {
        // Both stalling at high loss
        if trainTrend == .stalling && valTrend == .stalling {
            return true
        }

        // Loss is high and not improving
        if currentTrain > highLossThreshold && trainTrend != .improving {
            return true
        }

        // Plateau detection: average loss high and not changing
        if avgLoss > highLossThreshold * 0.8 && trainTrend == .stalling {
            return true
        }

        return false
    }

    /// Compute standard deviation of loss values
    private func computeStdDev(_ values: [Float]) -> Float {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Float(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(values.count)
        return sqrt(variance)
    }

    private func detectTrend(values: [Float]) -> Trend {
        guard values.count > 1 else { return .unknown }

        // Use both slope analysis and increase/decrease counting
        var increases = 0
        var decreases = 0

        for i in 1..<values.count {
            let diff = values[i] - values[i-1]
            if diff > 0.001 {  // Small threshold to ignore noise
                increases += 1
            } else if diff < -0.001 {
                decreases += 1
            }
        }

        let total = Float(values.count - 1)
        let incRatio = Float(increases) / total
        let decRatio = Float(decreases) / total

        // Calculate overall change
        let overallChange = values.last! - values.first!
        let relativeChange = abs(overallChange) / max(values.first!, 0.001)

        // Detect clear trends
        if incRatio > 0.6 && overallChange > 0 {
            return .degrading  // Loss increasing is bad
        } else if decRatio > 0.6 && overallChange < 0 {
            return .improving
        } else if relativeChange < plateauThreshold || (incRatio < 0.4 && decRatio < 0.4) {
            return .stalling  // Little net change
        } else {
            return .oscillating  // Alternating up/down
        }
    }
}
