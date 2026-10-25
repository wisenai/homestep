import XCTest
@testable import HomeStepCore

final class GuideRulesTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 5000)

    private func reading(pitch: Float = 45, near: Int = 500, far: Int = 500) -> StepDetector.Reading {
        StepDetector.Reading(groundCount: near + far, nearCount: near, farCount: far,
                             pitchDegrees: pitch, swingDegreesPerSecond: 0, groundSpeed: 0, isWalking: false)
    }

    // MARK: Spoken messages

    // REQ-SAFE-04
    func testEveryFailureTellsTheUserToUseTheirCane() {
        for line in [Phrases.guidanceStopped, Phrases.guidancePaused, Phrases.guidanceFailed, Phrases.noLiDAR] {
            XCTAssertTrue(line.hasSuffix("Use your cane."), line)
        }
    }

    // REQ-GUIDE-02
    func testNoLiDARSaysStepsAreNotDetected() {
        XCTAssertTrue(Phrases.noLiDAR.contains("Step detection needs a LiDAR iPhone"))
        XCTAssertTrue(Phrases.noLiDAR.contains("Reading markers only"))
    }

    // REQ-GUIDE-03
    func testStartIsAlwaysAnswered() {
        XCTAssertEqual(Phrases.guiding(place: "Home"), "Guiding. Home.")
        XCTAssertEqual(Phrases.guiding(place: nil), "Guiding. Watching for steps and obstacles.")
    }

    // REQ-PLACE-09
    func testPlaceChangeIsSaid() {
        XCTAssertEqual(Phrases.placeChanged(to: "Office"), "Now using place Office.")
        XCTAssertEqual(Phrases.placeChanged(to: nil), "No place in use. Markers are off.")
    }

    // REQ-GUIDE-07
    func testWhereAmI() {
        XCTAssertEqual(Phrases.whereAmI(lastLandmark: nil, readAt: nil, isRunning: true, now: t0),
                       "No marker read yet.")
        XCTAssertEqual(Phrases.whereAmI(lastLandmark: nil, readAt: nil, isRunning: false, now: t0),
                       "HomeStep is stopped. No marker read yet.")
        XCTAssertEqual(Phrases.whereAmI(lastLandmark: "Kitchen", readAt: t0, isRunning: true,
                                        now: t0.addingTimeInterval(30)), "Last marker: Kitchen, just now.")
        XCTAssertEqual(Phrases.whereAmI(lastLandmark: "Kitchen", readAt: t0, isRunning: true,
                                        now: t0.addingTimeInterval(90)), "Last marker: Kitchen, a minute ago.")
        XCTAssertEqual(Phrases.whereAmI(lastLandmark: "Kitchen", readAt: t0, isRunning: true,
                                        now: t0.addingTimeInterval(400)), "Last marker: Kitchen, 6 minutes ago.")
    }

    // REQ-STEP-09
    func testWarnDistanceIsSpoken() {
        XCTAssertEqual(Phrases.warnDistance(0.5), "Step warning at 0.50 metres")
    }

    // MARK: Aim

    // REQ-GUIDE-05
    func testAimHint() {
        XCTAssertEqual(Aim.hint(for: nil), "Waiting for depth…")
        XCTAssertEqual(Aim.hint(for: reading(pitch: 10)), "TILT DOWN — aiming too flat (10°)")
        XCTAssertEqual(Aim.hint(for: reading(pitch: 70)), "TILT UP — aiming too steep (70°)")
        XCTAssertEqual(Aim.hint(for: reading(near: 3)), "Can't see the floor underfoot — tilt down")
        XCTAssertEqual(Aim.hint(for: reading(far: 3)), "Can't see the floor ahead — tilt up")
        XCTAssertEqual(Aim.hint(for: reading(pitch: 45)), "Aim OK (45°)")
    }

    // REQ-GUIDE-06
    func testAimFaultAfterThreeBlindSecondsThenEveryTwelve() {
        var m = AimFaultMonitor()
        XCTAssertFalse(m.check(nearCount: 0, now: t0))
        XCTAssertFalse(m.check(nearCount: 0, now: t0.addingTimeInterval(1)))
        XCTAssertTrue(m.check(nearCount: 0, now: t0.addingTimeInterval(2)))
        for s in 3...14 { XCTAssertFalse(m.check(nearCount: 0, now: t0.addingTimeInterval(Double(s))), "\(s)") }
        XCTAssertTrue(m.check(nearCount: 0, now: t0.addingTimeInterval(15)))
    }

    // REQ-GUIDE-06
    func testSeeingTheFloorResetsTheAimCount() {
        var m = AimFaultMonitor()
        _ = m.check(nearCount: 0, now: t0)
        _ = m.check(nearCount: 0, now: t0.addingTimeInterval(1))
        XCTAssertFalse(m.check(nearCount: 400, now: t0.addingTimeInterval(2)))
        XCTAssertFalse(m.check(nearCount: 0, now: t0.addingTimeInterval(3)), "a brief loss during a sweep")
    }

    // MARK: Liveness

    // REQ-GUIDE-04, REQ-SAFE-04
    func testStalledFramesAreNoticedOnceAndRecoveryToo() {
        var m = LivenessMonitor()
        XCTAssertNil(m.check(lastFrameAt: t0, now: t0.addingTimeInterval(2.5)))
        XCTAssertEqual(m.check(lastFrameAt: t0, now: t0.addingTimeInterval(2.6)), .stalled)
        XCTAssertNil(m.check(lastFrameAt: t0, now: t0.addingTimeInterval(5)), "said once, not every second")
        XCTAssertEqual(m.check(lastFrameAt: t0.addingTimeInterval(6), now: t0.addingTimeInterval(6.1)), .resumed)
        XCTAssertFalse(m.isStalled)
    }

    // MARK: Log rows

    // REQ-LOG-02
    func testReadingLogKeysMatchTheAnalysisScript() {
        var r = reading()
        r.floorReference = -0.92
        r.dropVsReference = 0.004
        r.fallCoverage = 0
        r.obstacleAhead = .nan
        let f = r.logFields
        for key in ["near", "far", "pitch", "swing", "speed", "walking", "ref", "drop", "fallCov"] {
            XCTAssertNotNil(f[key], key)
        }
        XCTAssertNil(f["obstacle"], "non-finite numbers are left out, so the JSON stays valid")
        XCTAssertTrue(JSONSerialization.isValidJSONObject(f))
    }
}
