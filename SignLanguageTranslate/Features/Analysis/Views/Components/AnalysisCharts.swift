import SwiftUI
import Charts

// MARK: - Correlation Heatmap

struct CorrelationHeatmap: View {
    let matrix: [Float]
    let dimension: Int = 180
    
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let w = size.width
                let h = size.height
                let pixelW = w / Double(dimension)
                let pixelH = h / Double(dimension)
                
                // Draw only significant correlations to save perf?
                // Or just draw all.
                
                for row in 0..<dimension {
                    for col in 0..<dimension {
                        let index = row * dimension + col
                        if index < matrix.count {
                            let value = matrix[index]
                            let color = heatmapColor(for: value)
                            
                            let rect = CGRect(
                                x: Double(col) * pixelW,
                                y: Double(row) * pixelH,
                                width: pixelW + 0.5, // Slight overlap to avoid gaps
                                height: pixelH + 0.5
                            )
                            context.fill(Path(rect), with: .color(color))
                        }
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .drawingGroup() // Metal acceleration
    }
    
    private func heatmapColor(for value: Float) -> Color {
        // -1 (Blue) -> 0 (White/Black) -> +1 (Red)
        if value > 0 {
            return Color.red.opacity(Double(value))
        } else {
            return Color.blue.opacity(Double(abs(value)))
        }
    }
}

// MARK: - Variance Chart

struct FeatureVarianceChart: View {
    let variances: [Float]
    
    struct DataPoint: Identifiable {
        let id = UUID()
        let index: Int
        let value: Float
        let group: String
    }
    
    var data: [DataPoint] {
        variances.enumerated().compactMap { index, value in
            // Downsample for performance? Show every 3rd point?
            // 180 bars is fine on iPad.
            let group: String
            if index < 54 { group = "Body" }
            else if index < 117 { group = "Left Hand" }
            else { group = "Right Hand" }
            
            return DataPoint(index: index, value: value, group: group)
        }
    }
    
    var body: some View {
        Chart(data) { point in
            BarMark(
                x: .value("Feature", point.index),
                y: .value("Variance", point.value)
            )
            .foregroundStyle(by: .value("Group", point.group))
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: 20))
        }
        .chartForegroundStyleScale([
            "Body": .blue,
            "Left Hand": .green,
            "Right Hand": .orange
        ])
    }
}
