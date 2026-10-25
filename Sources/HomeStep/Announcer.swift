import AVFoundation
import CoreHaptics

/// Things the detector and the marker reader can report, most urgent first.
enum AnnouncerEvent {
    case hazard(text: String)
    case proximity(distance: Float, intensity: Float)   // intensity 0..1
    /// A step edge and how far ahead it is. `speak` is false while it's still
    /// far off, when the beeping alone locates it.
    case step(text: String, distance: Float, speak: Bool)
    case clear                                          // walking, nothing in the way
    case landmark(Landmark)
    /// An answer from the on-demand assistant, which this build doesn't include.
    case cognition(text: String)
}

/// Everything HomeStep says, beeps or buzzes goes through here, so warnings
/// never talk over each other. Hazards interrupt everything and play their own
/// sound first; landmarks wait out a short cooldown per marker.
@MainActor
final class Announcer {

    /// The user's speech, tones and vibration switches and speaking rate.
    /// Step and hazard warnings ignore the switches: they always play.
    struct Settings {
        var speech = true
        var tones = true
        var haptics = true
        var rate: Float = 0.5
    }
    var settings = Settings()

    private let speech = AVSpeechSynthesizer()
    private var haptics: CHHapticEngine?
    private let tones = ToneGenerator()
    private var lastLandmarkID: UUID?
    private var lastLandmarkAt = Date.distantPast
    private let cooldown: TimeInterval = 4

    // Obstacles beep like a parking sensor: closer is faster and higher.
    private var lastProximityAt = Date.distantPast

    /// The detector reports a step on every frame it stays in view, about 60
    /// times a second. Without a gap each repeat would cut the sentence off and
    /// he'd hear only beeping. The first warning is never delayed; only the same
    /// warning restarting itself is.
    private var lastHazardAt = Date.distantPast
    private var lastHazardText: String?
    private let hazardRepeatGap: TimeInterval = 2.5

    /// Mutes obstacle beeps and "Proceed" only. Step and hazard warnings can't
    /// be muted.
    var quietProximity = false

    private var lastThrottledText: String?
    private var lastThrottledAt = Date.distantPast

    // "Obstacle ahead" on a new obstacle, then only now and then: the beeps
    // already carry the distance.
    private var lastObstacleSeenAt = Date.distantPast
    private var lastObstacleSpokenAt = Date.distantPast
    private let obstacleNewGap: TimeInterval = 1.5    // silence this long = a new obstacle
    private let obstacleRepeatGap: TimeInterval = 6   // re-say at most this often

    private var lastStepBeepAt = Date.distantPast
    private var lastProceedAt = Date.distantPast
    private let proceedGap: TimeInterval = 2          // "Proceed." at most this often
    private let proceedAfterHazardGap: TimeInterval = 2.5

    init() {
        try? configureAudioSession()
        haptics = try? CHHapticEngine()
        try? haptics?.start()
    }

    func emit(_ event: AnnouncerEvent) {
        switch event {
        case .hazard(let text):
            // Interrupt, play the warning sound, then speak. Only a repeat of the
            // same words within the gap is skipped, so "Step up" is never held
            // back by a recent "Step down".
            let now = Date()
            if text == lastHazardText, now.timeIntervalSince(lastHazardAt) <= hazardRepeatGap {
                return
            }
            lastHazardText = text
            lastHazardAt = now
            speech.stopSpeaking(at: .immediate)
            playHazardEarcon()
            sayAlways(text)

        case .step(let text, let distance, let speak):
            // The beeping tracks the edge; the words come when it's near. It's
            // higher and doubled, unlike the obstacle beep, because the two mean
            // opposite things: go around, or the floor ends here.
            playStepBeep(distance: distance)
            guard speak else { return }
            let now = Date()
            if text == lastHazardText, now.timeIntervalSince(lastHazardAt) <= hazardRepeatGap {
                return
            }
            lastHazardText = text
            lastHazardAt = now
            speech.stopSpeaking(at: .immediate)
            sayAlways(text)

        case .proximity(_, let intensity):
            guard !quietProximity else { return }
            speakObstacleIfDue()
            playProximity(intensity: intensity)

        case .clear:
            speakProceedIfDue()

        case .landmark(let landmark):
            // A step or hazard marker is a warning too, so a marked step is
            // caught twice: by its marker and by the detector.
            if landmark.isHazard { emit(.hazard(text: landmark.spokenText)); return }
            let now = Date()
            let isNew = landmark.id != lastLandmarkID
            if isNew || now.timeIntervalSince(lastLandmarkAt) > cooldown {
                say(landmark.spokenText)
                lastLandmarkID = landmark.id
                lastLandmarkAt = now
            }

        case .cognition(let text):
            say(text)   // lowest priority; never interrupts a warning
        }
    }

