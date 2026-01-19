import Foundation
import Vision
import AVFoundation

/// Extracts human body pose landmarks using Apple's Vision framework
final class VisionPoseExtractor {
    
    // MARK: - Properties
    
    /// The Vision request for body pose detection
    private let bodyPoseRequest = VNDetectHumanBodyPoseRequest()
    
    // MARK: - Public Methods
    
    /// Extract unified body features from a CMSampleBuffer
    /// - Parameters:
    ///   - sampleBuffer: The video frame buffer
    ///   - timestamp: Timestamp of the frame
    /// - Returns: Array of unified keypoints (or empty if no body detected)
    func extractBodyFeatures(from sampleBuffer: CMSampleBuffer, timestamp: TimeInterval) throws -> [UnifiedKeypoint] {
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up)
        
        try handler.perform([bodyPoseRequest])
        
        guard let observation = bodyPoseRequest.results?.first else {
            return []
        }
        
        return try processObservation(observation)
    }
    
    /// Extract unified body features from a CGImage
    /// - Parameter image: The source image
    /// - Returns: Array of unified keypoints
    func extractBodyFeatures(from image: CGImage) throws -> [UnifiedKeypoint] {
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        
        try handler.perform([bodyPoseRequest])
        
        guard let observation = bodyPoseRequest.results?.first else {
            return []
        }
        
        return try processObservation(observation)
    }
    
    // MARK: - Private Methods
    
    private func processObservation(_ observation: VNHumanBodyPoseObservation) throws -> [UnifiedKeypoint] {
        var keypoints: [UnifiedKeypoint] = []
        
        let joints = observation.availableJointNames
        for jointName in joints {
            let point = try observation.recognizedPoint(jointName)
            guard point.confidence > 0 else { continue }
            
            // Normalize coordinates (Vision uses normalized 0.0-1.0, bottom-left origin)
            // We'll keep Vision's coordinate system for now or standardize if needed.
            // Standard computer vision usually uses top-left origin.
            // Vision: (0,0) is bottom-left, (1,1) is top-right.
            // Unified: Let's assume standard image coords: (0,0) top-left.
            // So y = 1.0 - point.y
            
            let unifiedKeypoint = UnifiedKeypoint(
                id: mapJointName(jointName),
                x: Float(point.x),
                y: Float(1.0 - point.y), // Flip Y to match top-left origin standard
                z: nil, // Vision 2D doesn't provide Z
                confidence: Float(point.confidence)
            )
            keypoints.append(unifiedKeypoint)
        }
        
        return keypoints
    }
    
    /// Map Vision joint names to our standardized IDs
    private func mapJointName(_ joint: VNHumanBodyPoseObservation.JointName) -> String {
        switch joint {
        case .nose: return KeypointNames.Body.nose
        case .leftEye: return KeypointNames.Body.leftEye
        case .rightEye: return KeypointNames.Body.rightEye
        case .leftEar: return KeypointNames.Body.leftEar
        case .rightEar: return KeypointNames.Body.rightEar
        case .leftShoulder: return KeypointNames.Body.leftShoulder
        case .rightShoulder: return KeypointNames.Body.rightShoulder
        case .leftElbow: return KeypointNames.Body.leftElbow
        case .rightElbow: return KeypointNames.Body.rightElbow
        case .leftWrist: return KeypointNames.Body.leftWrist
        case .rightWrist: return KeypointNames.Body.rightWrist
        case .leftHip: return KeypointNames.Body.leftHip
        case .rightHip: return KeypointNames.Body.rightHip
        case .leftKnee: return KeypointNames.Body.leftKnee
        case .rightKnee: return KeypointNames.Body.rightKnee
        case .leftAnkle: return KeypointNames.Body.leftAnkle
        case .rightAnkle: return KeypointNames.Body.rightAnkle
        case .neck: return KeypointNames.Body.neck
        default: return joint.rawValue.rawValue
        }
    }
}
