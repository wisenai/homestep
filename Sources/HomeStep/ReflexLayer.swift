import ARKit
import CoreVideo
import simd

/// Finds steps and obstacles in the floor ahead from the LiDAR depth map, every
/// frame, on the phone. No network.
///
/// This is one of two ways a step is caught. The other is a printed marker
/// tagged as a step, which the Announcer treats as a warning too.
///
/// ## What it measures
///
/// The height of the floor just ahead, in ARKit's gravity-aligned world where
/// +Y is up however the phone is held. Two strips of floor from the same frame
/// are compared: the reference strip right in front of the stick, and the probe
/// strip a little further out. Lower ahead means a step down; higher means a
/// step up.
///
/// There is one probe strip and no separate look-ahead band. An earlier version
/// had two, and a chair hiding the floor behind it made it say "Step down". The
/// cost is that the warning comes from about 0.7 m out rather than a stride
/// further, so there's less room to stop. If that isn't enough, raise the warn
/// distance in Settings.
///
/// ## The swinging stick
///
/// The phone is never still, and the swing affects the measurement three ways:
///
/// 1. Tilt. Heights don't change when the phone pitches; distances along a ray
///    do. So level floor reads level all through the swing.
/// 2. Coverage. The swing drags the strips across the floor, so a frame often
///    sees only part of an edge. The step-down test asks what share of the probe
///    strip is low (`stepDownCoverage`) instead of averaging its height, which
///    would water the edge down, or taking the minimum, which one bad sample
///    could trip.
/// 3. Blur. Fast swings smear the depth image, so above `fastSwingDegPerSec`
///    a step has to hold for more frames before it's reported.
struct ReflexLayer {

    // Every tunable number is here. The defaults lean towards warning early.
    struct Thresholds {
        /// Where the watched floor starts and ends, in metres ahead. In use the
        /// far end comes from `warnDistance` plus `beepLeadIn`; `probeMax` is
        /// only a starting value. At 1.10 m the step was announced a room away.
        var probeMin: Float = 0.25
        var probeMax: Float = 0.70

        /// Range of the warn-distance control. Below the minimum there's no
        /// room left to react.
        var minWarnDistance: Float = 0.30
        var maxWarnDistance: Float = 0.90

        /// How far past the speaking distance the probe reaches, so the edge
        /// beeps before it's named and he can hear it coming.
        var beepLeadIn: Float = 0.25
        /// Half-width (m) either side of his line of travel.
        var halfWidth: Float = 0.35

        /// How far below the reference the floor must be for a step down. Our
        /// step is about 0.17 m and flat floor varies by about 0.005 m.
        var stepDownDrop: Float = 0.07
        /// How far above the reference for a step up.
        var stepUpRise: Float = 0.07
        /// Taller than this is furniture or a wall, not a step. Building codes
        /// keep stair risers under about 0.19 m.
        var maxStepUp: Float = 0.22

        /// Share of the probe strip that must be raised for a step up. A step
        /// lifts all of it; a chair or sofa is a patch with floor around it.
        /// Without this, armchairs were announced as steps. The step-down test
        /// stays sensitive to a part view, so a drop is caught as soon as any
        /// of it shows.
        var stepUpCoverage: Float = 0.60

        /// Depth of the reference strip, from `probeMin` outward: the floor
        /// right in front of the stick. Everything past it is the probe strip.
        ///
        /// Both strips come from the same frame. An earlier version compared the
        /// probe with the floor height remembered over the last second, and
        /// ARKit's position estimate wobbles by a couple of centimetres while
        /// walking, so normal steps produced drops that weren't there. Within one
        /// frame both strips share the same error, and it cancels.
        var referenceDepth: Float = 0.15

        /// Share of the probe strip that must be low for a step down. Noise is
        /// scattered; a real drop is a cluster.
        var stepDownCoverage: Float = 0.15

        /// A surface must be this far below the camera to count as ground, so a
        /// tabletop or a chair back never becomes the floor.
        var minCameraAboveGround: Float = 0.35

        /// Something this tall above the floor, within `obstacleRange`, is an
        /// obstacle.
        var obstacleMinHeight: Float = 0.25
        /// At 1.2 m, walls and door frames he was only walking past kept beeping.
        var obstacleRange: Float = 0.90
        /// Frames an obstacle must last. A sweep drags the corridor across
        /// door frames for a frame or two at a time.
        var obstacleFramesToConfirm = 3

