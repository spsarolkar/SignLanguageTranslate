import SwiftUI

struct InsightsCardView: View {
    let insight: TrainingAnalyzer.AnalysisResult
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                SwiftUI.Label("Training Analyst", systemImage: "stethoscope")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                // Health Badge
                Text(insight.health.rawValue)
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(color(for: insight.health).opacity(0.2))
                    .foregroundStyle(color(for: insight.health))
                    .clipShape(Capsule())
            }
            
            Divider()
            
            // Trends
            HStack(spacing: 20) {
                trendItem(title: "Training", trend: insight.trainTrend)
                Divider()
                trendItem(title: "Validation", trend: insight.valTrend)
            }
            .padding(.vertical, 4)
            
            
            // Diagnostics (Bias/Variance)
            if let diagnostics = insight.diagnostics {
                Divider()

                VStack(spacing: 8) {
                    HStack(spacing: 16) {
                        metricItem(
                            title: "Bias",
                            subtitle: "Train Loss",
                            value: diagnostics.bias,
                            format: "%.3f",
                            isGood: diagnostics.bias < 1.0
                        )
                        Divider()
                        metricItem(
                            title: "Variance",
                            subtitle: "Val-Train Gap",
                            value: diagnostics.variance,
                            format: "%.3f",
                            isGood: diagnostics.variance < 0.2
                        )
                        Divider()
                        metricItem(
                            title: "Gap Ratio",
                            subtitle: "Overfit Risk",
                            value: diagnostics.gapRatio * 100,
                            format: "%.1f%%",
                            isGood: diagnostics.gapRatio < 0.15
                        )
                    }

                    if diagnostics.lossStdDev > 0.1 {
                        HStack {
                            Image(systemName: "waveform.path")
                                .foregroundStyle(.orange)
                            Text("High loss variance (\(String(format: "%.2f", diagnostics.lossStdDev))) - training may be unstable")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            
            // Suggestions
            if !insight.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Suggestions")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                    
                    ForEach(insight.suggestions, id: \.self) { suggestion in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "lightbulb.fill")
                                .foregroundStyle(.yellow)
                                .font(.caption)
                                .padding(.top, 2)
                            
                            Text(suggestion)
                                .font(.caption)
                                .foregroundStyle(.primary)
                        }
                    }
                }
                .padding(.top, 4)
                .transition(.opacity)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    // MARK: - Components
    
    private func trendItem(title: String, trend: TrainingAnalyzer.Trend) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text(trend.rawValue)
                    .font(.subheadline.bold())
            }
            
            Image(systemName: trend.icon)
                .font(.title2)
                .foregroundStyle(courseColor(for: trend))
        }
    }
    
    // MARK: - Helpers
    
    private func color(for health: TrainingAnalyzer.Health) -> Color {
        switch health {
        case .healthy: return .green
        case .overfitting: return .orange
        case .underfitting: return .yellow
        case .divergent: return .red
        case .unknown: return .gray
        }
    }
    
    private func courseColor(for trend: TrainingAnalyzer.Trend) -> Color {
        switch trend {
        case .improving: return .green
        case .stalling: return .orange
        case .degrading: return .red
        case .oscillating: return .purple
        case .unknown: return .gray
        }
    }
    
    private func metricItem(
        title: String,
        subtitle: String,
        value: Float,
        format: String,
        isGood: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Text(String(format: format, value))
                .font(.subheadline.bold())
                .foregroundStyle(isGood ? .green : .orange)
        }
    }
}

#Preview {
    VStack {
        InsightsCardView(insight: TrainingAnalyzer.AnalysisResult(
            trainTrend: .improving,
            valTrend: .degrading,
            health: .overfitting,
            suggestions: ["Validation loss rising.", "Increase Dropout to 0.3-0.5."],
            confidence: 0.9,
            diagnostics: TrainingAnalyzer.Diagnostics(
                bias: 0.45,
                variance: 0.32,
                gapRatio: 0.25,
                avgRecentLoss: 0.52,
                lossStdDev: 0.08
            )
        ))
        .padding()

        InsightsCardView(insight: TrainingAnalyzer.AnalysisResult(
            trainTrend: .improving,
            valTrend: .improving,
            health: .healthy,
            suggestions: ["Training is progressing well."],
            confidence: 1.0,
            diagnostics: TrainingAnalyzer.Diagnostics(
                bias: 0.35,
                variance: 0.05,
                gapRatio: 0.08,
                avgRecentLoss: 0.38,
                lossStdDev: 0.03
            )
        ))
        .padding()

        InsightsCardView(insight: TrainingAnalyzer.AnalysisResult(
            trainTrend: .stalling,
            valTrend: .stalling,
            health: .underfitting,
            suggestions: ["Loss plateaued.", "Increase learning rate or model capacity."],
            confidence: 0.75,
            diagnostics: TrainingAnalyzer.Diagnostics(
                bias: 2.5,
                variance: 0.1,
                gapRatio: 0.04,
                avgRecentLoss: 2.45,
                lossStdDev: 0.15
            )
        ))
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}