    /// Ordinary speech, which respects the speech switch.
    func say(_ text: String) {
        guard settings.speech else { return }
        sayAlways(text)
    }

    /// Like `say`, but the same sentence at most once per `minGap`, for messages
    /// a stray tap could otherwise repeat.
    func sayThrottled(_ text: String, minGap: TimeInterval = 20) {
        let now = Date()
        if lastThrottledText == text, now.timeIntervalSince(lastThrottledAt) < minGap { return }
        lastThrottledText = text
        lastThrottledAt = now
        say(text)
    }

    /// The app's own state: guidance paused, resumed or stopped.
    ///
    /// Always spoken, whatever the speech switch says: he can't see that the app
    /// has stopped, and silence would sound like a clear path. It uses a two-tone
    /// chime, not the warning sound, so it's never mistaken for a step.
    func alert(_ text: String) {
        speech.stopSpeaking(at: .immediate)
        tones.play([(880, 0.10), (0, 0.04), (660, 0.14)], amplitude: 0.7)
        sayAlways(text)
    }

    /// The reply to something the user just did, like Start or "Where am I?".
    /// Always spoken: an unanswered button sounds like a broken app.
    func status(_ text: String) {
        speech.stopSpeaking(at: .word)
        sayAlways(text)
    }

    /// Stop everything that's sounding now. Later warnings still play; there is
    /// no way to turn them off.
    func silence() {
        speech.stopSpeaking(at: .immediate)
        tones.stopAll()
        lastHazardAt = .distantPast   // a new warning may speak straight away
        lastHazardText = nil
    }

    // MARK: - Private

    /// Speech that ignores the speech switch.
    private func sayAlways(_ text: String) {
        let u = AVSpeechUtterance(string: text)
        u.rate = settings.rate
        speech.speak(u)
    }

    private func configureAudioSession() throws {
        // Lower other audio rather than stop it; meant for a single earpiece.
        let s = AVAudioSession.sharedInstance()
        try s.setCategory(.playback, options: [.duckOthers])
        try s.setActive(true)
    }

    /// Two quick high beeps and a strong buzz, so a hazard never sounds like an
    /// obstacle. Always plays.
    private func playHazardEarcon() {
        tones.play([(1568, 0.09), (0, 0.05), (1568, 0.09)], amplitude: 0.9)
        buzz(intensity: 1.0, force: true)   // ignores the vibration switch
    }

    /// "Obstacle ahead" when one is first met, then only now and then while it
    /// stays. The words make the first meeting clear; the beeps do the rest.
    private func speakObstacleIfDue() {
        let now = Date()
        // A pause in obstacle reports means this is a new one.
        let isNewEncounter = now.timeIntervalSince(lastObstacleSeenAt) > obstacleNewGap
        lastObstacleSeenAt = now
        guard isNewEncounter || now.timeIntervalSince(lastObstacleSpokenAt) > obstacleRepeatGap
        else { return }
        lastObstacleSpokenAt = now
        say("Obstacle ahead.")
    }

    /// "Proceed": the way ahead is clear and he's walking. Repeated every few
    /// seconds, so silence never has to mean "clear".
    ///
    /// Held back for a moment after a warning, so it never contradicts one while
    /// he's still standing at the step. STOP BEEPING mutes it.
    private func speakProceedIfDue() {
        guard !quietProximity else { return }
        let now = Date()
        // Only a spoken warning holds this back. When any obstacle report did,
        // false obstacles kept "Proceed" from ever playing.
        guard now.timeIntervalSince(lastHazardAt) > proceedAfterHazardGap else { return }
        guard now.timeIntervalSince(lastObstacleSpokenAt) > proceedAfterHazardGap else { return }
        guard now.timeIntervalSince(lastProceedAt) > proceedGap else { return }
        lastProceedAt = now
        say("Proceed.")
    }