        /// Fewest ground points before a strip is trusted.
        var minValidSamples = 12
        /// Depth readings outside this range are ignored.
        var minDepth: Float = 0.1
        var maxDepth: Float = 5.0
        /// Read every nth depth pixel each way, to keep the cost down.
        var sampleStride = 2
        /// Skip readings ARKit marks as low confidence.
        var requireMediumConfidence = true

        /// If the probe strip returns nothing while the path is clear, treat it
        /// as a drop: an edge can send the light off into empty space.
        var treatVoidAsDrop = true
        /// Only with a clear path: something in the way hides the floor behind
        /// it, which is likelier than a hole.
        var voidRequiresClearPath = true

        /// Frames in a row a step must hold before it's reported: about 50 ms
        /// at 60 fps. A warning that cries wolf gets ignored.
        var framesToConfirm = 3
        /// Above this sweep rate the depth image smears, so ask for more frames.
        var fastSwingDegPerSec: Float = 60
        var extraFramesWhenSwinging = 2

        /// Ground speed (m/s) that counts as walking. "Proceed" is only said to
        /// someone who is moving: if he has stopped, that's his decision.
        var walkingSpeed: Float = 0.10
        /// Frames of speed history, so a slow walker pausing mid-stride doesn't
        /// flicker in and out of "walking".
        var speedSmoothingFrames = 20
    }
    var t = Thresholds()

    /// Which way the floor ahead changes.
    enum StepKind: Sendable, Equatable { case down, up

        var spoken: String {
            switch self {
            case .down: return "Step down."
            case .up:   return "Step up."
            }
        }
    }

    /// How far ahead (m) a step is spoken; beeping starts `beepLeadIn` earlier.
    /// Set from the main actor and read on the ARKit thread, hence the box.
    let warnDistance = LockedBox<Float>(0.45)

    /// For "See what HomeStep sees": while true, each frame also publishes the
    /// points it classified. Nothing here feeds back into a decision.
    let captureSnapshot = LockedBox<Bool>(false)
    let latestSnapshot = LockedBox<DetectorSnapshot?>(nil)

    // State kept between frames. Boxed because `process` runs on the ARKit
    // thread.
    private let stepStreak = LockedBox<Int>(0)
    private let obstacleStreak = LockedBox<Int>(0)
    private let lastStepKind = LockedBox<StepKind?>(nil)
    private let lastHeading = LockedBox<(forward: simd_float3, time: TimeInterval)?>(nil)
    private let lastPose = LockedBox<(position: simd_float3, time: TimeInterval)?>(nil)
    private let speedHistory = LockedBox<[Float]>([])

    /// What this frame measured, for the screen and the log. No decision reads
    /// it; it's there so thresholds are tuned from real numbers.
    struct Reading: Sendable {
        var floorReference: Float?   // height of the floor just ahead (reference strip)
        var floorNow: Float?         // median height in the probe zone this frame
        var probeLow: Float?         // lowest visible ground in the probe zone
        var dropVsReference: Float?  // positive = ground ahead is LOWER
        var obstacleAhead: Float?    // horizontal metres to the nearest thing standing up
        var stepDistance: Float?     // horizontal metres to the near edge of the step
        var groundCount: Int
        var nearCount: Int
        var farCount: Int
        /// What share of the probe strip read as lower / higher: the numbers
        /// the step decision is made on.
        var fallCoverage: Float?
        var riseCoverage: Float?
        var pitchDegrees: Float
        var swingDegreesPerSecond: Float
        var groundSpeed: Float
        var isWalking: Bool
    }

    /// The event (if any) plus this frame's raw measurements.
    struct Outcome { var event: AnnouncerEvent?; var reading: Reading? }

