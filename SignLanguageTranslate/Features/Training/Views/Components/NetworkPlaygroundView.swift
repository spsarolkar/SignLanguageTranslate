import SwiftUI
import Charts
import MLX
import MLXNN

/// Interactive Model Playground visualizing the neural network architecture and live stats.
struct NetworkPlaygroundView: View {
    let config: TrainingConfig
    
    // Live stats passed from Manager
    // In a real implementation, this would come from a publisher
    // For now, we simulate or assume static structure + some dynamic gradient info?
    // We'll visualize just the architecture for now.
    
    @State private var selectedLayer: Int?
    
    var body: some View {
        VStack(spacing: 0) {
            // Visualize Data Flow
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    // Input
                    NodeView(title: "Input", subtitle: "180 Features", type: .input)
                    
                    ConnectorView()
                    
                    // Hidden Layers
                    if config.useLegacyModel {
                        // LSTM Structure
                        ForEach(0..<config.numLayers, id: \.self) { i in
                            NodeView(
                                title: "LSTM Layer \(i+1)",
                                subtitle: "\(config.hiddenDim) Units",
                                type: .hidden,
                                isSelected: selectedLayer == i
                            )
                            .onTapGesture { selectedLayer = i }
                            
                            ConnectorView()
                        }
                    } else {
                        // Transformer Structure
                        ForEach(0..<config.numLayers, id: \.self) { i in
                            NodeView(
                                title: "Transformer Encoder \(i+1)",
                                subtitle: "\(config.numHeads!) Heads, \(config.hiddenDim) Dim",
                                type: .hidden,
                                isSelected: selectedLayer == i
                            )
                            .onTapGesture { selectedLayer = i }
                            
                            ConnectorView()
                        }
                    }
                    
                    // Classifier
                    NodeView(title: "Classifier", subtitle: "300 Classes", type: .output)
                }
                .padding()
            }
            .frame(height: 150)
            .background(Color(.secondarySystemBackground))
            
            Divider()
            
            // Layer Inspection (TensorFlow Playground Style)
            if let layer = selectedLayer {
                LayerInspectionView(layerIndex: layer, hiddenDim: config.hiddenDim)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                ContentUnavailableView(
                    "Select a Layer",
                    systemImage: "square.stack.3d.up.fill",
                    description: Text("Tap a layer to inspect its weights and gradients.")
                )
                .frame(maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Node Components

struct NodeView: View {
    let title: String
    let subtitle: String
    let type: NodeType
    var isSelected: Bool = false
    
    enum NodeType {
        case input, hidden, output
        
        var color: Color {
            switch self {
            case .input: return .blue
            case .hidden: return .purple
            case .output: return .orange
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(type.color.opacity(isSelected ? 0.3 : 0.1))
                    .stroke(type.color, lineWidth: isSelected ? 2 : 1)
                    .frame(width: 120, height: 80)
                
                Image(systemName: iconName)
                    .font(.title)
                    .foregroundStyle(type.color)
            }
            
            VStack(spacing: 2) {
                Text(title)
                    .font(.caption.bold())
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }
    
    var iconName: String {
        switch type {
        case .input: return "arrow.right.to.line"
        case .hidden: return "cpu"
        case .output: return "chart.bar.xaxis"
        }
    }
}

struct ConnectorView: View {
    var body: some View {
        Image(systemName: "arrow.right")
            .foregroundStyle(.secondary.opacity(0.3))
            .frame(width: 40)
    }
}

// MARK: - Inspection View

struct LayerInspectionView: View {
    let layerIndex: Int
    let hiddenDim: Int
    
    // Simulate distribution data
    @State private var weightDistribution: [Double] = []
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Layer \(layerIndex + 1) Analysis")
                        .font(.headline)
                    Spacer()
                    Text("\(hiddenDim) Neutrons")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                // Heatmap Simulation
                VStack(alignment: .leading) {
                    Text("Activation Heatmap (Sample)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 16), spacing: 2) {
                        ForEach(0..<min(hiddenDim, 256), id: \.self) { i in
                            Rectangle()
                                .fill(Color.purple.opacity(Double.random(in: 0.1...0.9))) // Simulation
                                .aspectRatio(1, contentMode: .fit)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                
                // Weight Distribution
                VStack(alignment: .leading) {
                    Text("Weight Distribution")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Chart {
                        ForEach(0..<20, id: \.self) { i in
                            BarMark(
                                x: .value("Bin", i),
                                y: .value("Count", Int.random(in: 10...100)) // Simulation
                            )
                            .foregroundStyle(.blue.gradient)
                        }
                    }
                    .frame(height: 150)
                }
            }
            .padding()
        }
        .background(Color(.systemBackground))
    }
}
