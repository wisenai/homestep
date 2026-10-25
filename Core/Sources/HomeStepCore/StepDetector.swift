import Foundation
import simd

/// Finds steps and obstacles in the floor ahead, one LiDAR frame at a time.
///
/// Every depth pixel is turned into a point in ARKit's gravity-aligned world,
/// where height doesn't change when the cane tilts. The detector then compares
/// two strips of floor from the same frame: the reference strip just ahead of
/// the stick, and the probe strip further out. If the probe sits lower, there
/// is a step down; higher, a step up. Because both strips come from one frame,
/// any error in the phone's position moves both by the same amount and cancels.
///
/// The full rules and their reasons are in docs/specs/step-detector.md.
public struct StepDetector {

    /// Every tunable number, in metres unless noted. The defaults lean towards
    /// warning early.
    public struct Settings: Equatable, Sendable {
        /// Start of the reference strip, measured ahead of the camera.
        public var probeMin: Float = 0.25
        /// Depth of the reference strip. Everything past it, out to the warn
        /// distance plus `beepLeadIn`, is the probe strip.
        public var referenceDepth: Float = 0.15
        /// Half-width of the corridor watched either side of the walking line.
        public var halfWidth: Float = 0.35

        /// Range of the on-screen "speak at" control.
        public var minWarnDistance: Float = 0.30
        public var maxWarnDistance: Float = 0.90
        public var defaultWarnDistance: Float = 0.45
        /// The probe reaches this far past the speaking distance, so the edge
        /// is heard beeping before it is named.
        public var beepLeadIn: Float = 0.25

        /// How far below the reference the floor must be to count as a step down.
        /// Our step is about 0.17 m; flat floor varies by about 0.005 m.
        public var stepDownDrop: Float = 0.07
        /// Share of the probe strip that must be that low. Noise is scattered;
        /// a real edge is a cluster.
        public var stepDownCoverage: Float = 0.15

        /// How far above the reference the floor must be to count as a step up.
        public var stepUpRise: Float = 0.07
        /// Anything taller is furniture or a wall, not a step.
        public var maxStepUp: Float = 0.22
        /// Share of the probe strip that must be raised. A step lifts all of it;
        /// a chair seat lifts only a patch.
        public var stepUpCoverage: Float = 0.60

        /// A surface must be this far below the camera to be ground at all, so
        /// a tabletop never becomes the floor.
        public var minCameraAboveGround: Float = 0.35

        /// Something this tall above the floor, within `obstacleRange` ahead,
        /// is an obstacle.
        public var obstacleMinHeight: Float = 0.25
        public var obstacleRange: Float = 0.90
        /// Frames an obstacle must persist. A sweep drags the corridor across
        /// door frames for a frame or two at a time.
        public var obstacleFramesToConfirm = 3

        /// Fewest ground points a strip needs before it is trusted.
        public var minValidSamples = 12
        /// Depth readings outside this range are ignored.
        public var minDepth: Float = 0.1
        public var maxDepth: Float = 5.0
        /// Read every nth pixel in each direction.
        public var sampleStride = 2
        /// Skip readings ARKit marks as low confidence.
        public var requireMediumConfidence = true

        /// If the probe strip returns nothing while the path is clear, treat it
        /// as a drop: an edge can send the light off into empty space.
        public var treatVoidAsDrop = true

        /// Frames a step must hold before it is reported.
        public var framesToConfirm = 3
        /// Above this sweep rate the depth image smears, so ask for more frames.
        public var fastSwingDegPerSec: Float = 60
        public var extraFramesWhenSwinging = 2

        /// Ground speed (m/s) that counts as walking. "Proceed" is only said to
        /// someone who is moving.
        public var walkingSpeed: Float = 0.10
        /// Frames of speed history in the walking test.
        public var speedSmoothingFrames = 20

        public init() {}

        /// The warn distance kept inside the control's range.
        public func clampWarnDistance(_ value: Float) -> Float {
            min(maxWarnDistance, max(minWarnDistance, value))
        }
    }

    public enum StepKind: Sendable, Equatable {
        case down, up

