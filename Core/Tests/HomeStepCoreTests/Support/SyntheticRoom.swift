import Foundation
import simd
@testable import HomeStepCore

/// A pretend room, rendered into depth frames the way the LiDAR would see it.
///
/// The walking direction is world -Z. `ahead` below means distance along it
/// from z = 0. The floor is a run of flat strips at different heights, so a
/// step is where one strip ends and the next begins. Boxes stand in for
/// furniture.
struct Room {
    struct Strip { var from: Float; var height: Float }
    struct Box { var min: SIMD3<Float>; var max: SIMD3<Float> }

    /// Sorted by `from`. The first strip covers everything before the second.
    var floor: [Strip]
    var boxes: [Box] = []
    /// Stretches of floor (by `ahead`) that return no depth at all.
    var voids: [ClosedRange<Float>] = []
    /// Spread of the depth noise, in metres. The phone measured about 5 mm.
    var noise: Float = 0.004

    static let floorHeight: Float = -0.92   // camera starts 0.92 m above the floor

    static func flat() -> Room {
        Room(floor: [Strip(from: -100, height: floorHeight)])
    }

    /// The floor drops by `depth` metres at `edge` ahead.
    static func stepDown(at edge: Float, depth: Float = 0.17) -> Room {
        Room(floor: [Strip(from: -100, height: floorHeight), Strip(from: edge, height: floorHeight - depth)])
    }

    /// The floor rises by `rise` metres at `edge` ahead.
    static func stepUp(at edge: Float, rise: Float = 0.17) -> Room {
        Room(floor: [Strip(from: -100, height: floorHeight), Strip(from: edge, height: floorHeight + rise)])
    }

    /// A box on the floor centred on the walking line.
    static func box(ahead: Float, depth: Float = 0.4, width: Float = 0.5, height: Float, x: Float = 0) -> Box {
        Box(min: SIMD3(x - width / 2, floorHeight, -(ahead + depth)),
            max: SIMD3(x + width / 2, floorHeight + height, -ahead))
    }

    /// Distance along a ray (in units of the ray's length) to the first surface,
    /// and whether that surface returns light.
    func hit(origin o: SIMD3<Float>, direction d: SIMD3<Float>) -> (t: Float, returns: Bool)? {
        var best: (t: Float, returns: Bool)?
        func consider(_ t: Float, _ returns: Bool) {
            guard t > 1e-4, best == nil || t < best!.t else { return }
            best = (t, returns)
        }
        func ahead(_ t: Float) -> Float { -(o.z + t * d.z) }

        for (i, strip) in floor.enumerated() {
            let end = i + 1 < floor.count ? floor[i + 1].from : .greatestFiniteMagnitude
            // The strip's top surface.
            if abs(d.y) > 1e-6 {
                let t = (strip.height - o.y) / d.y
                let a = ahead(t)
                if a >= strip.from, a < end {
                    consider(t, !voids.contains { $0.contains(a) })
                }
            }
            // The riser where this strip starts.
            if i > 0, abs(d.z) > 1e-6 {
                let t = (-strip.from - o.z) / d.z
                let y = o.y + t * d.y
                let lo = min(floor[i - 1].height, strip.height), hi = max(floor[i - 1].height, strip.height)
                if y >= lo, y <= hi { consider(t, true) }
            }
        }
        for box in boxes {
            var tNear: Float = -.greatestFiniteMagnitude, tFar: Float = .greatestFiniteMagnitude
            var inside = true
            for axis in 0..<3 {
                if abs(d[axis]) < 1e-9 {
                    if o[axis] < box.min[axis] || o[axis] > box.max[axis] { inside = false }
                    continue
                }
                var t1 = (box.min[axis] - o[axis]) / d[axis]
                var t2 = (box.max[axis] - o[axis]) / d[axis]
                if t1 > t2 { swap(&t1, &t2) }
                tNear = max(tNear, t1)
                tFar = min(tFar, t2)
            }
            if inside, tNear <= tFar, tNear > 0 { consider(tNear, true) }
        }
        return best
    }
}

/// A camera on the stick, posed in the room.
struct Rig {
    /// A LiDAR depth map is 256 x 192. These intrinsics match an iPhone's wide
    /// camera (about 1450 px focal length at 1920 x 1440) scaled down to it.
    static let width = 256, height = 192
    static let intrinsics = CameraIntrinsics(fx: 193.3, fy: 193.3, cx: 128, cy: 96)

    /// - Parameters:
    ///   - pitch: degrees below horizontal (about 45 on the real mount).
    ///   - yaw: degrees left of the walking line, positive turns left.
    ///   - roll: 90 holds the phone upright, as on the stick.
    static func pose(at position: SIMD3<Float> = .zero, pitch: Float = 45, yaw: Float = 0,
                     roll: Float = 90, time: TimeInterval = 0) -> CameraPose {
        let rad: (Float) -> Float = { $0 * .pi / 180 }
        let q = simd_quatf(angle: rad(yaw), axis: SIMD3(0, 1, 0))
            * simd_quatf(angle: -rad(pitch), axis: SIMD3(1, 0, 0))
            * simd_quatf(angle: rad(roll), axis: SIMD3(0, 0, 1))
        var m = simd_float4x4(q)
        m.columns.3 = SIMD4(position, 1)
        return CameraPose(transform: m, timestamp: time)
    }
}

