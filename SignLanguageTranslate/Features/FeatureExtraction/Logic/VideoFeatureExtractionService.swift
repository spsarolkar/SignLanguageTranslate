import Foundation
import AVFoundation

/// Service for processing video files to extract unified features (body and hands)
actor VideoFeatureExtractionService {
    
    // MARK: - Properties
    
    private let poseExtractor = VisionPoseExtractor()
    private let handExtractor = VisionHandExtractor()
    
    /// Errors that can occur during extraction
    enum ExtractionError: Error {
        case assetNotFound
        case unreadableAsset
        case noVideoTrack
        case readerInitializationFailed
        case cancelled
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
        
        // Use native format (nil settings) for efficiency and stability with Vision
        // Vision handles YUV (420v/420f) natively and prefers it over BGRA
        let settings: [String: Any]? = nil 
        
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
            if Task.isCancelled {
                reader.cancelReading()
                throw ExtractionError.cancelled
            }
            
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
            currentTime = timestamp
            
            // Validate Image Buffer
            guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                continue
            }
            
            // Validate dimensions to prevent "invalid image bits/pixel" errors
            let width = CVPixelBufferGetWidth(imageBuffer)
            let height = CVPixelBufferGetHeight(imageBuffer)
            let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer)
            
            guard width > 0, height > 0, bytesPerRow > 0 else {
                continue
            }

            // Check for valid bytes per row if strict validation needed
            // But width/height > 0 covers most "empty" buffer cases.
            
            // Ensure buffer is backed by memory (not just metadata)
            // Vision handles standard CVPixelBuffers fine.
            
            // 1. Extract Body
            let bodyKeypoints = try poseExtractor.extractBodyFeatures(from: sampleBuffer, timestamp: timestamp)
            
            // 2. Extract Hands
            // Note: Vision works best if we reuse the handler, but our classes wrap the handler creation.
            // For optimization, we might eventually want to pass the same handler or request to a combined extractor.
            // For now, simple independent extraction is fine for M1.
            let handKeypoints = try handExtractor.extractHandFeatures(from: sampleBuffer, timestamp: timestamp)
            
            // 3. Aggregate
            let frameFeatures = FrameFeatures(
                timestamp: timestamp,
                body: bodyKeypoints,
                leftHand: handKeypoints.left,
                rightHand: handKeypoints.right,
                sourceModel: "AppleVision"
            )
            
            processedFrames.append(frameFeatures)
            
            // Update progress
            if duration > 0 {
                onProgress?(timestamp / duration)
            }
        }
        
        if reader.status == .failed {
            throw reader.error ?? ExtractionError.readerInitializationFailed
        }
        
        onProgress?(1.0)
        return processedFrames
    }
}
