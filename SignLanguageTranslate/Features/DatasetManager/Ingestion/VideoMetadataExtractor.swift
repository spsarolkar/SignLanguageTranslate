import Foundation
import AVFoundation
import CoreGraphics

/// Metadata extracted from a video file
struct VideoMetadata: Sendable {
    /// Duration in seconds
    let duration: TimeInterval
    /// Video dimensions (width x height)
    let dimensions: CGSize
    /// Frame rate (frames per second)
    let frameRate: Float
    /// Video codec name (e.g., "hevc", "h264")
    let codec: String?
    /// File size in bytes
    let fileSize: Int64
    /// Whether the video has audio
    let hasAudio: Bool
    
    /// Formatted duration string (e.g., "1:23")
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    /// Formatted dimensions (e.g., "1920x1080")
    var formattedDimensions: String {
        "\(Int(dimensions.width))x\(Int(dimensions.height))"
    }
    
    /// Aspect ratio (e.g., 16:9, 4:3)
    var aspectRatio: String? {
        guard dimensions.width > 0 && dimensions.height > 0 else { return nil }
        
        let ratio = dimensions.width / dimensions.height
        
        // Common aspect ratios
        if abs(ratio - 16.0/9.0) < 0.01 {
            return "16:9"
        } else if abs(ratio - 4.0/3.0) < 0.01 {
            return "4:3"
        } else if abs(ratio - 1.0) < 0.01 {
            return "1:1"
        } else {
            return String(format: "%.2f:1", ratio)
        }
    }
}

/// Extracts metadata from video files using AVFoundation
struct VideoMetadataExtractor {
    
    // MARK: - Metadata Extraction
    
    /// Extract comprehensive metadata from a video file
    /// - Parameter url: URL of the video file
    /// - Returns: VideoMetadata struct with all available information
    /// - Throws: MetadataError if extraction fails
    static func extract(from url: URL) async throws -> VideoMetadata {
        // Ensure file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MetadataError.fileNotFound(url)
        }
        
        // Get file size
        let fileSize = try getFileSize(url)
        
        // Create AVAsset
        let asset = AVAsset(url: url)
        
        // Extract duration
        let duration: TimeInterval
        if #available(iOS 15.0, *) {
            duration = try await asset.load(.duration).seconds
        } else {
            duration = asset.duration.seconds
        }
        
        // Get video track
        guard let videoTrack = try await getVideoTrack(from: asset) else {
            throw MetadataError.noVideoTrack(url)
        }
        
        // Extract video properties
        let dimensions = try await getVideoDimensions(from: videoTrack)
        let frameRate = try await getFrameRate(from: videoTrack)
        let codec = try await getCodec(from: videoTrack)
        
        // Check for audio track
        let hasAudio = try await hasAudioTrack(asset)
        
        return VideoMetadata(
            duration: duration,
            dimensions: dimensions,
            frameRate: frameRate,
            codec: codec,
            fileSize: fileSize,
            hasAudio: hasAudio
        )
    }
    
    /// Extract a thumbnail image from a video
    /// - Parameters:
    ///   - url: URL of the video file
    ///   - time: Time in the video to extract thumbnail from (default: 0)
    /// - Returns: CGImage thumbnail, or nil if extraction fails
    /// - Throws: MetadataError if thumbnail generation fails
    static func extractThumbnail(
        from url: URL,
        at time: TimeInterval = 0
    ) async throws -> CGImage? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MetadataError.fileNotFound(url)
        }
        
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceAfter = .zero
        generator.requestedTimeToleranceBefore = .zero
        
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        
        do {
            let (image, _) = try await generator.image(at: cmTime)
            return image
        } catch {
            throw MetadataError.thumbnailFailed(url, error.localizedDescription)
        }
    }
    
    // MARK: - Private Helpers
    
    private static func getFileSize(_ url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? Int64 else {
            throw MetadataError.invalidFileAttributes(url)
        }
        return size
    }
    
    private static func getVideoTrack(from asset: AVAsset) async throws -> AVAssetTrack? {
        if #available(iOS 15.0, *) {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            return tracks.first
        } else {
            return asset.tracks(withMediaType: .video).first
        }
    }
    
    private static func getVideoDimensions(from track: AVAssetTrack) async throws -> CGSize {
        if #available(iOS 15.0, *) {
            return try await track.load(.naturalSize)
        } else {
            return track.naturalSize
        }
    }
    
    private static func getFrameRate(from track: AVAssetTrack) async throws -> Float {
        if #available(iOS 15.0, *) {
            return try await track.load(.nominalFrameRate)
        } else {
            return track.nominalFrameRate
        }
    }
    
    private static func getCodec(from track: AVAssetTrack) async throws -> String? {
        if #available(iOS 15.0, *) {
            let descriptions = try await track.load(.formatDescriptions)
            guard let description = descriptions.first else { return nil }
            let mediaSubType = CMFormatDescriptionGetMediaSubType(description)
            return fourCCToString(mediaSubType)
        } else {
            guard let description = track.formatDescriptions.first else {
                return nil
            }
            let mediaSubType = CMFormatDescriptionGetMediaSubType(description as! CMFormatDescription)
            return fourCCToString(mediaSubType)
        }
    }
    
    private static func hasAudioTrack(_ asset: AVAsset) async throws -> Bool {
        if #available(iOS 15.0, *) {
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            return !tracks.isEmpty
        } else {
            return !asset.tracks(withMediaType: .audio).isEmpty
        }
    }
    
    private static func fourCCToString(_ value: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ]
        return String(bytes: bytes, encoding: .ascii) ?? "unknown"
    }
    
    // MARK: - Validation
    
    /// Check if a file appears to be a valid video
    /// - Parameter url: File URL to check
    /// - Returns: True if the file can be opened as a video
    static func isValidVideo(_ url: URL) async -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return false
        }
        
        let asset = AVAsset(url: url)
        
        do {
            if #available(iOS 15.0, *) {
                let tracks = try await asset.loadTracks(withMediaType: .video)
                return !tracks.isEmpty
            } else {
                return !asset.tracks(withMediaType: .video).isEmpty
            }
        } catch {
            return false
        }
    }
}

// MARK: - Errors

enum MetadataError: LocalizedError {
    case fileNotFound(URL)
    case noVideoTrack(URL)
    case invalidFileAttributes(URL)
    case thumbnailFailed(URL, String)
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "Video file not found: \(url.lastPathComponent)"
        case .noVideoTrack(let url):
            return "No video track found in: \(url.lastPathComponent)"
        case .invalidFileAttributes(let url):
            return "Could not read file attributes: \(url.lastPathComponent)"
        case .thumbnailFailed(let url, let message):
            return "Failed to generate thumbnail for \(url.lastPathComponent): \(message)"
        }
    }
}
