import SwiftUI
import Charts

struct PCAScatterChart: View {
    let points: [FeatureAnalyzer.Point]
    
    var body: some View {
        Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                PointMark(
                    x: .value("Comp 1", point.x),
                    y: .value("Comp 2", point.y)
                )
                .foregroundStyle(.blue.opacity(0.5))
                .symbolSize(10)
            }
        }
        .chartXAxisLabel("Component 1")
        .chartYAxisLabel("Component 2")
    }
}
