import SwiftUI
import SwiftData
import Combine
import AVKit

/// Real-time inference view for sign language recognition
/// Displays camera feed with pose overlay and predicted labels
struct InferenceView: View {
    @StateObject private var engine = InferenceEngine()
    @StateObject private var cameraManager = CameraInferenceManager()
    
    @State private var isRunning = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var selectedMode: Mode = .camera
    
    enum Mode: String, CaseIterable {
        case camera = "Live Camera"
        case video = "Video File"
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Camera/Video Feed
                ZStack(alignment: .topLeading) {
                    if selectedMode == .camera {
                        CameraPreviewView(manager: cameraManager)
                            .frame(maxWidth: .infinity)
                            .frame(height: 400)
                            .background(Color.black)
                    } else {
                        videoPlayerView
                    }
                    
                    // Mode Picker
                    Picker("Mode", selection: $selectedMode) {
                        ForEach(Mode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding()
                    .background(.ultraThinMaterial)
                }
                
                // Prediction Results
                predictionPanel
                
                Spacer()
                
                // Controls
                controlsPanel
            }
            .navigationTitle("Sign Recognition")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .task {
                await loadEngine()
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    // MARK: - Video Player
    
    @State private var videoURL: URL?
    
    private var videoPlayerView: some View {
        Group {
            if let url = videoURL {
                VideoPlayer(player: AVPlayer(url: url))
                    .frame(maxWidth: .infinity)
                    .frame(height: 400)
            } else {
                ContentUnavailableView(
                    "No Video Selected",
                    systemImage: "video.slash",
                    description: Text("Select a video file to analyze")
                )
                .frame(height: 400)
            }
        }
    }
    
    // MARK: - Prediction Panel
    
    private var predictionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Prediction")
                .font(.headline)
            
            if engine.isProcessing {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Processing...")
                        .foregroundStyle(.secondary)
                }
            } else if let prediction = engine.lastPrediction {
                VStack(alignment: .leading, spacing: 8) {
                    // Top prediction
                    HStack {
                        Text(prediction.label)
                            .font(.title.bold())
                            .foregroundStyle(.primary)
                        
                        Spacer()
                        
                        Text("\(Int(prediction.confidence))%")
                            .font(.title2.monospacedDigit())
                            .foregroundStyle(confidenceColor(prediction.confidence))
                    }
                    
                    // Top 3 alternatives
                    if prediction.topK.count > 1 {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Alternatives:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            ForEach(Array(prediction.topK.dropFirst().prefix(3).enumerated()), id: \.offset) { _, match in
                                HStack {
                                    Text(match.label)
                                        .font(.subheadline)
                                    Spacer()
                                    Text("\(Int(match.confidence))%")
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            } else {
                Text("No prediction yet")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
    }
    
    private func confidenceColor(_ confidence: Float) -> Color {
        if confidence >= 70 {
            return .green
        } else if confidence >= 40 {
            return .orange
        } else {
            return .red
        }
    }
    
    // MARK: - Controls
    
    private var controlsPanel: some View {
        VStack(spacing: 12) {
            // Vocabulary Info
            HStack {
                SwiftUI.Label("\(engine.vocabulary.count) signs", systemImage: "book")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                if engine.isModelLoaded {
                    SwiftUI.Label("Model Ready", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    SwiftUI.Label("Loading...", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            
            // Action Buttons
            HStack(spacing: 12) {
                Button(action: toggleInference) {
                    HStack {
                        Image(systemName: isRunning ? "stop.fill" : "play.fill")
                        Text(isRunning ? "Stop" : "Start")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .buttonStyle(.borderedProminent)
                .tint(isRunning ? .red : .blue)
                .disabled(!engine.isModelLoaded)
                
                if selectedMode == .video {
                    Button("Select Video") {
                        // File picker would go here
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding()
    }
    
    // MARK: - Actions
    
    private func loadEngine() async {
        do {
            try await engine.loadModel()
            
            // Load sample vocabulary (in production, load from dataset)
            await engine.addLabels([
                "Hello", "Thank You", "Please", "Dog", "Cat",
                "Yes", "No", "Help", "Water", "Food"
            ])
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
    
    private func toggleInference() {
        isRunning.toggle()
        
        if isRunning {
            startInference()
        } else {
            stopInference()
        }
    }
    
    private func startInference() {
        guard selectedMode == .camera else { return }
        cameraManager.startSession()
        
        // Start processing frames
        Task {
            for await prediction in engine.streamPredictions(
                frameStream: cameraManager.featureStream,
                windowSize: 30,
                stride: 10
            ) {
                // Predictions are automatically updated via @Published
                print("[InferenceView] Prediction: \(prediction.label) (\(prediction.confidence)%)")
            }
        }
    }
    
    private func stopInference() {
        cameraManager.stopSession()
    }
}

// MARK: - Camera Manager

@MainActor
class CameraInferenceManager: NSObject, ObservableObject {
    @Published var isRunning = false
    
    private var captureSession: AVCaptureSession?
    private var featureContinuation: AsyncStream<FrameFeatures>.Continuation?
    
    var featureStream: AsyncStream<FrameFeatures> {
        AsyncStream { continuation in
            self.featureContinuation = continuation
        }
    }
    
    func startSession() {
        // Camera setup would go here
        // For now, just mark as running
        isRunning = true
    }
    
    func stopSession() {
        isRunning = false
        featureContinuation?.finish()
    }
}

// MARK: - Camera Preview

struct CameraPreviewView: UIViewRepresentable {
    let manager: CameraInferenceManager
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        
        // Add "Camera Preview" placeholder
        let label = UILabel()
        label.text = "Camera Preview\n(Not Implemented)"
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Update camera preview if needed
    }
}

// MARK: - Preview

#Preview {
    InferenceView()
        .modelContainer(PersistenceController.preview.container)
}
