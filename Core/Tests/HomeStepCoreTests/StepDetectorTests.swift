import XCTest
import simd
@testable import HomeStepCore

/// The detector on single views of the synthetic room. The camera stands 0.92 m
/// above the floor looking 45° down, like the phone on the stick.
final class StepDetectorTests: XCTestCase {

    /// Three frames confirm a step, so most checks look at the fourth.
    private func settle(_ room: Room, pose: CameraPose = Rig.pose(), warnDistance: Float = 0.45,
                        settings: StepDetector.Settings = .init()) -> StepDetector.Outcome {
        var walk = Walk(detector: StepDetector(settings: settings), warnDistance: warnDistance)
        return walk.hold(room, pose: pose, frames: 4).last!
    }

    // MARK: Steps

    // REQ-STEP-03
    func testStepDownIsFound() {
        let out = settle(.stepDown(at: 0.45))
        XCTAssertEqual(out.step?.text, "Step down.")
        XCTAssertGreaterThan(out.reading.fallCoverage ?? 0, 0.15)
    }

    // REQ-STEP-03
    func testStepDownThresholdIsSevenCentimetres() {
        XCTAssertNil(settle(.stepDown(at: 0.45, depth: 0.05)).step, "5 cm is inside floor noise")
        XCTAssertEqual(settle(.stepDown(at: 0.45, depth: 0.09)).step?.text, "Step down.")
    }

    // REQ-STEP-03
    func testStepDownNeedsFifteenPercentOfTheProbe() {
        // An edge at the far end of the probe shows only a sliver of low floor.
        let sliver = settle(.stepDown(at: 0.62))
        XCTAssertLessThan(sliver.reading.fallCoverage ?? 1, 0.15)
        XCTAssertNil(sliver.step)
    }

    // REQ-STEP-04
    func testStepUpIsFound() {
        let out = settle(.stepUp(at: 0.45))
        XCTAssertEqual(out.step?.text, "Step up.")
        XCTAssertGreaterThanOrEqual(out.reading.riseCoverage ?? 0, 0.60)
    }

    // REQ-STEP-04
    func testRiseTallerThanAStepIsNotAStepUp() {
        let out = settle(.stepUp(at: 0.45, rise: 0.30))
        XCTAssertNil(out.step, "30 cm is furniture or a wall, not a step")
    }

    // REQ-STEP-05
    func testLowFurniturePatchIsNotAStepUp() {
        // A footstool 15 cm tall, narrower than the corridor: floor is still
        // visible around it.
        var room = Room.flat()
        room.boxes = [Room.box(ahead: 0.42, depth: 0.5, width: 0.3, height: 0.15)]
        let out = settle(room)
        XCTAssertNil(out.step)
        XCTAssertLessThan(out.reading.riseCoverage ?? 1, 0.60)
    }

    // REQ-STEP-06
    func testVanishingFloorWithClearPathIsAStepDown() {
        // The floor returns nothing from where the probe strip starts.
        var room = Room.flat()
        room.voids = [0.40...10]
        let out = settle(room)
        XCTAssertEqual(out.step?.text, "Step down.")
        XCTAssertEqual(out.step?.distance ?? 0, 0.40, accuracy: 1e-5, "reported at the end of the reference strip")
    }

    // REQ-STEP-06
    func testVanishingFloorBehindAnObstacleIsNotAStep() {
        var room = Room.flat()
        room.voids = [0.40...10]
        room.boxes = [Room.box(ahead: 0.6, width: 0.6, height: 0.8)]
        let out = settle(room)
        XCTAssertNil(out.step, "something in the way hides the floor; that is likelier than a hole")
    }

    // MARK: Pose

    // REQ-STEP-01
    func testHoldingThePhoneSidewaysChangesNothing() {
        let upright = settle(.stepDown(at: 0.45), pose: Rig.pose(roll: 90))
        let sideways = settle(.stepDown(at: 0.45), pose: Rig.pose(roll: 0))
        XCTAssertEqual(upright.step?.text, sideways.step?.text)
        XCTAssertEqual(upright.step?.distance ?? 0, sideways.step?.distance ?? 1, accuracy: 0.02)
    }

    // REQ-STEP-01
    func testCaneTiltDoesNotChangeTheFloorHeight() {
        for pitch: Float in [35, 45, 55] {
            let out = settle(.flat(), pose: Rig.pose(pitch: pitch))
            XCTAssertEqual(out.reading.floorReference ?? 0, Room.floorHeight, accuracy: 0.01, "pitch \(pitch)")
            XCTAssertEqual(out.reading.dropVsReference ?? 1, 0, accuracy: 0.02, "pitch \(pitch)")
            XCTAssertNil(out.step, "pitch \(pitch)")
        }
    }

