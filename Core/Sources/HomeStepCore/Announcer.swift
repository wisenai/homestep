import Foundation

/// Something the detector or a marker wants the user to know.
public enum AnnouncerEvent: Equatable, Sendable {
    /// A hazard marker: interrupts everything.
    case hazard(text: String)
    /// A step edge `distance` metres ahead. `speak` is false while it is still
    /// far off: the beeping alone locates it until he is close.
    case step(text: String, distance: Float, speak: Bool)
    /// Something in the way. `intensity` runs 0 (far) to 1 (touching).
    case proximity(distance: Float, intensity: Float)
    /// Walking, and nothing in the way.
    case clear
    case landmark(Landmark)

    /// Short name used in the test-walk log.
    public var logName: String {
        switch self {
        case .hazard(let text): return "hazard:\(text)"
        case .step(let text, let d, let speak):
            return "step:\(text) d=\(String(format: "%.2f", d)) spoken=\(speak)"
        case .proximity: return "proximity"
        case .clear: return "clear"
        case .landmark(let lm): return "landmark:\(lm.marker)"
        }
    }
}

/// One tone segment. A frequency of 0 is a gap.
public struct Tone: Equatable, Sendable {
    public var hz: Double
    public var seconds: Double

    public init(_ hz: Double, _ seconds: Double) {
        self.hz = hz
        self.seconds = seconds
    }
}

/// What the announcer asks the speaker, voice and vibration motor to do.
public enum Sound: Equatable, Sendable {
    /// Stop speaking now, or at the end of the current word.
    case stopSpeaking(immediately: Bool)
    case speak(String)
    case play([Tone], volume: Float)
    case stopTones
    case vibrate(Float)
}

/// Decides what HomeStep says, beeps and buzzes, and when.
///
/// The app has one output channel so warnings can't talk over each other.
/// This type holds its rules: priorities, repeat gaps and which sounds the
/// user's settings may switch off. It returns a list of `Sound`s and never
/// touches audio itself, so every rule can be tested with a fake clock.
///
/// Step and hazard warnings ignore the speech, tones and vibration settings.
/// Nothing can mute them. See docs/specs/announcer.md.
public struct AnnouncerPolicy {

    public struct Settings: Equatable, Sendable {
        public var speech = true
        public var tones = true
        public var haptics = true
        /// AVSpeechUtterance rate.
        public var rate: Float = 0.5

        public init(speech: Bool = true, tones: Bool = true, haptics: Bool = true, rate: Float = 0.5) {
            self.speech = speech
            self.tones = tones
            self.haptics = haptics
            self.rate = rate
        }
    }

    // Timing, in seconds.
    public static let landmarkCooldown: TimeInterval = 4
    /// The detector reports a step on every frame it stays in view. Without
    /// this gap each repeat would cut off the sentence before it finished.
    public static let warningRepeatGap: TimeInterval = 2.5
    /// A pause in obstacle reports this long means the next one is a new obstacle.
    public static let obstacleNewGap: TimeInterval = 1.5
    public static let obstacleRepeatGap: TimeInterval = 6
    public static let proceedGap: TimeInterval = 2
    /// "Proceed" waits this long after a spoken warning, so it never
    /// contradicts one while he is still standing at the step.
    public static let proceedAfterWarningGap: TimeInterval = 2.5
    public static let throttleGap: TimeInterval = 20

    // Sounds. Steps are high and doubled, obstacles single and low, so the two
    // can't be confused: one means go around, the other means the floor ends.
    public static let hazardEarcon = [Tone(1568, 0.09), Tone(0, 0.05), Tone(1568, 0.09)]
    public static let stepBeep = [Tone(1200, 0.05), Tone(0, 0.04), Tone(1200, 0.05)]
    /// For system messages such as "Guidance paused". Not a warning sound.
    public static let alertChime = [Tone(880, 0.10), Tone(0, 0.04), Tone(660, 0.14)]

    public var settings = Settings()
    /// The "Stop beeping" control: mutes obstacle beeps and "Proceed" only.
    public var quietProximity = false

    private var lastWarningText: String?
    private var lastWarningAt = Date.distantPast
    private var lastLandmarkID: UUID?
    private var lastLandmarkAt = Date.distantPast
    private var lastProximityAt = Date.distantPast
    private var lastObstacleSeenAt = Date.distantPast
    private var lastObstacleSpokenAt = Date.distantPast
    private var lastStepBeepAt = Date.distantPast
    private var lastProceedAt = Date.distantPast
    private var lastThrottledText: String?
    private var lastThrottledAt = Date.distantPast

    public init(settings: Settings = Settings()) {
        self.settings = settings
    }