        public var spoken: String {
            switch self {
            case .down: return "Step down."
            case .up: return "Step up."
            }
        }
    }

    /// What one frame measured. For the screen and the log; no decision reads it.
    public struct Reading: Sendable, Equatable {
        /// Height of the floor just ahead (median of the reference strip).
        public var floorReference: Float?
        /// Median height of the probe strip.
        public var floorNow: Float?
        /// 15th-percentile height of the probe strip.
        public var probeLow: Float?
        /// Reference minus `probeLow`: positive when the floor ahead is lower.
        public var dropVsReference: Float?
        public var obstacleAhead: Float?
        public var stepDistance: Float?
        public var groundCount: Int
        public var nearCount: Int
        public var farCount: Int
        /// Share of the probe strip below / above the step thresholds.
        public var fallCoverage: Float?
        public var riseCoverage: Float?
        public var pitchDegrees: Float
        public var swingDegreesPerSecond: Float
        public var groundSpeed: Float
        public var isWalking: Bool
    }

    public struct Outcome {
        public var event: AnnouncerEvent?
        public var reading: Reading
        /// Filled only when asked for, for "See what HomeStep sees".
        public var snapshot: DetectorSnapshot?
    }

    public var settings: Settings

    // State carried between frames.
    private var stepStreak = 0
    private var obstacleStreak = 0
    private var lastStepKind: StepKind?
    private var lastHeading: (forward: SIMD3<Float>, time: TimeInterval)?
    private var lastPosition: (position: SIMD3<Float>, time: TimeInterval)?
    private var speedHistory: [Float] = []

    public init(settings: Settings = Settings()) {
        self.settings = settings
    }

    /// Forget everything learned from earlier frames. Called on Start and after
    /// an interruption, when the floor seen before can't be trusted.
    /// The last position is kept: it only feeds walking speed, and a gap of more
    /// than half a second is ignored there anyway.
    public mutating func reset() {
        stepStreak = 0
        obstacleStreak = 0
        speedHistory = []
        lastStepKind = nil
        lastHeading = nil
    }

