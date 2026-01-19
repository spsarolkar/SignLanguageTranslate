import Foundation
import Vision
import AVFoundation

/// Extracts human hand pose landmarks using Apple's Vision framework
final class VisionHandExtractor {
    
    // MARK: - Properties
    
    /// The Vision request for hand pose detection
    private let handPoseRequest : VNDetectHumanHandPoseRequest = {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 2 // Detect both hands
        return request
    }()
    
    // MARK: - Public Methods
    
    /// Extract unified hand features from a CMSampleBuffer
    /// - Parameters:
    ///   - sampleBuffer: The video frame buffer
    ///   - timestamp: Timestamp of the frame
    /// - Returns: Tuple containing arrays of unified keypoints for left and right hands
    func extractHandFeatures(from sampleBuffer: CMSampleBuffer, timestamp: TimeInterval) throws -> (left: [UnifiedKeypoint]?, right: [UnifiedKeypoint]?) {
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up)
        
        try handler.perform([handPoseRequest])
        
        return try processObservations(handPoseRequest.results ?? [])
    }
    
    /// Extract unified hand features from a CGImage
    /// - Parameter image: The source image
    /// - Returns: Tuple containing arrays of unified keypoints for left and right hands
    func extractHandFeatures(from image: CGImage) throws -> (left: [UnifiedKeypoint]?, right: [UnifiedKeypoint]?) {
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        
        try handler.perform([handPoseRequest])
        
        return try processObservations(handPoseRequest.results ?? [])
    }
    
    // MARK: - Private Methods
    
    private func processObservations(_ observations: [VNHumanHandPoseObservation]) throws -> (left: [UnifiedKeypoint]?, right: [UnifiedKeypoint]?) {
        var leftHand: [UnifiedKeypoint]?
        var rightHand: [UnifiedKeypoint]?
        
        for observation in observations {
            let keypoints = try processSingleObservation(observation)
            
            // Vision typically identifies chirality (left/right) automatically
            // However, it can be unreliable or depend on context (camera mirror etc)
            // VNDetectHumanHandPoseRequest doesn't strictly explicitly separate "left" and "right" array outputs,
            // but VNHumanHandPoseObservation has a `chirality` property.
            
            if observation.chirality == .left {
                leftHand = keypoints
            } else {
                rightHand = keypoints
            }
        }
        
        return (left: leftHand, right: rightHand)
    }
    
    private func processSingleObservation(_ observation: VNHumanHandPoseObservation) throws -> [UnifiedKeypoint] {
        var keypoints: [UnifiedKeypoint] = []
        
        let joints = observation.availableJointNames
        for jointName in joints {
            let point = try observation.recognizedPoint(jointName)
            guard point.confidence > 0 else { continue }
            
            let unifiedKeypoint = UnifiedKeypoint(
                id: mapJointName(jointName),
                x: Float(point.x),
                y: Float(1.0 - point.y), // Flip Y for top-left origin
                z: nil,
                confidence: Float(point.confidence)
            )
            keypoints.append(unifiedKeypoint)
        }
        
        return keypoints
    }
    
    private func mapJointName(_ joint: VNHumanHandPoseObservation.JointName) -> String {
        switch joint {
        case .wrist: return KeypointNames.Hand.wrist
        case .thumbCMC: return KeypointNames.Hand.thumbCMC
        case .thumbMP: return KeypointNames.Hand.thumbMCP
        case .thumbIP: return KeypointNames.Hand.thumbIP
        case .thumbTip: return KeypointNames.Hand.thumbTip
        case .indexMCP: return KeypointNames.Hand.indexMCP
        case .indexPIP: return KeypointNames.Hand.indexPIP
        case .indexDIP: return KeypointNames.Hand.indexDIP
        case .indexTip: return KeypointNames.Hand.indexTip
        case .middleMCP: return KeypointNames.Hand.middleMCP
        case .middlePIP: return KeypointNames.Hand.middlePIP
        case .middleDIP: return KeypointNames.Hand.middleDIP
        case .middleTip: return KeypointNames.Hand.middleTip
        case .ringMCP: return KeypointNames.Hand.ringMCP
        case .ringPIP: return KeypointNames.Hand.ringPIP
        case .ringDIP: return KeypointNames.Hand.ringDIP
        case .ringTip: return KeypointNames.Hand.ringTip
        case .littleMCP: return KeypointNames.Hand.littleMCP
        case .littlePIP: return KeypointNames.Hand.littlePIP
        case .littleDIP: return KeypointNames.Hand.littleDIP
        case .littleTip: return KeypointNames.Hand.littleTip
        default: return joint.rawValue.rawValue
        }
    }
}
