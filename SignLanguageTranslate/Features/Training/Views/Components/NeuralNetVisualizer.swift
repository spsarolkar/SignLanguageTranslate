import SwiftUI

/// A Canvas-based visualization of a Neural Network's "Neurons" and connections.
/// Similar to TensorFlow Playground, it draws layers as columns of circles and connections as lines.
struct NeuralNetVisualizer: View {
    let config: TrainingConfig
    
    // View State
    @State private var offset: CGSize = .zero
    @State private var scale: CGFloat = 1.0
    
    // Computed Properties for Layout
    private func layerCount() -> Int {
        // LSTM: Input -> [LSTM1, LSTM2] -> Output
        // Transformer: Input -> [Enc1, Enc2...] -> Output
        return config.useLegacyModel ? 2 + 2 : (config.numLayers + 2)
    }
    
    private func layerSize(at index: Int) -> Int {
        let total = layerCount()
        if index == 0 { return 180 } // Input
        if index == total - 1 { return 300 } // Output (GloVe dim)
        return config.hiddenDim
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background Grid
                Color(UIColor.secondarySystemBackground)
                
                // Canvas Drawing
                Canvas { context, size in
                    drawNetwork(in: context, size: size)
                }
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    DragGesture()
                        .onChanged { value in offset = value.translation }
                )
                
                // Controls Overlay
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Button(action: { scale *= 1.2 }) {
                                Image(systemName: "plus.magnifyingglass")
                                    .padding()
                                    .background(.thinMaterial)
                                    .clipShape(Circle())
                            }
                            Button(action: { scale /= 1.2 }) {
                                Image(systemName: "minus.magnifyingglass")
                                    .padding()
                                    .background(.thinMaterial)
                                    .clipShape(Circle())
                            }
                        }
                        .padding()
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    // MARK: - Drawing Logic
    
    private func drawNetwork(in context: GraphicsContext, size: CGSize) {
        let layers = layerCount()
        let layerWidth = size.width / CGFloat(layers + 1)
        
        var nodePositions: [[CGPoint]] = []
        
        // 1. Calculate Node Positions
        for l in 0..<layers {
            let x = layerWidth * CGFloat(l + 1)
            let neurons = layerSize(at: l)
            
            // Limit neurons drawn to avoid clutter (show representative subset if too large)
            let maxNeuronsToDraw = 20
            let drawnCount = min(neurons, maxNeuronsToDraw)
            
            let height = size.height * 0.8
            let spacing = height / CGFloat(drawnCount + 1)
            let startY = (size.height - height) / 2
            
            var currentLayerPositions: [CGPoint] = []
            
            for n in 0..<drawnCount {
                let y = startY + spacing * CGFloat(n + 1)
                currentLayerPositions.append(CGPoint(x: x, y: y))
            }
            nodePositions.append(currentLayerPositions)
        }
        
        // 2. Draw Connections (Lines)
        for l in 0..<layers-1 {
            let current = nodePositions[l]
            let next = nodePositions[l+1]
            
            for start in current {
                for end in next {
                    var path = Path()
                    path.move(to: start)
                    path.addLine(to: end)
                    
                    // Simulate weights with random opacity/color (since we don't stream real weights yet)
                    // In Phase 9 extension, we can hook this to actual model parameters
                    context.stroke(
                        path, 
                        with: .color(.gray.opacity(0.1)),
                        lineWidth: 1
                    )
                }
            }
        }
        
        // 3. Draw Nodes (Circles)
        for (l, positions) in nodePositions.enumerated() {
            let color = layerColor(at: l, total: layers)
            
            for p in positions {
                let rect = CGRect(x: p.x - 8, y: p.y - 8, width: 16, height: 16)
                context.fill(Path(ellipseIn: rect), with: .color(color))
                context.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: 2)
            }
            
            // Draw Layer Label
            if let first = positions.first {
                let text = Text(layerName(at: l, total: layers))
                    .font(.caption.bold())
                    .foregroundColor(.primary)
                
                context.draw(text, at: CGPoint(x: first.x, y: first.y - 35), anchor: .bottom)
                
                let countText = Text(layerSizeLabel(at: l, total: layers))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                context.draw(countText, at: CGPoint(x: first.x, y: first.y - 15), anchor: .bottom)
            }
        }
    }
    
    // MARK: - Helpers
    
    private func layerColor(at index: Int, total: Int) -> Color {
        if index == 0 { return .blue }
        if index == total - 1 { return .orange }
        return .purple
    }
    
    private func layerName(at index: Int, total: Int) -> String {
        if index == 0 { return "Input\n(180 feats × 60 frames)" } // Features x Frames
        if index == total - 1 { return "Output\n(300 dims)" } // GloVe Dim
        return "Hidden \(index)"
    }
    
    private func layerSizeLabel(at index: Int, total: Int) -> String {
        if index == 0 { return "10,800 units" } // 180 * 60 flattened equivalent context
        if index == total - 1 { return "300 units" }
        return "\(config.hiddenDim) units"
    }
}

#Preview {
    NeuralNetVisualizer(config: .default)
        .frame(height: 500)
}