    // REQ-STEP-02
    func testWhereTheWorldOriginSitsDoesNotMatter() {
        // ARKit's origin drifts. Moving the room and the camera together, even
        // up by half a metre, must give the same answer, because both strips
        // are read through the same pose.
        let base = settle(.stepDown(at: 0.45))
        var room = Room.stepDown(at: 0.45)
        room.floor = room.floor.map { Room.Strip(from: $0.from, height: $0.height + 0.5) }
        let shifted = settle(room, pose: Rig.pose(at: SIMD3(0, 0.5, 0)))
        XCTAssertEqual(base.step?.text, shifted.step?.text)
        XCTAssertEqual(base.step?.distance ?? 0, shifted.step?.distance ?? 1, accuracy: 0.01)
    }

    // MARK: Confirmation

    // REQ-STEP-07
    func testAStepMustHoldForThreeFrames() {
        var walk = Walk()
        let out = walk.hold(.stepDown(at: 0.45), pose: Rig.pose(), frames: 3)
        XCTAssertNil(out[0].step)
        XCTAssertNil(out[1].step)
        XCTAssertNotNil(out[2].step)
    }

    // REQ-STEP-07
    func testFastSweepNeedsTwoMoreFrames() {
        var walk = Walk()
        // Turning 2° every sixtieth of a second is 120°/s, well over 60°/s.
        let outs = (0..<6).map { i in
            walk.look(.stepDown(at: 0.45), pose: Rig.pose(yaw: i.isMultiple(of: 2) ? 1 : -1, time: Double(i) / 60))
        }
        XCTAssertGreaterThan(outs[3].reading.swingDegreesPerSecond, 60)
        XCTAssertNil(outs[3].step, "fourth frame: not yet while swinging fast")
        XCTAssertNotNil(outs[4].step, "fifth frame")
    }

    // REQ-STEP-07
    func testChangingDirectionStartsTheCountAgain() {
        var walk = Walk()
        _ = walk.hold(.stepDown(at: 0.45), pose: Rig.pose(), frames: 2)
        let up = walk.hold(.stepUp(at: 0.45), pose: Rig.pose(time: 1), frames: 3)
        XCTAssertNil(up[0].step, "a step-up frame does not continue a step-down count")
        XCTAssertNil(up[1].step)
        XCTAssertEqual(up[2].step?.text, "Step up.")
    }

    // REQ-STEP-10
    func testResetForgetsAPartlyConfirmedStep() {
        var walk = Walk()
        _ = walk.hold(.stepDown(at: 0.45), pose: Rig.pose(), frames: 2)
        walk.detector.reset()
        let out = walk.hold(.stepDown(at: 0.45), pose: Rig.pose(time: 1), frames: 2)
        XCTAssertNil(out.last?.step)
    }

    // MARK: Distance and speaking

    // REQ-STEP-08
    func testEdgeDistanceIsMeasured() {
        // Looking down past an edge, the lower floor just beyond it is hidden,
        // so the first low point is a little past the edge itself.
        let out = settle(.stepDown(at: 0.45))
        XCTAssertEqual(out.step?.distance ?? 0, 0.50, accuracy: 0.08)
    }

    // REQ-STEP-08
    func testWordsWaitUntilTheEdgeIsWithinTheWarnDistance() {
        let near = settle(.stepDown(at: 0.45), warnDistance: 0.60)
        XCTAssertEqual(near.step?.speak, true)
        let far = settle(.stepDown(at: 0.45), warnDistance: 0.30)
        XCTAssertEqual(far.step?.speak, false, "still beeping, not yet speaking")
        XCTAssertEqual(far.step?.text, "Step down.")
    }

    // REQ-STEP-09
    func testWarnDistanceStaysInRange() {
        let s = StepDetector.Settings()
        XCTAssertEqual(s.defaultWarnDistance, 0.45)
        XCTAssertEqual(s.clampWarnDistance(0.1), 0.30)
        XCTAssertEqual(s.clampWarnDistance(2.0), 0.90)
        XCTAssertEqual(s.clampWarnDistance(0.55), 0.55)
    }

    // MARK: Input filtering

    // REQ-STEP-11
    func testLowConfidenceDepthIsIgnored() {
        var walk = Walk()
        var depth = RenderedDepth(room: .flat(), pose: Rig.pose())
        depth.confidenceLevel = 0
        let out = walk.detector.process(depth: depth, camera: Rig.pose(), intrinsics: Rig.intrinsics,
                                        warnDistance: 0.45)
        XCTAssertEqual(out.reading.groundCount, 0)
        XCTAssertNil(out.reading.floorReference)
    }

    // REQ-STEP-11
    func testDepthOutsideRangeIsIgnored() {
        var detector = StepDetector()
        let far = DepthGrid(width: 8, height: 8, depths: Array(repeating: 6.0, count: 64))
        let out = detector.process(depth: far, camera: Rig.pose(), intrinsics: Rig.intrinsics, warnDistance: 0.45)
        XCTAssertEqual(out.reading.groundCount, 0)
        let nan = DepthGrid(width: 8, height: 8, depths: Array(repeating: .nan, count: 64))
        XCTAssertEqual(detector.process(depth: nan, camera: Rig.pose(), intrinsics: Rig.intrinsics,
                                        warnDistance: 0.45).reading.groundCount, 0)
    }