    func process(frame: ARFrame) -> Outcome {
        guard let sceneDepth = frame.sceneDepth else { return Outcome(event: nil, reading: nil) }

        let survey = surveyGround(frame: frame, sceneDepth: sceneDepth)
        let swing = swingRate(frame: frame)
        let speed = groundSpeed(frame: frame)
        let walking = speed >= t.walkingSpeed

        // Both strips come from this frame, so the shared position error cancels.
        let reference = percentile(survey.nearGround, 0.5)
        let farHeights = survey.farGround.map(\.height)
        let probeMedian = percentile(farHeights, 0.5)

        // Obstacles stand up from the floor; a step down is below it, so the
        // two can't be confused. With no floor in view nothing is decided: a
        // swept cane loses the floor for a frame or two all the time, and calling
        // that an obstacle beeped at nothing.
        var obstacle: Float?
        if let f = reference ?? probeMedian {
            obstacle = survey.candidates
                .filter { $0.height > f + t.obstacleMinHeight && $0.ahead <= t.obstacleRange }
                .map(\.ahead).min()
        }
        // Obstacles must persist, like steps.
        let obstacleStreakNow = obstacle != nil ? obstacleStreak.get() + 1 : 0
        obstacleStreak.set(obstacleStreakNow)
        if obstacleStreakNow < t.obstacleFramesToConfirm { obstacle = nil }

        // Step up or step down. Needs no marker.
        var drop: Float?
        var fallCoverage: Float?
        var riseCoverage: Float?
        var stepDistance: Float?
        let step: StepKind?
        if let reference, survey.farGround.count >= t.minValidSamples {
            // Share of the probe strip below the floor he's on.
            let low = survey.farGround.filter { $0.height < reference - t.stepDownDrop }
            fallCoverage = Float(low.count) / Float(survey.farGround.count)
            drop = reference - (percentile(farHeights, 0.15) ?? reference)

            // Share of the probe strip that is raised.
            let high = survey.farGround.filter { $0.height > reference + t.stepUpRise }
            riseCoverage = Float(high.count) / Float(survey.farGround.count)
            let rise = (probeMedian ?? reference) - reference

            if (fallCoverage ?? 0) >= t.stepDownCoverage {
                step = .down
                // The near edge of the drop: how far his foot is from it.
                stepDistance = low.map(\.ahead).min()
            } else if (riseCoverage ?? 0) >= t.stepUpCoverage,
                      rise > t.stepUpRise, rise <= t.maxStepUp {
                step = .up
                stepDistance = high.map(\.ahead).min()
            } else {
                step = nil
            }
        } else if t.treatVoidAsDrop,
                  reference != nil,
                  survey.farGround.count < t.minValidSamples,
                  !(t.voidRequiresClearPath && obstacle != nil) {
            // The floor ahead vanished and nothing is in the way to hide it.
            step = .down
            stepDistance = t.probeMin + t.referenceDepth
        } else {
            step = nil
        }

        if !survey.samples.isEmpty {
            latestSnapshot.set(DetectorSnapshot.build(
                samples: survey.samples, reference: reference, drop: drop,
                stepDistance: stepDistance, obstacle: obstacle,
                warnDistance: warnDistance.get(),
                rules: .init(stepDownDrop: t.stepDownDrop, stepUpRise: t.stepUpRise,
                             obstacleMinHeight: t.obstacleMinHeight, obstacleRange: t.obstacleRange)))
        }

        let reading = Reading(floorReference: reference,
                              floorNow: probeMedian,
                              probeLow: percentile(farHeights, 0.15),
                              dropVsReference: drop,
                              obstacleAhead: obstacle,
                              stepDistance: stepDistance,
                              groundCount: survey.nearGround.count + survey.farGround.count,
                              nearCount: survey.nearGround.count,
                              farCount: survey.farGround.count,
                              fallCoverage: fallCoverage,
                              riseCoverage: riseCoverage,
                              pitchDegrees: pitchDown(frame.camera.transform),
                              swingDegreesPerSecond: swing,
                              groundSpeed: speed,
                              isWalking: walking)

        // A step must hold for several frames in a row, more during a fast
        // sweep. Changing direction starts the count again, so "Step up" is never
        // said on the strength of step-down frames.
        let needed = t.framesToConfirm
            + (swing > t.fastSwingDegPerSec ? t.extraFramesWhenSwinging : 0)
        let streak: Int
        if let step {
            streak = (lastStepKind.get() == step) ? stepStreak.get() + 1 : 1
        } else {
            streak = 0
        }
        lastStepKind.set(step)
        stepStreak.set(streak)
        if let step, streak >= needed {
            let d = stepDistance ?? t.probeMin
            // Beep as soon as the edge is in view; say the words once it's close.
            return Outcome(event: .step(text: step.spoken, distance: d,
                                        speak: d <= warnDistance.get()),
                           reading: reading)
        }

        // Obstacle ahead: the closer, the stronger the cue (see Announcer).
        if let obstacle {
            let closeness = 1 - (obstacle / t.obstacleRange)
            return Outcome(event: .proximity(distance: obstacle,
                                             intensity: max(0, min(1, closeness))),
                           reading: reading)
        }

        // All clear, and only for someone walking: telling a person who has
        // stopped to "proceed" would override their own decision.
        if walking, survey.nearGround.count >= t.minValidSamples {
            return Outcome(event: .clear, reading: reading)
        }

        return Outcome(event: nil, reading: reading)
    }

