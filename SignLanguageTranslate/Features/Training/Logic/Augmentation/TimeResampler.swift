import Foundation

/// Normalizes the temporal dimension of video features by resampling to a fixed number of frames.
/// Uses linear interpolation for smoother motion representation.
public struct TimeResampler {
    
    /// Resamples a sequence of frames to exactly `targetCount` frames.
    public static nonisolated func resample(_ frames: [FrameFeatures], targetCount: Int) -> [FrameFeatures] {
        guard !frames.isEmpty else { return [] }
        if frames.count == targetCount { return frames }
        if frames.count == 1 {
            return Array(repeating: frames[0], count: targetCount)
        }
        
        var resampled: [FrameFeatures] = []
        resampled.reserveCapacity(targetCount)
        
        let sourceDuration = Double(frames.count - 1)
        let targetDuration = Double(targetCount - 1)
        
        for i in 0..<targetCount {
            // Calculate position in source array (0.0 to sourceCount-1.0)
            let position = (Double(i) / targetDuration) * sourceDuration
            
            let indexLower = Int(floor(position))
            let indexUpper = min(indexLower + 1, frames.count - 1)
            let alpha = Float(position - Double(indexLower))
            
            if indexLower == indexUpper {
                resampled.append(frames[indexLower])
            } else {
                let frameA = frames[indexLower]
                let frameB = frames[indexUpper]
                resampled.append(interpolate(frameA, frameB, alpha: alpha))
            }
        }
        
        return resampled
    }
    
    private static func interpolate(_ a: FrameFeatures, _ b: FrameFeatures, alpha: Float) -> FrameFeatures {
        // Interpolate Body
        let newBody = interpolateKeypoints(a.body, b.body, alpha: alpha)
        
        // Interpolate Hands (handles missing hands by checking both)
        let newLeft = interpolateOptionalKeypoints(a.leftHand, b.leftHand, alpha: alpha)
        let newRight = interpolateOptionalKeypoints(a.rightHand, b.rightHand, alpha: alpha)
        // Note: Face removed as per PoseAugmenter decision (not used in current model)
        
        return FrameFeatures(
            timestamp: (1.0 - Double(alpha)) * a.timestamp + Double(alpha) * b.timestamp,
            body: newBody,
            leftHand: newLeft,
            rightHand: newRight,
            sourceModel: a.sourceModel
        )
    }
    
    // Interpolates two arrays of keypoints. Assumes same order/ids.
    private static func interpolateKeypoints(_ groupA: [UnifiedKeypoint], _ groupB: [UnifiedKeypoint], alpha: Float) -> [UnifiedKeypoint] {
        // If counts differ, we can't safely interpolate element-wise. Fallback to A or B based on alpha
        if groupA.count != groupB.count {
            return alpha < 0.5 ? groupA : groupB
        }
        
        return zip(groupA, groupB).map { (kA, kB) in
            guard kA.id == kB.id else { return kA } // Fallback if mismatch
            
            // Linear Interpolation: A + (B-A)*t
            let x = kA.x + (kB.x - kA.x) * alpha
            let y = kA.y + (kB.y - kA.y) * alpha
            
            // For Z, handle optionals
            let zA = kA.z ?? 0
            let zB = kB.z ?? 0
            let z = zA + (zB - zA) * alpha
            
            // Confidence can also be interpolated
            let conf = kA.confidence + (kB.confidence - kA.confidence) * alpha
            
            return UnifiedKeypoint(id: kA.id, x: x, y: y, z: z, confidence: conf)
        }
    }
    
    private static func interpolateOptionalKeypoints(_ groupA: [UnifiedKeypoint]?, _ groupB: [UnifiedKeypoint]?, alpha: Float) -> [UnifiedKeypoint]? {
        // If both exist, interpolate
        if let gA = groupA, let gB = groupB {
            return interpolateKeypoints(gA, gB, alpha: alpha)
        }
        // If only one exists, return it (implying presence > absence) or blend with 0?
        // Usually, if hand disappears, we might want to fade it out, but struct structure makes it optional.
        // Simple strategy: Propagate presence if visible in either frame (nearest neighbor logic for presence)
        return alpha < 0.5 ? groupA : groupB
    }
}
