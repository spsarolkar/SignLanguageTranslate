import SwiftUI
import AVKit
import Combine

struct VideoAnnotationPlayer: View {
    let videoURL: URL
    let features: [FrameFeatures]
    
    @State private var player: AVPlayer?
    @State private var currentFrameFeatures: FrameFeatures?
    @State private var showBody = true
    @State private var showHands = true
    @State private var isPlaying = false
    @State private var hasEnded = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 1
    
    // For efficient frame lookup
    @State private var lastFrameIndex = 0
    
    private let timeObserver = PassthroughSubject<Double, Never>()
    
    var body: some View {
        VStack {
            ZStack {
                // Video Layer
                if let player = player {
                    VideoPlayer(player: player)
                        .onAppear {
                            player.play()
                            isPlaying = true
                        }
                } else {
                    Color.black
                        .overlay {
                            ProgressView()
                        }
                }
                
                // Overlay Layer
                Canvas { context, size in
                    guard let frame = currentFrameFeatures else { return }
                    
                    if showBody {
                        KeypointVisualizer.drawBody(features: frame, in: context, size: size)
                    }
                    
                    if showHands {
                        KeypointVisualizer.drawHand(points: frame.leftHand, color: .blue, in: context, size: size)
                        KeypointVisualizer.drawHand(points: frame.rightHand, color: .orange, in: context, size: size)
                    }
                }
                .allowsHitTesting(false) // Let taps pass through to video controls
            }
            .aspectRatio(16/9, contentMode: .fit)
            .background(Color.black)
            .cornerRadius(12)
            
            // Controls
            HStack {
                Button(action: togglePlay) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                }
                
                // Replay button appears when video ends
                if hasEnded {
                    Button(action: replay) {
                        SwiftUI.Label("Replay", systemImage: "arrow.counterclockwise")
                            .font(.subheadline)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                
                Slider(value: Binding(get: { currentTime }, set: { seek(to: $0) }), in: 0...duration)
                
                Text(formatTime(currentTime))
                    .font(.caption.monospacedDigit())
            }
            .padding(.horizontal)
            
            // Toggles
            HStack {
                Toggle("Show Body", isOn: $showBody)
                    .toggleStyle(.button)
                    .font(.caption)
                
                Toggle("Show Hands", isOn: $showHands)
                    .toggleStyle(.button)
                    .font(.caption)
                
                Spacer()
                
                if let frame = currentFrameFeatures {
                    Text("Conf: \(String(format: "%.2f", avgConfidence(frame)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
        .onChange(of: videoURL) {
            setupPlayer()
        }
    }
    
    // MARK: - Logic
    
    private func setupPlayer() {
        player = AVPlayer(url: videoURL)
        
        // Duration loading
        Task {
            if let duration = try? await player?.currentItem?.asset.load(.duration) {
                await MainActor.run {
                    self.duration = CMTimeGetSeconds(duration)
                }
            }
        }
        
        // Observe playback end
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem,
            queue: .main
        ) { _ in
            self.hasEnded = true
            self.isPlaying = false
        }
        
        // Periodic Time Observer
        player?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.033, preferredTimescale: 600), queue: .main) { time in
            let seconds = CMTimeGetSeconds(time)
            self.currentTime = seconds
            self.updateOverlay(for: seconds)
            
            // Reset hasEnded when playback restarts
            if self.hasEnded && seconds < self.duration - 0.1 {
                self.hasEnded = false
            }
        }
    }
    
    private func replay() {
        player?.seek(to: .zero)
        player?.play()
        isPlaying = true
        hasEnded = false
    }
    
    private func togglePlay() {
        if isPlaying {
            player?.pause()
        } else {
            player?.play()
        }
        isPlaying.toggle()
    }
    
    private func seek(to time: Double) {
        player?.seek(to: CMTime(seconds: time, preferredTimescale: 600))
        currentTime = time
        updateOverlay(for: time)
    }
    
    private func updateOverlay(for time: Double) {
        // Find closest frame feature
        // Optimization: Start search from lastFrameIndex
        // Dictionary lookup might be faster if we mapped by discrete timestamps, 
        // but simple loop/linear scan from last index is robust for sequential playback
        
        guard !features.isEmpty else { return }
        
        // If we jumped back, reset index
        if lastFrameIndex >= features.count || features[lastFrameIndex].timestamp > time {
            lastFrameIndex = 0
        }
        
        // Scan forward
        var bestIndex = lastFrameIndex
        var minDiff = abs(features[lastFrameIndex].timestamp - time)
        
        for i in lastFrameIndex..<features.count {
            let diff = abs(features[i].timestamp - time)
            if diff < minDiff {
                minDiff = diff
                bestIndex = i
            } else if diff > minDiff + 0.1 {
                 // Optimization: if diff starts growing and is significantly larger, stop
                 break
            }
        }
        
        lastFrameIndex = bestIndex
        
        // Only show if reasonably close (e.g. within 100ms)
        if minDiff < 0.1 {
            currentFrameFeatures = features[bestIndex]
        } else {
            currentFrameFeatures = nil
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let min = Int(seconds) / 60
        let sec = Int(seconds) % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%d:%02d.%02d", min, sec, ms)
    }
    
    private func avgConfidence(_ frame: FrameFeatures) -> Float {
        let bodyConf = frame.body.reduce(0) { $0 + $1.confidence } / Float(max(1, frame.body.count))
        return bodyConf
    }
}
