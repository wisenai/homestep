import XCTest
@testable import HomeStepCore

/// Whole approaches, frame by frame at 60 fps, with the cane sweeping 15°
/// each side once a second and the phone moving with it. These stand in for
/// the walks done at home. They don't replace them: the field protocols in
/// docs/testing/field-protocols.md are still the gate.
final class WalkScenarioTests: XCTestCase {

    // REQ-STEP-12
    func testSweepingOnLevelFloorNeverReportsAStep() {
        var walk = Walk()
        let frames = walk.walk(.flat(), from: 0, to: 2.0)
        XCTAssertGreaterThan(frames.count, 200)
        XCTAssertTrue(frames.allSatisfy { $0.outcome.step == nil }, "false step warning on flat floor")
        let drops = frames.compactMap { $0.outcome.reading.dropVsReference }
        XCTAssertLessThan(drops.map(abs).max() ?? 1, 0.02, "level-floor noise stays far under the 7 cm threshold")
    }

    // REQ-STEP-12
    func testFastSweepOnLevelFloorNeverReportsAStep() {
        var walk = Walk()
        let frames = walk.walk(.flat(), from: 0, to: 1.5, sweep: 30)
        XCTAssertTrue(frames.allSatisfy { $0.outcome.step == nil })
    }

    // REQ-STEP-13, REQ-SAFE-07, REQ-SAFE-08
    func testWalkingUpToAStepDownWarnsInTime() {
        let edge: Float = 2.0
        var walk = Walk()
        let frames = walk.walk(.stepDown(at: edge), from: 0.5, to: 1.8)

        let firstBeep = frames.first { $0.outcome.step != nil }
        let firstWords = frames.first { $0.outcome.step?.speak == true }
        XCTAssertNotNil(firstBeep)
        XCTAssertEqual(firstWords?.outcome.step?.text, "Step down.")

        // Measured from the phone, which sits behind the stick's tip.
        let beepAt = edge - firstBeep!.position
        let wordsAt = edge - firstWords!.position
        XCTAssertGreaterThanOrEqual(beepAt, 0.45, "beeping starts well before the edge")
        XCTAssertGreaterThanOrEqual(wordsAt, 0.30, "\"Step down\" with at least 30 cm to spare")
        XCTAssertGreaterThan(beepAt, wordsAt)
    }

    /// How far from the edge the words came, or nil if they never did.
    private func wordsAt(_ warn: Float, _ room: Room = .stepDown(at: 2.0)) -> Float? {
        var walk = Walk(warnDistance: warn)
        let frames = walk.walk(room, from: 0.8, to: 1.95)
        return frames.first { $0.outcome.step?.speak == true }.map { 2.0 - $0.position }
    }

    // REQ-STEP-13
    func testWarningDistanceFollowsTheSetting() throws {
        let early = try XCTUnwrap(wordsAt(0.75))
        let late = try XCTUnwrap(wordsAt(0.45))
        XCTAssertGreaterThan(early, late + 0.15)
    }

    // REQ-STEP-16
    func testEveryAllowedWarnDistanceSpeaks() {
        // Known issue KI-1 (docs/specs/step-detector.md): once the edge is within
        // about 0.3 m of the phone it sits in the reference strip and the step
        // is no longer reported. At the shortest settings, the edge gets there
        // before it is close enough to be spoken, so the step only beeps.
        let s = StepDetector.Settings()
        for warn in stride(from: s.minWarnDistance, through: s.maxWarnDistance + 0.001, by: 0.05) {
            for (name, room) in [("down", Room.stepDown(at: 2.0)), ("up", Room.stepUp(at: 2.0))] {
                if warn < 0.449 {
                    XCTExpectFailure("KI-1: no words at warn distance \(warn)")
                }
                XCTAssertNotNil(wordsAt(warn, room), "step \(name) at warn distance \(warn)")
            }
        }
    }

    // REQ-STEP-14
    func testWalkingUpToAStepUpWarns() {
        let edge: Float = 2.0
        var walk = Walk()
        let frames = walk.walk(.stepUp(at: edge), from: 0.8, to: 1.8)
        let words = frames.first { $0.outcome.step?.speak == true }
        XCTAssertEqual(words?.outcome.step?.text, "Step up.")
        XCTAssertGreaterThanOrEqual(edge - words!.position, 0.30)
        XCTAssertFalse(frames.contains { $0.outcome.step?.text == "Step down." })
    }

    // REQ-OBST-01, REQ-STEP-05
    func testWalkingTowardsAChairGivesObstacleNotStep() {
        var room = Room.flat()
        room.boxes = [Room.box(ahead: 1.6, depth: 0.5, width: 0.6, height: 0.45)]
        var walk = Walk()
        let frames = walk.walk(room, from: 0.4, to: 1.0)
        XCTAssertTrue(frames.contains { $0.outcome.obstacle != nil })
        XCTAssertFalse(frames.contains { $0.outcome.step != nil }, "a chair seat is not a step up")
    }
}