    /// A double beep that speeds up as the edge gets closer, so he can hear
    /// where it is. Never muted.
    private func playStepBeep(distance: Float) {
        let d = max(0, min(1, distance / 0.8))       // 1 = far, 0 = at the edge
        let interval = TimeInterval(0.12 + 0.55 * Double(d))
        let now = Date()
        guard now.timeIntervalSince(lastStepBeepAt) >= interval else { return }
        lastStepBeepAt = now
        tones.play([(1200, 0.05), (0, 0.04), (1200, 0.05)], amplitude: 0.75)
        buzz(intensity: 1 - Float(d), force: true)
    }

    /// Obstacle beep: the closer it is, the higher, faster and stronger.
    private func playProximity(intensity: Float) {
        let i = max(0, min(1, intensity))
        // Cadence: ~0.6 s apart when far, ~0.12 s when very close.
        let interval = TimeInterval(0.6 - 0.48 * Double(i))
        let now = Date()
        guard now.timeIntervalSince(lastProximityAt) >= interval else { return }
        lastProximityAt = now

        if settings.tones {
            // Kept low, well under the 1568 Hz warning sound. When these went up
            // to 1400 Hz, a near obstacle sounded like a step warning.
            let hz = 300.0 + 500.0 * Double(i)   // 300 Hz far, 800 Hz near
            tones.play([(hz, 0.07)], amplitude: 0.5)
        }
        // With tones off, an obstacle still has to reach him, so it vibrates
        // whatever the vibration switch says.
        buzz(intensity: i, force: !settings.tones)
    }

    /// `force` ignores the vibration switch, for warnings.
    private func buzz(intensity: Float, force: Bool = false) {
        guard force || settings.haptics, let haptics else { return }
        let i = CHHapticEventParameter(parameterID: .hapticIntensity,
                                       value: max(0, min(1, intensity)))
        let event = CHHapticEvent(eventType: .hapticTransient, parameters: [i], relativeTime: 0)
        if let pattern = try? CHHapticPattern(events: [event], parameters: []),
           let player = try? haptics.makePlayer(with: pattern) {
            try? player.start(atTime: 0)
        }
    }
}

/// A small sine-tone player for the beeps. A segment with frequency 0 is a gap,
/// used between the two warning beeps.
@MainActor
private final class ToneGenerator {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var started = false

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    /// Play (frequency Hz, duration s) segments in order.
    func play(_ segments: [(frequency: Double, duration: Double)], amplitude: Float) {
        ensureRunning()
        guard started else { return }
        for seg in segments {
            if let buffer = makeBuffer(frequency: seg.frequency,
                                       duration: seg.duration,
                                       amplitude: amplitude) {
                player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            }
        }
    }

    /// Drop every queued tone now. The next `play` starts the player again.
    func stopAll() {
        player.stop()
        started = false
    }

    private func ensureRunning() {
        guard !started else { return }
        do {
            try engine.start()
            player.play()
            started = true
        } catch {
            started = false   // tones simply won't sound; speech/haptics still work
        }
    }

    private func makeBuffer(frequency: Double, duration: Double, amplitude: Float) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let frames = AVAudioFrameCount(max(1, duration * sampleRate))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        let n = Int(frames)
        let ramp = max(1, n / 16)   // short attack/release to avoid clicks
        let omega = 2.0 * Double.pi * frequency
        for i in 0..<n {
            if frequency <= 0 { channel[i] = 0; continue }   // silence segment
            var env: Float = 1
            if i < ramp { env = Float(i) / Float(ramp) }
            else if i > n - ramp { env = Float(n - i) / Float(ramp) }
            channel[i] = amplitude * env * Float(sin(omega * Double(i) / sampleRate))
        }
        return buffer
    }
}