    /// Look at one frame.
    ///
    /// - Parameters:
    ///   - intrinsics: already scaled to the depth map; nil skips the survey.
    ///   - warnDistance: how far ahead a step is spoken.
    ///   - captureSnapshot: also return the classified points, for display.
    public mutating func process<F: DepthFrame>(
        depth: F, camera: CameraPose, intrinsics: CameraIntrinsics?,
        warnDistance: Float, captureSnapshot: Bool = false
    ) -> Outcome {
        let s = settings
        let survey = surveyGround(depth, camera: camera, intrinsics: intrinsics,
                                  probeMax: warnDistance + s.beepLeadIn, capture: captureSnapshot)
        let swing = swingRate(camera)
        let speed = groundSpeed(camera)
        let walking = speed >= s.walkingSpeed

        let reference = percentile(survey.nearGround, 0.5)
        let farHeights = survey.farGround.map(\.height)
        let probeMedian = percentile(farHeights, 0.5)

        // Obstacles stand up from the floor; a step down is below it, so the
        // two can't be confused. With no floor in view nothing is decided:
        // a swept cane loses the floor for a frame or two all the time.
        var obstacle: Float?
        if let floor = reference ?? probeMedian {
            obstacle = survey.candidates
                .filter { $0.height > floor + s.obstacleMinHeight && $0.ahead <= s.obstacleRange }
                .map(\.ahead).min()
        }
        obstacleStreak = obstacle != nil ? obstacleStreak + 1 : 0
        if obstacleStreak < s.obstacleFramesToConfirm { obstacle = nil }

        var drop: Float?
        var fallCoverage: Float?
        var riseCoverage: Float?
        var stepDistance: Float?
        let step: StepKind?
        if let reference, survey.farGround.count >= s.minValidSamples {
            let count = Float(survey.farGround.count)
            let low = survey.farGround.filter { $0.height < reference - s.stepDownDrop }
            let high = survey.farGround.filter { $0.height > reference + s.stepUpRise }
            fallCoverage = Float(low.count) / count
            riseCoverage = Float(high.count) / count
            drop = reference - (percentile(farHeights, 0.15) ?? reference)
            let rise = (probeMedian ?? reference) - reference

            if fallCoverage! >= s.stepDownCoverage {
                step = .down
                // The near edge of the drop: how far his foot is from it.
                stepDistance = low.map(\.ahead).min()
            } else if riseCoverage! >= s.stepUpCoverage, rise > s.stepUpRise, rise <= s.maxStepUp {
                step = .up
                stepDistance = high.map(\.ahead).min()
            } else {
                step = nil
            }
        } else if s.treatVoidAsDrop, reference != nil,
                  survey.farGround.count < s.minValidSamples, obstacle == nil {
            // The floor ahead vanished and nothing is in the way to hide it.
            step = .down
            stepDistance = s.probeMin + s.referenceDepth
        } else {
            step = nil
        }

        var snapshot: DetectorSnapshot?
        if !survey.samples.isEmpty {
            snapshot = DetectorSnapshot.build(
                samples: survey.samples, reference: reference, drop: drop,
                stepDistance: stepDistance, obstacle: obstacle, warnDistance: warnDistance,
                rules: .init(stepDownDrop: s.stepDownDrop, stepUpRise: s.stepUpRise,
                             obstacleMinHeight: s.obstacleMinHeight, obstacleRange: s.obstacleRange))
        }

        let reading = Reading(
            floorReference: reference, floorNow: probeMedian,
            probeLow: percentile(farHeights, 0.15), dropVsReference: drop,
            obstacleAhead: obstacle, stepDistance: stepDistance,
            groundCount: survey.nearGround.count + survey.farGround.count,
            nearCount: survey.nearGround.count, farCount: survey.farGround.count,
            fallCoverage: fallCoverage, riseCoverage: riseCoverage,
            pitchDegrees: camera.pitchDown, swingDegreesPerSecond: swing,
            groundSpeed: speed, isWalking: walking)

        // A step must hold for several frames in a row, more while the cane is
        // sweeping fast. Changing direction starts the count again, so "Step up"
        // is never said on the strength of step-down frames.
        let needed = s.framesToConfirm + (swing > s.fastSwingDegPerSec ? s.extraFramesWhenSwinging : 0)
        stepStreak = step == nil ? 0 : (lastStepKind == step ? stepStreak + 1 : 1)
        lastStepKind = step
        if let step, stepStreak >= needed {
            let distance = stepDistance ?? s.probeMin
            // Beep as soon as the edge is in view; say the words once it is close.
            let event = AnnouncerEvent.step(text: step.spoken, distance: distance,
                                            speak: distance <= warnDistance)
            return Outcome(event: event, reading: reading, snapshot: snapshot)
        }

        if let obstacle {
            let closeness = max(0, min(1, 1 - obstacle / s.obstacleRange))
            return Outcome(event: .proximity(distance: obstacle, intensity: closeness),
                           reading: reading, snapshot: snapshot)
        }

        // All clear, and only for someone walking: telling a person who has
        // stopped to "proceed" would override their own decision.
        if walking, survey.nearGround.count >= s.minValidSamples {
            return Outcome(event: .clear, reading: reading, snapshot: snapshot)
        }
        return Outcome(event: nil, reading: reading, snapshot: snapshot)
    }

    // MARK: - Survey

    private struct Point { let ahead: Float; let height: Float }

    private struct Survey {
        var nearGround: [Float] = []
        var farGround: [Point] = []
        var candidates: [Point] = []
        var samples: [DetectorSnapshot.Sample] = []
    }