    public mutating func emit(_ event: AnnouncerEvent, at now: Date) -> [Sound] {
        switch event {
        case .hazard(let text):
            guard !isRepeat(text, now) else { return [] }
            noteWarning(text, now)
            return [.stopSpeaking(immediately: true),
                    .play(Self.hazardEarcon, volume: 0.9),
                    .vibrate(1.0),
                    .speak(text)]

        case .step(let text, let distance, let speak):
            var sounds = stepBeep(distance: distance, now)
            guard speak, !isRepeat(text, now) else { return sounds }
            noteWarning(text, now)
            sounds += [.stopSpeaking(immediately: true), .speak(text)]
            return sounds

        case .proximity(_, let intensity):
            guard !quietProximity else { return [] }
            return obstacleWords(now) + obstacleBeep(intensity: intensity, now)

        case .clear:
            return proceed(now)

        case .landmark(let landmark):
            // A step marker takes the hazard path, so a marked step is covered
            // twice: by its marker and by the detector.
            if landmark.isHazard { return emit(.hazard(text: landmark.spokenText), at: now) }
            guard landmark.id != lastLandmarkID || now.timeIntervalSince(lastLandmarkAt) > Self.landmarkCooldown
            else { return [] }
            lastLandmarkID = landmark.id
            lastLandmarkAt = now
            return say(landmark.spokenText)
        }
    }

    /// Ordinary speech; respects the speech setting.
    public func say(_ text: String) -> [Sound] {
        settings.speech ? [.speak(text)] : []
    }

    /// Like `say`, but the same sentence at most once per `minGap`. For error
    /// messages that a stray tap could otherwise repeat.
    public mutating func sayThrottled(_ text: String, minGap: TimeInterval = throttleGap, at now: Date) -> [Sound] {
        if text == lastThrottledText, now.timeIntervalSince(lastThrottledAt) < minGap { return [] }
        lastThrottledText = text
        lastThrottledAt = now
        return say(text)
    }

    /// A change in the app's own state: paused, resumed, failed. Always spoken,
    /// because to a blind user an app that has quietly stopped sounds exactly
    /// like a clear path.
    public func alert(_ text: String) -> [Sound] {
        [.stopSpeaking(immediately: true), .play(Self.alertChime, volume: 0.7), .speak(text)]
    }

    /// The reply to something the user just did, like Start or "Where am I?".
    /// Always spoken: an unanswered button sounds like a broken app.
    public func status(_ text: String) -> [Sound] {
        [.stopSpeaking(immediately: false), .speak(text)]
    }

    /// Stop everything that is sounding now. Future warnings still play, and a
    /// new one may speak straight away.
    public mutating func silence() -> [Sound] {
        lastWarningText = nil
        lastWarningAt = .distantPast
        return [.stopSpeaking(immediately: true), .stopTones]
    }

    // MARK: - Rules

    /// The same warning again within the repeat gap. Keyed on the words, so
    /// "Step up" is never held back by a recent "Step down".
    private func isRepeat(_ text: String, _ now: Date) -> Bool {
        text == lastWarningText && now.timeIntervalSince(lastWarningAt) <= Self.warningRepeatGap
    }

    private mutating func noteWarning(_ text: String, _ now: Date) {
        lastWarningText = text
        lastWarningAt = now
    }

    /// Double beep that speeds up as the edge gets closer: about 0.67 s apart at
    /// 0.8 m or more, 0.12 s at the edge. Never muted.
    private mutating func stepBeep(distance: Float, _ now: Date) -> [Sound] {
        let far = max(0, min(1, distance / 0.8))
        let interval = 0.12 + 0.55 * Double(far)
        guard now.timeIntervalSince(lastStepBeepAt) >= interval else { return [] }
        lastStepBeepAt = now
        return [.play(Self.stepBeep, volume: 0.75), .vibrate(1 - far)]
    }

    /// One low beep, higher and faster as the obstacle gets closer: 300 Hz every
    /// 0.6 s far off, 800 Hz every 0.12 s up close. With tones off it still
    /// vibrates, so an obstacle always reaches the user somehow.
    private mutating func obstacleBeep(intensity: Float, _ now: Date) -> [Sound] {
        let i = max(0, min(1, intensity))
        let interval = 0.6 - 0.48 * Double(i)
        guard now.timeIntervalSince(lastProximityAt) >= interval else { return [] }
        lastProximityAt = now
        var sounds: [Sound] = []
        if settings.tones {
            sounds.append(.play([Tone(300 + 500 * Double(i), 0.07)], volume: 0.5))
        }
        if !settings.tones || settings.haptics {
            sounds.append(.vibrate(i))
        }
        return sounds
    }

    /// "Obstacle ahead" on a new obstacle, then at most every few seconds while
    /// it stays. The beeps carry the distance in between.
    private mutating func obstacleWords(_ now: Date) -> [Sound] {
        let isNew = now.timeIntervalSince(lastObstacleSeenAt) > Self.obstacleNewGap
        lastObstacleSeenAt = now
        guard isNew || now.timeIntervalSince(lastObstacleSpokenAt) > Self.obstacleRepeatGap else { return [] }
        lastObstacleSpokenAt = now
        return say("Obstacle ahead.")
    }

    /// "Proceed" every couple of seconds while the way is clear, so silence is
    /// never the only sign that things are fine.
    private mutating func proceed(_ now: Date) -> [Sound] {
        guard !quietProximity,
              now.timeIntervalSince(lastWarningAt) > Self.proceedAfterWarningGap,
              now.timeIntervalSince(lastObstacleSpokenAt) > Self.proceedAfterWarningGap,
              now.timeIntervalSince(lastProceedAt) > Self.proceedGap
        else { return [] }
        lastProceedAt = now
        return say("Proceed.")
    }
}