    // REQ-STEP-11
    func testTooFewPointsDecideNothing() {
        var s = StepDetector.Settings()
        s.sampleStride = 64   // a handful of points per frame
        let out = settle(.stepDown(at: 0.45), settings: s)
        XCTAssertLessThan(out.reading.nearCount, 12)
        XCTAssertNil(out.reading.floorReference)
        XCTAssertNil(out.event)
    }

    // REQ-STEP-11
    func testNoIntrinsicsMeansNoSurvey() {
        var detector = StepDetector()
        let out = detector.process(depth: RenderedDepth(room: .flat(), pose: Rig.pose()), camera: Rig.pose(),
                                   intrinsics: nil, warnDistance: 0.45)
        XCTAssertEqual(out.reading.groundCount, 0)
        XCTAssertNil(out.event)
    }

    // MARK: Obstacles

    // REQ-OBST-01
    func testObstacleAheadIsFound() {
        var room = Room.flat()
        room.boxes = [Room.box(ahead: 0.6, height: 0.5)]
        let out = settle(room)
        XCTAssertEqual(out.obstacle?.distance ?? 0, 0.6, accuracy: 0.03)
    }

    // REQ-OBST-01
    func testLowThingsAndThingsOffToTheSideAreNotObstacles() {
        var low = Room.flat()
        low.boxes = [Room.box(ahead: 0.6, width: 0.8, height: 0.2)]
        XCTAssertNil(settle(low).obstacle, "20 cm is under the 25 cm obstacle height")

        var aside = Room.flat()
        aside.boxes = [Room.box(ahead: 0.5, width: 0.3, height: 0.8, x: 0.7)]
        XCTAssertNil(settle(aside).obstacle, "outside the corridor either side of the walking line")

        var beyond = Room.flat()
        beyond.boxes = [Room.box(ahead: 1.1, height: 0.8)]
        XCTAssertNil(settle(beyond).obstacle, "further than 0.9 m")
    }

    // REQ-OBST-02
    func testObstacleMustPersistForThreeFrames() {
        var room = Room.flat()
        room.boxes = [Room.box(ahead: 0.6, height: 0.5)]
        var walk = Walk()
        let outs = walk.hold(room, pose: Rig.pose(), frames: 3)
        XCTAssertNil(outs[0].obstacle)
        XCTAssertNil(outs[1].obstacle)
        XCTAssertNotNil(outs[2].obstacle)
    }

    // REQ-OBST-03
    func testObstacleIntensityGrowsAsItGetsCloser() {
        func intensity(_ ahead: Float) -> Float {
            var room = Room.flat()
            room.boxes = [Room.box(ahead: ahead, height: 0.6)]
            let o = settle(room).obstacle!
            XCTAssertEqual(o.intensity, 1 - o.distance / 0.9, accuracy: 1e-5)
            return o.intensity
        }
        XCTAssertGreaterThan(intensity(0.45), intensity(0.75))
    }

    // REQ-OBST-04
    func testAStepOutranksAnObstacleInTheSameFrame() {
        var room = Room.stepDown(at: 0.45)
        room.boxes = [Room.box(ahead: 0.7, width: 0.3, height: 0.8, x: 0.25)]
        let out = settle(room)
        XCTAssertNotNil(out.reading.obstacleAhead)
        XCTAssertEqual(out.step?.text, "Step down.")
    }

    // REQ-OBST-07
    func testNoFloorInViewDecidesNothing() {
        // Aimed at the ceiling: no ground at all. Unknown is not an obstacle.
        let out = settle(.flat(), pose: Rig.pose(pitch: -40))
        XCTAssertNil(out.reading.floorReference)
        XCTAssertNil(out.event)
    }

    // MARK: All clear

    // REQ-CLEAR-01
    func testProceedOnlyWhileWalking() {
        var walk = Walk()
        let standing = walk.hold(.flat(), pose: Rig.pose(), frames: 30)
        XCTAssertTrue(standing.allSatisfy { $0.event == nil }, "standing still on clear floor: nothing to say")

        var moving = Walk()
        let frames = moving.walk(.flat(), from: 0, to: 0.5, sweep: 0)
        XCTAssertEqual(frames.last?.outcome.event, .clear)
        XCTAssertTrue(frames.last!.outcome.reading.isWalking)
    }

    // MARK: Snapshot

    // REQ-UI-02
    func testSnapshotOnlyWhenAskedFor() {
        var walk = Walk()
        XCTAssertNil(walk.look(.flat(), pose: Rig.pose()).snapshot)
        let snap = walk.look(.stepDown(at: 0.45), pose: Rig.pose(time: 0.1), capture: true).snapshot
        XCTAssertNotNil(snap)
        XCTAssertTrue(snap!.points.contains { $0.kind == .low }, "the step's floor is drawn as low")
        XCTAssertTrue(snap!.points.contains { $0.kind == .reference })
    }
}
