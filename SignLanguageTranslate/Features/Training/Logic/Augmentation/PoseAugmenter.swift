import Foundation

/// Handles geometric augmentation of pose landmarks to improve model robustness.
/// Supports rotation (tilt), scaling (distance), and translation (framing).
public struct PoseAugmenter {
    
    // MARK: - Configuration
    public struct Config {
        /// Max rotation in degrees (e.g., 15°)
        public var maxRotation: Float = 15.0
        /// Scale factor range (e.g., 0.8...1.2)
        public var scaleRange: ClosedRange<Float> = 0.8...1.2
        /// Translation range as fraction of frame (e.g., 0.1 = 10% shift)
        public var translationRange: Float = 0.1
        
        public static let `default` = Config()
    }
    
    // MARK: - API
    
    /// Applies random augmentations to a sequence of frames.
    /// - Note: Applying the SAME transformation to all frames in a clip is usually best
    /// to preserve temporal continuity, rather than jittering every frame differently.
    public static nonisolated func augment(frames: [FrameFeatures], config: Config = .default) -> [FrameFeatures] {
        // Generate random params once per clip
        let rotationAngle = Float.random(in: -config.maxRotation...config.maxRotation)
        let scale = Float.random(in: config.scaleRange)
        let shiftX = Float.random(in: -config.translationRange...config.translationRange)
        let shiftY = Float.random(in: -config.translationRange...config.translationRange)
        
        // Precompute rotation math
        let rad = rotationAngle * .pi / 180.0
        let cosA = cos(rad)
        let sinA = sin(rad)
        
        // Helper to transform points
        func transform(_ points: [UnifiedKeypoint]) -> [UnifiedKeypoint] {
            return points.map { p in
                // 1. Rotate (around center 0.5, 0.5)
                let cx: Float = 0.5
                let cy: Float = 0.5
                
                let dx = p.x - cx
                let dy = p.y - cy
                
                let rx = dx * cosA - dy * sinA
                let ry = dx * sinA + dy * cosA
                
                // 2. Scale
                let sx = rx * scale
                let sy = ry * scale
                
                // 3. Translate & Restore Center
                let finalX = sx + cx + shiftX
                let finalY = sy + cy + shiftY
                
                return UnifiedKeypoint(id: p.id, x: finalX, y: finalY, z: p.z, confidence: p.confidence)
            }
        }
        
        return frames.map { frame in
            // Transform non-optional body
            let newBody = transform(frame.body)
            
            // Transform optional hands
            let newLeft = frame.leftHand.map { transform($0) }
            let newRight = frame.rightHand.map { transform($0) }
            
            return FrameFeatures(
                timestamp: frame.timestamp,
                body: newBody,
                leftHand: newLeft,
                rightHand: newRight,
                sourceModel: frame.sourceModel
            )
        }
    }
}