    /// Forget what earlier frames saw. Called on Start and after an interruption.
    func reset() {
        stepStreak.set(0)
        obstacleStreak.set(0)
        speedHistory.set([])
        lastStepKind.set(nil)
        lastHeading.set(nil)
    }

    // MARK: - Ground survey

    private struct Point { let ahead: Float; let height: Float }
    private struct Survey {
        var nearGround: [Float] = []    // reference strip heights
        var farGround: [Point] = []     // probe strip, with distances ahead
        var candidates: [Point] = []    // everything within obstacle range
        /// For the visualization; filled only while `captureSnapshot` is on.
        var samples: [DetectorSnapshot.Sample] = []
    }

    /// Turn the depth map into world points and sort the useful ones into the
    /// two strips and the obstacle corridor.
    private func surveyGround(frame: ARFrame, sceneDepth: ARDepthData) -> Survey {
        var survey = Survey()

        let depth = sceneDepth.depthMap
        CVPixelBufferLockBaseAddress(depth, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depth, .readOnly) }

        let w = CVPixelBufferGetWidth(depth)
        let h = CVPixelBufferGetHeight(depth)
        guard w > 0, h > 0, let base = CVPixelBufferGetBaseAddress(depth) else { return survey }
        let rowBytes = CVPixelBufferGetBytesPerRow(depth)

        var confBase: UnsafeMutableRawPointer?
        var confRowBytes = 0
        let confidence = t.requireMediumConfidence ? sceneDepth.confidenceMap : nil
        if let confidence {
            CVPixelBufferLockBaseAddress(confidence, .readOnly)
            confBase = CVPixelBufferGetBaseAddress(confidence)
            confRowBytes = CVPixelBufferGetBytesPerRow(confidence)
        }
        defer { if let confidence { CVPixelBufferUnlockBaseAddress(confidence, .readOnly) } }

        // The intrinsics describe the colour image; scale them to the depth map.
        let intr = frame.camera.intrinsics
        let res = frame.camera.imageResolution
        guard res.width > 0, res.height > 0 else { return survey }
        let sx = Float(w) / Float(res.width)
        let sy = Float(h) / Float(res.height)
        let fx = intr[0][0] * sx, fy = intr[1][1] * sy
        let cx = intr[2][0] * sx, cy = intr[2][1] * sy
        guard fx != 0, fy != 0 else { return survey }

        let camT = frame.camera.transform
        let camPos = simd_make_float3(camT.columns.3)

        // The walking direction, flattened onto the floor, so "distance ahead"
        // doesn't depend on how the cane is pitched.
        let look = -simd_make_float3(camT.columns.2)
        var forward = simd_float3(look.x, 0, look.z)
        guard simd_length(forward) > 1e-4 else { return survey }
        forward = simd_normalize(forward)
        let right = simd_float3(forward.z, 0, -forward.x)

        let groundCeiling = camPos.y - t.minCameraAboveGround
        // The probe reaches past the speaking distance so the edge beeps first.
        let probeMax = warnDistance.get() + t.beepLeadIn
        let maxAhead = max(probeMax, t.obstacleRange)
        let stride = max(1, t.sampleStride)
        survey.nearGround.reserveCapacity(512)
        survey.farGround.reserveCapacity(512)
        let capturing = captureSnapshot.get()

