import AVFoundation
import UIKit

/// Plays a silent audio track to keep the app active in the background.
/// Requires "Audio, AirPlay, and Picture in Picture" background mode.
class SilentAudioPlayer: NSObject {
    private var audioPlayer: AVAudioPlayer?
    private var isPlaying = false
    public private(set) var isSetupSuccessful = false
    public private(set) var setupError: String?
    
    override init() {
        super.init()
        setupAudioSession()
        setupInterruptionObserver()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupInterruptionObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        
        // Also handle Media Services Reset (rare but kills audio)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMediaServicesReset),
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: nil
        )
    }
    
    @objc private func handleInterruption(notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        
        switch type {
        case .began:
            print("[SilentAudio] Interruption began")
            // App might be suspended here if we don't handle it? 
            // Actually nothing to do but wait.
        case .ended:
            print("[SilentAudio] Interruption ended. Resuming...")
            if let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    audioPlayer?.play()
                }
            } else {
                // Try resuming anyway
                audioPlayer?.play()
            }
        @unknown default: break
        }
    }
    
    @objc private func handleMediaServicesReset(notification: Notification) {
        print("[SilentAudio] Media services reset. Re-initializing...")
        setupAudioSession()
        createSilentPlayer()
        if isPlaying {
            audioPlayer?.play()
        }
    }
    
    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // "Playback" category is required for background audio. 
            // "MixWithOthers" ensures we don't kill Spotify/Apple Music.
            // Explicitly setting mode to .default to avoid ambiguity (Error -50)
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers, .allowAirPlay])
            try session.setActive(true)
            
            isSetupSuccessful = true
            setupError = nil
            print("[SilentAudio] Audio session setup successfully.")
        } catch {
            print("[SilentAudio] Primary setup failed: \(error). Retrying with simpler config...")
            // Fallback: Try without AirPlay or specific options
            do {
                try session.setCategory(.playback, options: .mixWithOthers)
                try session.setActive(true)
                isSetupSuccessful = true
                setupError = nil
                print("[SilentAudio] Fallback setup successful.")
            } catch {
                 print("[SilentAudio] Fallback setup failed: \(error)")
                 isSetupSuccessful = false
                 setupError = error.localizedDescription
            }
        }
    }
    
    /// Starts playing silent audio in an infinite loop
    func start() {
        guard !isPlaying else { return }
        
        // We generate a tiny silent buffer directly in memory so we don't need a file resource
        // 44.1kHz, Mono, 16-bit
        if audioPlayer == nil {
            createSilentPlayer()
        }
        
        if let player = audioPlayer {
            player.numberOfLoops = -1 // Infinite loop
            player.play()
            isPlaying = true
            print("[SilentAudio] Background keep-alive started.")
        }
    }
    
    func stop() {
        guard isPlaying else { return }
        audioPlayer?.stop()
        isPlaying = false
        print("[SilentAudio] Background keep-alive stopped.")
    }
    
    private func createSilentPlayer() {
        // Minimal valid WAV header for 1 second of silence
        let sampleRate: Int32 = 44100
        let duration: Int32 = 1 // second
        let numSamples = sampleRate * duration
        let headerSize: Int32 = 44
        let dataSize = numSamples * 2 // 16-bit
        let fileSize = headerSize + dataSize
        
        var wavData = Data()
        
        // RIFF chunk
        wavData.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        wavData.append(contentsOf: withUnsafeBytes(of: fileSize - 8) { Array($0) })
        wavData.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
        
        // fmt chunk
        wavData.append(contentsOf: [0x66, 0x6d, 0x74, 0x20]) // "fmt "
        wavData.append(contentsOf: [16, 0, 0, 0]) // chunk size 16
        wavData.append(contentsOf: [1, 0]) // PCM
        wavData.append(contentsOf: [1, 0]) // Mono
        wavData.append(contentsOf: withUnsafeBytes(of: sampleRate) { Array($0) }) // Sample rate
        wavData.append(contentsOf: withUnsafeBytes(of: sampleRate * 2) { Array($0) }) // Byte rate
        wavData.append(contentsOf: [2, 0]) // Block align
        wavData.append(contentsOf: [16, 0]) // Bits per sample
        
        // data chunk
        wavData.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        wavData.append(contentsOf: withUnsafeBytes(of: dataSize) { Array($0) })
        wavData.append(contentsOf: Array(repeating: 0, count: Int(dataSize)))
        
        do {
            audioPlayer = try AVAudioPlayer(data: wavData)
            audioPlayer?.volume = 0.0 // Ensure silence
            audioPlayer?.prepareToPlay()
        } catch {
            print("[SilentAudio] Failed to create player: \(error)")
        }
    }
}
