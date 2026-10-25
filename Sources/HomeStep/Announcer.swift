import AVFoundation
import CoreHaptics
import HomeStepCore

/// Plays what `AnnouncerPolicy` (HomeStepCore) decides: speech, beeps and
/// vibration. Everything HomeStep says goes through here, so warnings never
/// talk over each other. The rules, and their tests, live in the policy; this
/// class only makes the sounds.
@MainActor
final class Announcer {
    private var policy = AnnouncerPolicy()

    /// The user's speech, tones and vibration switches and speaking rate.
    /// Step and hazard warnings ignore the switches.
    var settings: AnnouncerPolicy.Settings {
        get { policy.settings }
        set { policy.settings = newValue }
    }

    /// The STOP BEEPING button: mutes obstacle beeps and "Proceed" only.
    var quietProximity: Bool {
        get { policy.quietProximity }
        set { policy.quietProximity = newValue }
    }

    private let speech = AVSpeechSynthesizer()
    private var haptics: CHHapticEngine?
    private let tones = ToneGenerator()

    init() {
        try? configureAudioSession()
        haptics = try? CHHapticEngine()
        try? haptics?.start()
    }

    func emit(_ event: AnnouncerEvent) { play(policy.emit(event, at: Date())) }

    /// Ordinary speech, which respects the speech switch.
    func say(_ text: String) { play(policy.say(text)) }

    func sayThrottled(_ text: String, minGap: TimeInterval = AnnouncerPolicy.throttleGap) {
        play(policy.sayThrottled(text, minGap: minGap, at: Date()))
    }

    /// The app's own state (paused, resumed, failed). Always spoken, with a chime.
    func alert(_ text: String) { play(policy.alert(text)) }

    /// The reply to something the user just did. Always spoken.
    func status(_ text: String) { play(policy.status(text)) }

    /// Stop everything that's sounding now. Later warnings still play.
    func silence() { play(policy.silence()) }

    // MARK: - Private

    private func play(_ sounds: [Sound]) {
        for sound in sounds {
            switch sound {
            case .stopSpeaking(let immediately):
                speech.stopSpeaking(at: immediately ? .immediate : .word)
            case .speak(let text):
                let u = AVSpeechUtterance(string: text)
                u.rate = policy.settings.rate
                speech.speak(u)
            case .play(let segments, let volume):
                tones.play(segments.map { ($0.hz, $0.seconds) }, amplitude: volume)
            case .stopTones:
                tones.stopAll()
            case .vibrate(let intensity):
                buzz(intensity)
            }
        }
    }

    private func configureAudioSession() throws {
        // Lower other audio rather than stop it; meant for a single earpiece.
        let s = AVAudioSession.sharedInstance()
        try s.setCategory(.playback, options: [.duckOthers])
        try s.setActive(true)
    }

    private func buzz(_ intensity: Float) {
        guard let haptics else { return }
        let i = CHHapticEventParameter(parameterID: .hapticIntensity, value: max(0, min(1, intensity)))
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