        var v = 0
        while v < h {
            let row = base.advanced(by: v * rowBytes).assumingMemoryBound(to: Float32.self)
            let confRow = confBase?.advanced(by: v * confRowBytes).assumingMemoryBound(to: UInt8.self)
            var u = 0
            while u < w {
                defer { u += stride }
                let d = row[u]
                guard d.isFinite, d >= t.minDepth, d <= t.maxDepth else { continue }
                if let confRow, confRow[u] < UInt8(ARConfidenceLevel.medium.rawValue) { continue }

                // Pixel to camera space: +X right, +Y up, -Z forward. Image rows
                // count downward, hence the minus.
                let xc = (Float(u) - cx) * d / fx
                let yc = -(Float(v) - cy) * d / fy
                let world = camT * simd_float4(xc, yc, -d, 1)
                let p = simd_make_float3(world)

                let rel = p - camPos
                let ahead = simd_dot(rel, forward)
                guard ahead > 0, ahead <= maxAhead else { continue }
                guard abs(simd_dot(rel, right)) <= t.halfWidth else { continue }

                var zone: DetectorSnapshot.Zone = []
                if p.y < groundCeiling, ahead >= t.probeMin, ahead <= probeMax {
                    if ahead < t.probeMin + t.referenceDepth {
                        survey.nearGround.append(p.y)
                        zone.insert(.near)
                    } else {
                        // Keep the distance, to find where the edge is.
                        survey.farGround.append(Point(ahead: ahead, height: p.y))
                        zone.insert(.far)
                    }
                }
                if ahead <= t.obstacleRange {
                    survey.candidates.append(Point(ahead: ahead, height: p.y))
                    zone.insert(.candidate)
                }
                if capturing, !zone.isEmpty {
                    survey.samples.append(.init(world: p, ahead: ahead, height: p.y, zone: zone))
                }
            }
            v += stride
        }
        return survey
    }

    // MARK: - Helpers

    /// The value `q` (0…1) of the way through the sorted values, or nil if
    /// there are too few to trust.
    private func percentile(_ values: [Float], _ q: Float) -> Float? {
        guard values.count >= t.minValidSamples else { return nil }
        var v = values
        v.sort()
        let idx = Int((Float(v.count - 1) * max(0, min(1, q))).rounded())
        return v[idx]
    }

    /// Horizontal speed in m/s. Raising the cane is vertical, so it doesn't count.
    private func groundSpeed(frame: ARFrame) -> Float {
        let p = simd_make_float3(frame.camera.transform.columns.3)
        let now = frame.timestamp
        defer { lastPose.set((p, now)) }
        guard let prev = lastPose.get() else { return 0 }
        let dt = Float(now - prev.time)
        guard dt > 1e-4, dt < 0.5 else { return 0 }
        let d = p - prev.position
        let instant = simd_length(simd_float3(d.x, 0, d.z)) / dt

        // Smooth it: he walks slowly and pauses mid-stride.
        var h = speedHistory.get()
        h.append(instant)
        if h.count > t.speedSmoothingFrames { h.removeFirst(h.count - t.speedSmoothingFrames) }
        speedHistory.set(h)
        guard !h.isEmpty else { return instant }
        return h.sorted()[h.count / 2]
    }

    /// How fast the phone is turning, in degrees per second: the cane's sweep.
    private func swingRate(frame: ARFrame) -> Float {
        let look = -simd_make_float3(frame.camera.transform.columns.2)
        let n = simd_length(look)
        guard n > 1e-4 else { return 0 }
        let forward = look / n
        let now = frame.timestamp
        defer { lastHeading.set((forward, now)) }
        guard let prev = lastHeading.get() else { return 0 }
        let dt = Float(now - prev.time)
        guard dt > 1e-4, dt < 0.5 else { return 0 }
        let cosA = max(-1, min(1, simd_dot(forward, prev.forward)))
        return acos(cosA) * 180 / .pi / dt
    }

    /// How far below horizontal the camera looks, in degrees. For display only.
    private func pitchDown(_ camT: simd_float4x4) -> Float {
        let look = -simd_make_float3(camT.columns.2)
        let n = simd_length(look)
        guard n > 1e-4 else { return 0 }
        return asin(max(-1, min(1, -look.y / n))) * 180 / .pi
    }
}