    /// Turn the depth map into world points and sort the useful ones into the
    /// reference strip, the probe strip and the obstacle corridor.
    private func surveyGround<F: DepthFrame>(_ frame: F, camera: CameraPose, intrinsics: CameraIntrinsics?,
                                             probeMax: Float, capture: Bool) -> Survey {
        var survey = Survey()
        let s = settings
        guard frame.width > 0, frame.height > 0,
              let k = intrinsics, k.fx != 0, k.fy != 0 else { return survey }

        let camPos = camera.position
        // "Ahead" is measured along the walking direction, flattened onto the
        // floor, so it doesn't depend on how the cane is pitched.
        let look = camera.look
        var forward = SIMD3<Float>(look.x, 0, look.z)
        guard simd_length(forward) > 1e-4 else { return survey }
        forward = simd_normalize(forward)
        let right = SIMD3<Float>(forward.z, 0, -forward.x)

        let groundCeiling = camPos.y - s.minCameraAboveGround
        let maxAhead = max(probeMax, s.obstacleRange)
        let referenceEnd = s.probeMin + s.referenceDepth
        let stride = max(1, s.sampleStride)
        survey.nearGround.reserveCapacity(512)
        survey.farGround.reserveCapacity(512)

        for v in Swift.stride(from: 0, to: frame.height, by: stride) {
            for u in Swift.stride(from: 0, to: frame.width, by: stride) {
                let d = frame.depth(x: u, y: v)
                guard d.isFinite, d >= s.minDepth, d <= s.maxDepth else { continue }
                if s.requireMediumConfidence, let c = frame.confidence(x: u, y: v), c < 1 { continue }

                let p = camera.worldPoint(u: Float(u), v: Float(v), depth: d, intrinsics: k)
                let rel = p - camPos
                let ahead = simd_dot(rel, forward)
                guard ahead > 0, ahead <= maxAhead, abs(simd_dot(rel, right)) <= s.halfWidth else { continue }

                var zone: DetectorSnapshot.Zone = []
                if p.y < groundCeiling, ahead >= s.probeMin, ahead <= probeMax {
                    if ahead < referenceEnd {
                        survey.nearGround.append(p.y)
                        zone.insert(.near)
                    } else {
                        survey.farGround.append(Point(ahead: ahead, height: p.y))
                        zone.insert(.far)
                    }
                }
                if ahead <= s.obstacleRange {
                    survey.candidates.append(Point(ahead: ahead, height: p.y))
                    zone.insert(.candidate)
                }
                if capture, !zone.isEmpty {
                    survey.samples.append(.init(world: p, ahead: ahead, height: p.y, zone: zone))
                }
            }
        }
        return survey
    }

    // MARK: - Helpers

    /// The value `q` (0…1) of the way through the sorted values, or nil if there
    /// are too few to trust.
    private func percentile(_ values: [Float], _ q: Float) -> Float? {
        guard values.count >= settings.minValidSamples else { return nil }
        let sorted = values.sorted()
        let index = Int((Float(sorted.count - 1) * max(0, min(1, q))).rounded())
        return sorted[index]
    }

    /// Horizontal speed in m/s, as a running median so a slow walker pausing
    /// mid-stride doesn't flicker between walking and standing. Raising the cane
    /// is vertical, so it doesn't count.
    private mutating func groundSpeed(_ camera: CameraPose) -> Float {
        let p = camera.position
        let now = camera.timestamp
        defer { lastPosition = (p, now) }
        guard let previous = lastPosition else { return 0 }
        let dt = Float(now - previous.time)
        guard dt > 1e-4, dt < 0.5 else { return 0 }
        let d = p - previous.position
        let instant = simd_length(SIMD3<Float>(d.x, 0, d.z)) / dt

        speedHistory.append(instant)
        if speedHistory.count > settings.speedSmoothingFrames {
            speedHistory.removeFirst(speedHistory.count - settings.speedSmoothingFrames)
        }
        return speedHistory.sorted()[speedHistory.count / 2]
    }

    /// How fast the camera is turning, in degrees per second: the cane's sweep.
    private mutating func swingRate(_ camera: CameraPose) -> Float {
        let look = camera.look
        let n = simd_length(look)
        guard n > 1e-4 else { return 0 }
        let forward = look / n
        let now = camera.timestamp
        defer { lastHeading = (forward, now) }
        guard let previous = lastHeading else { return 0 }
        let dt = Float(now - previous.time)
        guard dt > 1e-4, dt < 0.5 else { return 0 }
        let cosAngle = max(-1, min(1, simd_dot(forward, previous.forward)))
        return acos(cosAngle) * 180 / .pi / dt
    }
}
