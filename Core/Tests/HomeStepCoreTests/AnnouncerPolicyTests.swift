import XCTest
@testable import HomeStepCore

/// What gets said, beeped and buzzed, and when, checked against a fake clock.
final class AnnouncerPolicyTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1000)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    private let everythingOff = AnnouncerPolicy.Settings(speech: false, tones: false, haptics: false)
    private let kitchen = Landmark(marker: 2, name: "Kitchen", kind: .landmark)
    private let hall = Landmark(marker: 5, name: "Hall", kind: .landmark)

    private func spoken(_ sounds: [Sound]) -> [String] {
        sounds.compactMap { if case .speak(let s) = $0 { return s } else { return nil } }
    }

    private func vibrations(_ sounds: [Sound]) -> [Float] {
        sounds.compactMap { if case .vibrate(let i) = $0 { return i } else { return nil } }
    }

    private func tones(_ sounds: [Sound]) -> [[Tone]] {
        sounds.compactMap { if case .play(let t, _) = $0 { return t } else { return nil } }
    }

    // MARK: Warnings

    // REQ-OUT-01
    func testHazardInterruptsThenSoundsThenSpeaks() {
        var p = AnnouncerPolicy()
        let out = p.emit(.hazard(text: "Step down."), at: t0)
        XCTAssertEqual(out, [.stopSpeaking(immediately: true),
                             .play(AnnouncerPolicy.hazardEarcon, volume: 0.9),
                             .vibrate(1.0),
                             .speak("Step down.")])
    }

    // REQ-SAFE-02
    func testWarningsIgnoreEverySetting() {
        var p = AnnouncerPolicy(settings: everythingOff)
        XCTAssertEqual(spoken(p.emit(.hazard(text: "Caution. Stairs."), at: t0)), ["Caution. Stairs."])
        let step = p.emit(.step(text: "Step down.", distance: 0.3, speak: true), at: at(10))
        XCTAssertEqual(spoken(step), ["Step down."])
        XCTAssertEqual(tones(step), [AnnouncerPolicy.stepBeep])
        XCTAssertFalse(vibrations(step).isEmpty, "the step buzz ignores the vibration switch")
    }

    // REQ-SAFE-03
    func testStopBeepingNeverMutesSteps() {
        var p = AnnouncerPolicy()
        p.quietProximity = true
        XCTAssertEqual(spoken(p.emit(.step(text: "Step up.", distance: 0.3, speak: true), at: t0)), ["Step up."])
        XCTAssertEqual(spoken(p.emit(.hazard(text: "Stairs."), at: at(5))), ["Stairs."])
    }

    // REQ-OUT-02
    func testSameWarningIsNotRepeatedWithinTheGap() {
        var p = AnnouncerPolicy()
        XCTAssertFalse(p.emit(.hazard(text: "Step down."), at: t0).isEmpty)
        XCTAssertTrue(p.emit(.hazard(text: "Step down."), at: at(2.5)).isEmpty)
        XCTAssertFalse(p.emit(.hazard(text: "Step down."), at: at(2.6)).isEmpty)
    }

    // REQ-OUT-02
    func testOppositeWarningIsNeverHeldBack() {
        var p = AnnouncerPolicy()
        _ = p.emit(.hazard(text: "Step down."), at: t0)
        XCTAssertEqual(spoken(p.emit(.hazard(text: "Step up."), at: at(0.1))), ["Step up."])
    }

    // REQ-OUT-02
    func testRepeatedStepStillBeepsButSpeaksOnce() {
        var p = AnnouncerPolicy()
        XCTAssertEqual(spoken(p.emit(.step(text: "Step down.", distance: 0.4, speak: true), at: t0)), ["Step down."])
        let again = p.emit(.step(text: "Step down.", distance: 0.1, speak: true), at: at(1))
        XCTAssertTrue(spoken(again).isEmpty)
        XCTAssertEqual(tones(again), [AnnouncerPolicy.stepBeep])
    }

    // REQ-OUT-03
    func testStepBeepSpeedsUpNearTheEdge() {
        // Far off (0.8 m or more): 0.67 s apart. At the edge: 0.12 s.
        var far = AnnouncerPolicy()
        XCTAssertFalse(far.emit(.step(text: "Step down.", distance: 0.9, speak: false), at: t0).isEmpty)
        XCTAssertTrue(far.emit(.step(text: "Step down.", distance: 0.9, speak: false), at: at(0.6)).isEmpty)
        XCTAssertFalse(far.emit(.step(text: "Step down.", distance: 0.9, speak: false), at: at(0.68)).isEmpty)

        var near = AnnouncerPolicy()
        _ = near.emit(.step(text: "Step down.", distance: 0, speak: false), at: t0)
        XCTAssertFalse(near.emit(.step(text: "Step down.", distance: 0, speak: false), at: at(0.13)).isEmpty)
    }

    // REQ-OUT-03, REQ-STEP-08
    func testStepFarOffOnlyBeeps() {
        var p = AnnouncerPolicy()
        let out = p.emit(.step(text: "Step down.", distance: 0.6, speak: false), at: t0)
        XCTAssertTrue(spoken(out).isEmpty)
        XCTAssertEqual(tones(out), [AnnouncerPolicy.stepBeep])
        XCTAssertEqual(vibrations(out).first ?? 0, 0.25, accuracy: 1e-5, "stronger as the edge gets closer")
    }

    // MARK: Obstacles

    // REQ-OBST-05
    func testObstacleBeepIsLowAndSpeedsUp() {
        var p = AnnouncerPolicy()
        let far = p.emit(.proximity(distance: 0.9, intensity: 0), at: t0)
        XCTAssertEqual(tones(far).last, [Tone(300, 0.07)])
        var q = AnnouncerPolicy()
        let near = q.emit(.proximity(distance: 0, intensity: 1), at: t0)
        XCTAssertEqual(tones(near).last, [Tone(800, 0.07)])
        XCTAssertLessThan(800, AnnouncerPolicy.hazardEarcon[0].hz, "never confusable with the warning sound")

        // 0.6 s between beeps far off, 0.12 s up close.
        XCTAssertTrue(tones(p.emit(.proximity(distance: 0.9, intensity: 0), at: at(0.5))).isEmpty)
        XCTAssertFalse(tones(q.emit(.proximity(distance: 0, intensity: 1), at: at(0.13))).isEmpty)
    }

    // REQ-OBST-05
    func testWithTonesOffObstaclesStillVibrate() {
        var p = AnnouncerPolicy(settings: .init(speech: true, tones: false, haptics: false))
        let out = p.emit(.proximity(distance: 0.5, intensity: 0.5), at: t0)
        XCTAssertTrue(tones(out).isEmpty)
        XCTAssertEqual(vibrations(out), [0.5])
    }

    // REQ-OBST-05
    func testObstacleVibrationFollowsTheSwitchWhenTonesAreOn() {
        var p = AnnouncerPolicy(settings: .init(speech: true, tones: true, haptics: false))
        XCTAssertTrue(vibrations(p.emit(.proximity(distance: 0.5, intensity: 0.5), at: t0)).isEmpty)
    }

    // REQ-OBST-06
    func testObstacleWordsOnANewObstacleThenRarely() {
        var p = AnnouncerPolicy()
        XCTAssertEqual(spoken(p.emit(.proximity(distance: 0.6, intensity: 0.3), at: t0)), ["Obstacle ahead."])
        // Still in view, reported every frame: no words for 6 s.
        var said: [TimeInterval] = []
        for i in 1...80 {
            let t = Double(i) * 0.1
            if !spoken(p.emit(.proximity(distance: 0.6, intensity: 0.3), at: at(t))).isEmpty { said.append(t) }
        }
        XCTAssertEqual(said.count, 1)
        XCTAssertGreaterThan(said[0], 6)
        // Gone for 2 s, then back: a new obstacle, named straight away.
        XCTAssertEqual(spoken(p.emit(.proximity(distance: 0.6, intensity: 0.3), at: at(10))), ["Obstacle ahead."])
    }

    // REQ-SAFE-03
    func testStopBeepingMutesObstaclesAndProceed() {
        var p = AnnouncerPolicy()
        p.quietProximity = true
        XCTAssertTrue(p.emit(.proximity(distance: 0.3, intensity: 0.9), at: t0).isEmpty)
        XCTAssertTrue(p.emit(.clear, at: at(10)).isEmpty)
    }

    // MARK: Proceed

    // REQ-CLEAR-02
    func testProceedEveryFewSeconds() {
        var p = AnnouncerPolicy()
        XCTAssertEqual(spoken(p.emit(.clear, at: t0)), ["Proceed."])
        XCTAssertTrue(p.emit(.clear, at: at(2)).isEmpty)
        XCTAssertEqual(spoken(p.emit(.clear, at: at(2.1))), ["Proceed."])
    }

    // REQ-CLEAR-02
    func testProceedNeverContradictsAWarning() {
        var p = AnnouncerPolicy()
        _ = p.emit(.step(text: "Step down.", distance: 0.3, speak: true), at: t0)
        XCTAssertTrue(p.emit(.clear, at: at(2.5)).isEmpty)
        XCTAssertEqual(spoken(p.emit(.clear, at: at(2.6))), ["Proceed."])

        var q = AnnouncerPolicy()
        _ = q.emit(.proximity(distance: 0.5, intensity: 0.4), at: t0)
        XCTAssertTrue(q.emit(.clear, at: at(2)).isEmpty, "not straight after \"Obstacle ahead\"")
    }

    // MARK: Landmarks

    // REQ-OUT-04
    func testLandmarkCooldown() {
        var p = AnnouncerPolicy()
        XCTAssertEqual(spoken(p.emit(.landmark(kitchen), at: t0)), ["Kitchen."])
        XCTAssertTrue(p.emit(.landmark(kitchen), at: at(4)).isEmpty)
        XCTAssertEqual(spoken(p.emit(.landmark(kitchen), at: at(4.1))), ["Kitchen."])
    }

    // REQ-OUT-04
    func testADifferentLandmarkSpeaksStraightAway() {
        var p = AnnouncerPolicy()
        _ = p.emit(.landmark(kitchen), at: t0)
        XCTAssertEqual(spoken(p.emit(.landmark(hall), at: at(0.5))), ["Hall."])
    }

    // REQ-SAFE-07, REQ-MARK-04
    func testStepMarkerIsAWarning() {
        var p = AnnouncerPolicy(settings: everythingOff)
        let step = Landmark(marker: 0, name: "Living room", kind: .stepDown)
        let out = p.emit(.landmark(step), at: t0)
        XCTAssertEqual(out.first, .stopSpeaking(immediately: true))
        XCTAssertEqual(tones(out), [AnnouncerPolicy.hazardEarcon])
        XCTAssertEqual(spoken(out), ["Step down. Living room."])
    }

    // REQ-OUT-08
    func testOrdinarySpeechFollowsTheSwitch() {
        var p = AnnouncerPolicy(settings: everythingOff)
        XCTAssertTrue(p.emit(.landmark(kitchen), at: t0).isEmpty)
        XCTAssertTrue(p.say("Hello").isEmpty)
        XCTAssertTrue(p.emit(.clear, at: at(5)).isEmpty)
    }

    // MARK: System messages

    // REQ-OUT-05, REQ-SAFE-04
    func testAlertsAlwaysSpeakWithAChime() {
        let p = AnnouncerPolicy(settings: everythingOff)
        XCTAssertEqual(p.alert("Guidance stopped. Use your cane."),
                       [.stopSpeaking(immediately: true),
                        .play(AnnouncerPolicy.alertChime, volume: 0.7),
                        .speak("Guidance stopped. Use your cane.")])
        XCTAssertNotEqual(AnnouncerPolicy.alertChime, AnnouncerPolicy.hazardEarcon)
    }

    // REQ-OUT-06
    func testRepliesAlwaysSpeak() {
        let p = AnnouncerPolicy(settings: everythingOff)
        XCTAssertEqual(p.status("Guiding."), [.stopSpeaking(immediately: false), .speak("Guiding.")])
    }

    // REQ-OUT-07
    func testSilenceStopsEverythingAndFreesTheNextWarning() {
        var p = AnnouncerPolicy()
        _ = p.emit(.hazard(text: "Step down."), at: t0)
        XCTAssertEqual(p.silence(), [.stopSpeaking(immediately: true), .stopTones])
        XCTAssertEqual(spoken(p.emit(.hazard(text: "Step down."), at: at(0.5))), ["Step down."])
    }

    // REQ-OUT-08
    func testThrottledSpeech() {
        var p = AnnouncerPolicy()
        XCTAssertEqual(spoken(p.sayThrottled("No marker read yet.", at: t0)), ["No marker read yet."])
        XCTAssertTrue(p.sayThrottled("No marker read yet.", at: at(19)).isEmpty)
        XCTAssertFalse(p.sayThrottled("No marker read yet.", at: at(21)).isEmpty)
    }

    // REQ-LOG-05
    func testEventLogNames() {
        XCTAssertEqual(AnnouncerEvent.step(text: "Step down.", distance: 0.456, speak: true).logName,
                       "step:Step down. d=0.46 spoken=true")
        XCTAssertEqual(AnnouncerEvent.landmark(kitchen).logName, "landmark:2")
        XCTAssertEqual(AnnouncerEvent.clear.logName, "clear")
    }
}
