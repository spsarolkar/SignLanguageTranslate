import Foundation

/// A unified representation of a detected keypoint, independent of the underlying framework (Vision, MediaPipe, etc.)
public struct UnifiedKeypoint: Codable, Sendable {
    /// Standardized identifier for the keypoint (e.g., "nose", "left_shoulder")
    public let id: String
    
    /// Normalized X coordinate (0.0 - 1.0)
    public let x: Float
    
    /// Normalized Y coordinate (0.0 - 1.0)
    public let y: Float
    
    /// Optional normalized Z coordinate for 3D depth
    public let z: Float?
    
    /// Confidence score of the detection (0.0 - 1.0)
    public let confidence: Float
}

/// A collection of features detected in a single video frame
public struct FrameFeatures: Codable, Sendable {
    /// Timestamp of the frame in seconds
    public let timestamp: TimeInterval
    
    /// Detected body landmarks
    public let body: [UnifiedKeypoint]
    
    /// Detected left hand landmarks
    public let leftHand: [UnifiedKeypoint]?
    
    /// Detected right hand landmarks
    public let rightHand: [UnifiedKeypoint]?
    
    /// The source model that generated these features (e.g., "Vision.VNDetectHumanBodyPoseRequest")
    public let sourceModel: String
}

/// Constants for standardized keypoint names
enum KeypointNames {
    enum Body {
        static let nose = "nose"
        static let leftEye = "left_eye"
        static let rightEye = "right_eye"
        static let leftEar = "left_ear"
        static let rightEar = "right_ear"
        static let leftShoulder = "left_shoulder"
        static let rightShoulder = "right_shoulder"
        static let leftElbow = "left_elbow"
        static let rightElbow = "right_elbow"
        static let leftWrist = "left_wrist"
        static let rightWrist = "right_wrist"
        static let leftHip = "left_hip"
        static let rightHip = "right_hip"
        static let leftKnee = "left_knee"
        static let rightKnee = "right_knee"
        static let leftAnkle = "left_ankle"
        static let rightAnkle = "right_ankle"
        static let neck = "neck" // Custom/Derived
    }
    
    enum Hand {
        static let wrist = "wrist"
        static let thumbCMC = "thumb_cmc"
        static let thumbMCP = "thumb_mcp"
        static let thumbIP = "thumb_ip"
        static let thumbTip = "thumb_tip"
        static let indexMCP = "index_mcp"
        static let indexPIP = "index_pip"
        static let indexDIP = "index_dip"
        static let indexTip = "index_tip"
        static let middleMCP = "middle_mcp"
        static let middlePIP = "middle_pip"
        static let middleDIP = "middle_dip"
        static let middleTip = "middle_tip"
        static let ringMCP = "ring_mcp"
        static let ringPIP = "ring_pip"
        static let ringDIP = "ring_dip"
        static let ringTip = "ring_tip"
        static let littleMCP = "little_mcp"
        static let littlePIP = "little_pip"
        static let littleDIP = "little_dip"
        static let littleTip = "little_tip"
    }
}
