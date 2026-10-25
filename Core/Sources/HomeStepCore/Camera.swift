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
    public func scaled(fromImage imageWidth: Float, _ imageHeight: Float,
                       toDepth width: Int, _ height: Int) -> CameraIntrinsics? {
        guard imageWidth > 0, imageHeight > 0 else { return nil }
        let sx = Float(width) / imageWidth
        let sy = Float(height) / imageHeight
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

/// One LiDAR depth map, read in place: Float32 metres per pixel, row by row,
/// with ARKit's confidence (UInt8: 0 low, 1 medium, 2 high) where known.
///
/// A concrete type rather than a protocol, so the detector's per-pixel reads
/// are direct calls on the phone.
public struct DepthMap {
    public let width: Int
    public let height: Int
    private let depthBase: UnsafeRawPointer?
    private let depthRowBytes: Int
    private let confidenceBase: UnsafeRawPointer?
    private let confidenceRowBytes: Int

    /// The pointers must stay valid while the map is in use. A nil depth
    /// pointer gives an empty map.
    public init(width: Int, height: Int, depth: UnsafeRawPointer?, depthRowBytes: Int,
                confidence: UnsafeRawPointer? = nil, confidenceRowBytes: Int = 0) {
        self.width = depth == nil ? 0 : width
        self.height = depth == nil ? 0 : height
        depthBase = depth
        self.depthRowBytes = depthRowBytes
        confidenceBase = confidence
        self.confidenceRowBytes = confidenceRowBytes
    }

    func depth(x: Int, y: Int) -> Float {
        depthBase!.advanced(by: y * depthRowBytes).assumingMemoryBound(to: Float32.self)[x]
    }

    /// Nil when the map carries no confidence.
    func confidence(x: Int, y: Int) -> UInt8? {
        confidenceBase.map { $0.advanced(by: y * confidenceRowBytes).assumingMemoryBound(to: UInt8.self)[x] }
    }

    /// A map over plain arrays, valid inside `body`.
    public static func withArrays<R>(width: Int, height: Int, depths: [Float], confidences: [UInt8]? = nil,
                                     _ body: (DepthMap) -> R) -> R {
        precondition(depths.count == width * height)
        return depths.withUnsafeBytes { d in
            guard let confidences else {
                return body(DepthMap(width: width, height: height, depth: d.baseAddress,
                                     depthRowBytes: width * MemoryLayout<Float>.stride))
            }
            precondition(confidences.count == width * height)
            return confidences.withUnsafeBytes { c in
                body(DepthMap(width: width, height: height, depth: d.baseAddress,
                              depthRowBytes: width * MemoryLayout<Float>.stride,
                              confidence: c.baseAddress, confidenceRowBytes: width))
            }
        }
    }
}