/// What the LiDAR returns for one pose in one room. Only every other pixel
/// each way is rendered (the rest are NaN), since that is all the detector
/// reads at its default stride.
struct RenderedDepth {
    let room: Room
    let pose: CameraPose
    var seed: UInt32 = 0
    /// Confidence for every pixel (2 = high).
    var confidenceLevel: UInt8? = 2
    let width = Rig.width
    let height = Rig.height

    func depth(x: Int, y: Int) -> Float {
        let k = Rig.intrinsics
        // A ray through the pixel with camera-space z = -1, so the hit
        // distance along it equals the depth ARKit would report.
        let cam = SIMD4<Float>((Float(x) - k.cx) / k.fx, -(Float(y) - k.cy) / k.fy, -1, 0)
        let dir = simd_make_float3(pose.transform * cam)
        guard let hit = room.hit(origin: pose.position, direction: dir), hit.returns else { return 0 }
        return hit.t + room.noise * jitter(x, y)
    }

    /// The rendered frame as a `DepthMap`, valid inside `body`.
    func withMap<R>(_ body: (DepthMap) -> R) -> R {
        var depths = [Float](repeating: .nan, count: width * height)
        for y in stride(from: 0, to: height, by: 2) {
            for x in stride(from: 0, to: width, by: 2) {
                depths[y * width + x] = depth(x: x, y: y)
            }
        }
        let confidences = confidenceLevel.map { [UInt8](repeating: $0, count: width * height) }
        return DepthMap.withArrays(width: width, height: height, depths: depths, confidences: confidences, body)
    }

    /// Repeatable noise in -1...1, different for every pixel and frame.
    private func jitter(_ x: Int, _ y: Int) -> Float {
        var h = UInt32(truncatingIfNeeded: x &* 73_856_093) ^ UInt32(truncatingIfNeeded: y &* 19_349_663) ^ (seed &* 83_492_791)
        h ^= h >> 13
        h = h &* 0x5bd1_e995
        h ^= h >> 15
        return Float(h % 20_001) / 10_000 - 1
    }
}

/// Feeds the detector a sequence of frames and keeps what it said.
struct Walk {
    struct Frame {
        var time: TimeInterval
        /// How far the camera has travelled along the walking line.
        var position: Float
        var outcome: StepDetector.Outcome
    }

    var detector = StepDetector()
    var warnDistance: Float = 0.45
    private var frameCount: UInt32 = 0

    /// One frame at a fixed pose.
    mutating func look(_ room: Room, pose: CameraPose, capture: Bool = false) -> StepDetector.Outcome {
        frameCount += 1
        let depth = RenderedDepth(room: room, pose: pose, seed: frameCount)
        return depth.withMap {
            detector.process(depth: $0, camera: pose, intrinsics: Rig.intrinsics,
                             warnDistance: warnDistance, captureSnapshot: capture)
        }
    }

    /// The same view `count` times, a sixtieth of a second apart.
    mutating func hold(_ room: Room, pose: CameraPose, frames count: Int) -> [StepDetector.Outcome] {
        (0..<count).map { i in
            var p = pose
            p.timestamp = pose.timestamp + Double(i) / 60
            return look(room, pose: p)
        }
    }

    /// Walk along the line from `start` to `end` metres at `speed` m/s, the
    /// cane sweeping `sweep` degrees each side once a second.
    mutating func walk(_ room: Room, from start: Float, to end: Float, speed: Float = 0.5,
                       sweep: Float = 15, pitch: Float = 45, fps: Double = 60) -> [Frame] {
        var frames: [Frame] = []
        let duration = Double((end - start) / speed)
        var t = 0.0
        while t <= duration {
            let along = start + speed * Float(t)
            let phase = Float(2 * Double.pi * t)          // one sweep a second
            let yaw = sweep * sin(phase)
            // The phone rides the stick, so it moves sideways with the sweep too.
            let x = -0.25 * sin(yaw * .pi / 180)
            let pose = Rig.pose(at: SIMD3(x, 0, -along), pitch: pitch, yaw: yaw, time: t)
            frames.append(Frame(time: t, position: along, outcome: look(room, pose: pose)))
            t += 1 / fps
        }
        return frames
    }
}

extension StepDetector.Outcome {
    var step: (text: String, distance: Float, speak: Bool)? {
        if case .step(let text, let d, let speak) = event { return (text, d, speak) }
        return nil
    }

    var obstacle: (distance: Float, intensity: Float)? {
        if case .proximity(let d, let i) = event { return (d, i) }
        return nil
    }
}
