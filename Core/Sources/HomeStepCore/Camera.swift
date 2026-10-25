import Foundation
import simd

/// Pinhole camera intrinsics, in pixels.
public struct CameraIntrinsics: Equatable, Sendable {
    public var fx: Float
    public var fy: Float
    public var cx: Float
    public var cy: Float

    public init(fx: Float, fy: Float, cx: Float, cy: Float) {
        self.fx = fx
        self.fy = fy
        self.cx = cx
        self.cy = cy
    }

    /// ARKit's 3x3 matrix is column-major: fx at [0][0], cx at [2][0].
    public init(_ m: simd_float3x3) {
        self.init(fx: m[0][0], fy: m[1][1], cx: m[2][0], cy: m[2][1])
    }

    /// ARKit's intrinsics describe the colour image. The depth map shows the
    /// same view at a lower resolution, so they scale down with it.
    public func scaled(fromImage image: CGSize, toDepth width: Int, _ height: Int) -> CameraIntrinsics? {
        guard image.width > 0, image.height > 0 else { return nil }
        let sx = Float(width) / Float(image.width)
        let sy = Float(height) / Float(image.height)
        return CameraIntrinsics(fx: fx * sx, fy: fy * sy, cx: cx * sx, cy: cy * sy)
    }
}

/// Where the camera is and which way it faces at one moment, in ARKit's
/// gravity-aligned world: +Y is up however the phone is held.
public struct CameraPose: Sendable {
    public var transform: simd_float4x4
    public var timestamp: TimeInterval

    public init(transform: simd_float4x4, timestamp: TimeInterval) {
        self.transform = transform
        self.timestamp = timestamp
    }

    public var position: SIMD3<Float> { simd_make_float3(transform.columns.3) }

    /// The way the camera looks: its -Z axis.
    public var look: SIMD3<Float> { -simd_make_float3(transform.columns.2) }

    /// Degrees below horizontal that the camera looks.
    public var pitchDown: Float {
        let n = simd_length(look)
        guard n > 1e-4 else { return 0 }
        return asin(max(-1, min(1, -look.y / n))) * 180 / .pi
    }

    /// The world point seen at depth pixel (u, v), `depth` metres along the view.
    /// Camera space is +X right, +Y up, -Z forward; image rows count downward,
    /// hence the minus on y.
    public func worldPoint(u: Float, v: Float, depth: Float, intrinsics k: CameraIntrinsics) -> SIMD3<Float> {
        let x = (u - k.cx) * depth / k.fx
        let y = -(v - k.cy) * depth / k.fy
        return simd_make_float3(transform * SIMD4<Float>(x, y, -depth, 1))
    }
}

/// One LiDAR depth map: metres per pixel, with ARKit's confidence where known.
public protocol DepthFrame {
    var width: Int { get }
    var height: Int { get }
    func depth(x: Int, y: Int) -> Float
    /// 0 low, 1 medium, 2 high; nil when the frame carries no confidence map.
    func confidence(x: Int, y: Int) -> UInt8?
}

/// A depth map held in plain arrays, row by row.
public struct DepthGrid: DepthFrame {
    public let width: Int
    public let height: Int
    public var depths: [Float]
    public var confidences: [UInt8]?

    public init(width: Int, height: Int, depths: [Float], confidences: [UInt8]? = nil) {
        precondition(depths.count == width * height)
        self.width = width
        self.height = height
        self.depths = depths
        self.confidences = confidences
    }

    public func depth(x: Int, y: Int) -> Float { depths[y * width + x] }
    public func confidence(x: Int, y: Int) -> UInt8? { confidences?[y * width + x] }
}
