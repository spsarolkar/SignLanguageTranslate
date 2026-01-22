import SwiftUI

/// Helper for visualizing keypoints and skeletons
struct KeypointVisualizer {
    
    /// Scale normalized keypoint to screen coordinates
    static func scale(point: UnifiedKeypoint, to size: CGSize) -> CGPoint {
        // UnifiedKeypoint uses (x, y) normalized 0...1 with origin top-left usually
        // If the coordinate system differs (e.g. Vision origin is bottom-left), we'd adjust here.
        // Assuming UnifiedKeypoint is already standardized to top-left origin.
        CGPoint(x: CGFloat(point.x) * size.width, y: CGFloat(point.y) * size.height)
    }
    
    /// Draw a skeleton for body pose
    static func drawBody(features: FrameFeatures, in context: GraphicsContext, size: CGSize) {
        let points = features.body
        guard !points.isEmpty else { return }
        
        let pointMap = Dictionary(uniqueKeysWithValues: points.map { ($0.id, $0) })
        
        // Define connections (Bone structure)
        let connections: [(String, String)] = [
            // Torso
            ("left_shoulder", "right_shoulder"),
            ("left_shoulder", "left_hip"),
            ("right_shoulder", "right_hip"),
            ("left_hip", "right_hip"),
            
            // Arms
            ("left_shoulder", "left_elbow"),
            ("left_elbow", "left_wrist"),
            ("right_shoulder", "right_elbow"),
            ("right_elbow", "right_wrist"),
            
            // Legs
            ("left_hip", "left_knee"),
            ("left_knee", "left_ankle"),
            ("right_hip", "right_knee"),
            ("right_knee", "right_ankle"),
            
            // Head (if available)
            ("nose", "left_eye"),
            ("nose", "right_eye"),
            ("left_eye", "left_ear"),
            ("right_eye", "right_ear")
        ]
        
        // Draw bones
        context.stroke(
            Path { path in
                for (startId, endId) in connections {
                    if let start = pointMap[startId], let end = pointMap[endId],
                       start.confidence > 0.3, end.confidence > 0.3 {
                        path.move(to: scale(point: start, to: size))
                        path.addLine(to: scale(point: end, to: size))
                    }
                }
            },
            with: .color(.green),
            lineWidth: 2
        )
        
        // Draw joints
        for point in points where point.confidence > 0.3 {
            let p = scale(point: point, to: size)
            let circle = Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6))
            context.fill(circle, with: .color(.red))
        }
    }
    
    /// Draw hand landmarks
    static func drawHand(points: [UnifiedKeypoint]?, color: Color, in context: GraphicsContext, size: CGSize) {
        guard let points = points, !points.isEmpty else { return }
        
        // Draw connections
        // Assuming standard 21 hand landmarks order or IDs
        // Simplification for now: draw lines between consecutive points for fingers
        // Wrist is usually root
        
        // Ideally we need id-based mapping if order isn't guaranteed
        // For unified model, let's look for standard IDs
        
        let fingers = [
            ["wrist", "thumb_cmc", "thumb_mcp", "thumb_ip", "thumb_tip"],
            ["wrist", "index_mcp", "index_pip", "index_dip", "index_tip"],
            ["wrist", "middle_mcp", "middle_pip", "middle_dip", "middle_tip"],
            ["wrist", "ring_mcp", "ring_pip", "ring_dip", "ring_tip"],
            ["wrist", "little_mcp", "little_pip", "little_dip", "little_tip"]
        ]
        
        let pointMap = Dictionary(uniqueKeysWithValues: points.map { ($0.id, $0) })
        
        context.stroke(
            Path { path in
                for finger in fingers {
                    var previousId: String? = nil
                    for id in finger {
                        if let prev = previousId,
                           let start = pointMap[prev], let end = pointMap[id],
                           start.confidence > 0.3, end.confidence > 0.3 {
                            path.move(to: scale(point: start, to: size))
                            path.addLine(to: scale(point: end, to: size))
                        }
                        previousId = id
                    }
                }
            },
            with: .color(color),
            lineWidth: 1.5
        )
        
        // Draw joints
        for point in points where point.confidence > 0.3 {
            let p = scale(point: point, to: size)
            let circle = Path(ellipseIn: CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4))
            context.fill(circle, with: .color(.yellow))
        }
    }
}
