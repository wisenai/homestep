import Foundation

/// Sentences the guide speaks about its own state. Kept in one place so tests
/// can check that every failure tells the user to use their cane.
public enum Phrases {
    public static let noLiDAR = "Step detection needs a LiDAR iPhone. Reading markers only. Use your cane."
    public static let notSupported = "This phone does not support HomeStep's camera tracking."
    public static let needsCamera = "HomeStep needs the camera. Turn on camera access in the Settings app."
    public static let guidanceStopped = "Guidance stopped. Use your cane."
    public static let guidancePaused = "Guidance paused. Use your cane."
    public static let guidanceFailed = "Guidance failed. Use your cane."
    public static let guidanceResumed = "Guidance resumed."
    public static let cannotSeeFloor = "Cannot see the floor. Tilt the phone down."
    public static let lowPower = "Low power mode is on."
    public static let marked = "Marked."

    /// Every Start gets an answer; silence must never be the only reply.
    public static func guiding(place: String?) -> String {
        place.map { "Guiding. \($0)." } ?? "Guiding. Watching for steps and obstacles."
    }

    /// The active place changed while guiding. Never silent: it changes what
    /// every marker means.
    public static func placeChanged(to name: String?) -> String {
        name.map { "Now using place \($0)." } ?? "No place in use. Markers are off."
    }

    public static func warnDistance(_ metres: Float) -> String {
        String(format: "Step warning at %.2f metres", metres)
    }

    /// The reply to "Where am I?": the last marker read and how long ago.
    public static func whereAmI(lastLandmark: String?, readAt: Date?, isRunning: Bool, now: Date) -> String {
        guard let name = lastLandmark, let readAt else {
            return isRunning ? "No marker read yet." : "HomeStep is stopped. No marker read yet."
        }
        let minutes = Int(now.timeIntervalSince(readAt) / 60)
        let when = minutes < 1 ? "just now" : minutes == 1 ? "a minute ago" : "\(minutes) minutes ago"
        return "Last marker: \(name), \(when)."
    }
}

/// Help for whoever is aiming the phone on the stick.
public enum Aim {
    /// Pitch range (degrees below horizontal) that keeps both strips of floor in view.
    public static let pitchRange: ClosedRange<Float> = 25...58
    public static let minPoints = 12

    public static func hint(for reading: StepDetector.Reading?) -> String {
        guard let r = reading else { return "Waiting for depth…" }
        // Tilt comes first: aimed too flat, the floor never reaches the
        // reference strip and steps can't be detected at all.
        if r.pitchDegrees < pitchRange.lowerBound { return "TILT DOWN — aiming too flat (\(Int(r.pitchDegrees))°)" }
        if r.pitchDegrees > pitchRange.upperBound { return "TILT UP — aiming too steep (\(Int(r.pitchDegrees))°)" }
        if r.nearCount < minPoints { return "Can't see the floor underfoot — tilt down" }
        if r.farCount < minPoints { return "Can't see the floor ahead — tilt up" }
        return "Aim OK (\(Int(r.pitchDegrees))°)"
    }
}

/// Says out loud when the phone can't see the floor. Nobody watches the
/// screen while he walks, so a bad aim has to be heard.
///
/// Checked once a second. Three blind checks in a row raise the alarm, and it
/// repeats at most every 12 seconds.
public struct AimFaultMonitor {
    public static let blindChecksBeforeWarning = 3
    public static let repeatGap: TimeInterval = 12

    private var blindChecks = 0
    private var lastWarningAt = Date.distantPast

    public init() {}

    /// True when it's time to say `Phrases.cannotSeeFloor`.
    public mutating func check(nearCount: Int, now: Date) -> Bool {
        guard nearCount < Aim.minPoints else {
            blindChecks = 0
            return false
        }
        blindChecks += 1
        guard blindChecks >= Self.blindChecksBeforeWarning,
              now.timeIntervalSince(lastWarningAt) > Self.repeatGap else { return false }
        lastWarningAt = now
        return true
    }

    public mutating func reset() {
        blindChecks = 0
        lastWarningAt = .distantPast
    }
}

/// Notices when camera frames stop arriving: a locked phone, a call, heat.
/// The app can't fix those, but it must never go quiet without saying so.
public struct LivenessMonitor {
    public static let stallSeconds: TimeInterval = 2.5

    public enum Change: Equatable { case stalled, resumed }

    public private(set) var isStalled = false

    public init() {}

    public mutating func check(lastFrameAt: Date, now: Date) -> Change? {
        let stale = now.timeIntervalSince(lastFrameAt) > Self.stallSeconds
        if stale, !isStalled {
            isStalled = true
            return .stalled
        }
        if !stale, isStalled {
            isStalled = false
            return .resumed
        }
        return nil
    }

    public mutating func reset() { isStalled = false }
}

extension StepDetector.Reading {
    /// The reading as written to the test-walk log. tools/analyze-log.py reads
    /// these keys.
    public var logFields: [String: Any] {
        var f: [String: Any] = [
            "near": nearCount, "far": farCount,
            "pitch": pitchDegrees, "swing": swingDegreesPerSecond,
            "speed": groundSpeed, "walking": isWalking,
        ]
        if let v = floorReference, v.isFinite { f["ref"] = v }
        if let v = floorNow, v.isFinite { f["probe"] = v }
        if let v = probeLow, v.isFinite { f["low"] = v }
        if let v = dropVsReference, v.isFinite { f["drop"] = v }
        if let v = obstacleAhead, v.isFinite { f["obstacle"] = v }
        if let v = fallCoverage { f["fallCov"] = v }
        if let v = riseCoverage { f["riseCov"] = v }
        return f
    }
}
