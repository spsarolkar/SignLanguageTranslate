import Foundation
import AVFoundation

/// Service for processing video files to extract unified features (body and hands)
actor VideoFeatureExtractionService {
    
    // MARK: - Properties
    
    private let poseExtractor = VisionPoseExtractor()
    private let handExtractor = VisionHandExtractor()
    
    /// Errors that can occur during extraction
    enum ExtractionError: LocalizedError {
        case assetNotFound
        case unreadableAsset
        case noVideoTrack
        case readerInitializationFailed
        case cancelled
        case noDecodedFrames

        var errorDescription: String? {
            switch self {
            case .assetNotFound: return "The source video could not be found."
            case .unreadableAsset: return "The source video cannot be read."
            case .noVideoTrack: return "The file has no video track."
            case .readerInitializationFailed: return "The video decoder could not complete reading the clip."
            case .cancelled: return "Feature extraction was cancelled."
            case .noDecodedFrames: return "No video frames could be decoded. No features were saved; retry extraction or check the source video."
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// Extract features from a video file URL
    /// - Parameters:
    ///   - url: URL of the video file
    ///   - datasetName: Name of the dataset (for logging/metadata)
    ///   - onProgress: Callback for tracking progress (0.0 - 1.0)
    /// - Returns: Array of FrameFeatures (one per processed frame)
    func extractFeatures(
        from url: URL,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> [FrameFeatures] {
        try await readFrames(from: url, onProgress: onProgress) { sampleBuffer, timestamp in
            let body = try self.poseExtractor.extractBodyFeatures(from: sampleBuffer, timestamp: timestamp)
            let hands = try self.handExtractor.extractHandFeatures(from: sampleBuffer, timestamp: timestamp)
            return FrameFeatures(timestamp: timestamp, body: body, leftHand: hands.left,
                                 rightHand: hands.right, sourceModel: "AppleVision")
        }
    }

    /// Keep decoding testable on Simulator, where Vision pose models may be
    /// unavailable. Production always supplies the Vision processor above.
    func readFrames(
        from url: URL,
        onProgress: ((Double) -> Void)? = nil,
        processFrame: (CMSampleBuffer, TimeInterval) throws -> FrameFeatures
    ) async throws -> [FrameFeatures] {
        let asset = AVAsset(url: url)
        
        // Ensure asset is readable
        let isReadable = try await asset.load(.isReadable)
        guard isReadable else { throw ExtractionError.unreadableAsset }
        
        // Get video track
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ExtractionError.noVideoTrack
        }
        
        // Setup Asset Reader
        let reader = try AVAssetReader(asset: asset)
        
        // nil returns compressed samples for H.264/HEVC movies, which have no
        // CVPixelBuffer. Request decoded YUV pixels for Vision explicitly.
        let settings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ]
        
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        
        guard reader.canAdd(output) else { throw ExtractionError.readerInitializationFailed }
        reader.add(output)
        
        guard reader.startReading() else { throw ExtractionError.readerInitializationFailed }
        
        // Get duration for progress tracking
        let duration = try await asset.load(.duration).seconds
        var processedFrames: [FrameFeatures] = []
        
        var currentTime: TimeInterval = 0
        
        // Process frames
        while let sampleBuffer = output.copyNextSampleBuffer() {
            try autoreleasepool {
                if Task.isCancelled {
                    reader.cancelReading()
                    throw ExtractionError.cancelled
                }
                
                let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
                currentTime = timestamp
                
                // Validate Image Buffer
                guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                    return
                }
                
                // Validate dimensions to prevent "invalid image bits/pixel" errors
                let width = CVPixelBufferGetWidth(imageBuffer)
                let height = CVPixelBufferGetHeight(imageBuffer)
                let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer)
                
                guard width > 0, height > 0, bytesPerRow > 0 else {
                    return
                }

                processedFrames.append(try processFrame(sampleBuffer, timestamp))
                
                // Update progress
                if duration > 0 {
                    onProgress?(timestamp / duration)
                }
            }
        }
        
        if reader.status == .failed {
            throw reader.error ?? ExtractionError.readerInitializationFailed
        }
        guard !Task.isCancelled, reader.status != .cancelled else {
            throw ExtractionError.cancelled
        }
        guard reader.status == .completed else {
            throw ExtractionError.readerInitializationFailed
        }
        guard !processedFrames.isEmpty else { throw ExtractionError.noDecodedFrames }
        
        onProgress?(1.0)
        return processedFrames
    }
}
