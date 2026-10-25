import Foundation

/// The user's preferences, kept in UserDefaults.
///
/// None of these can silence a step or hazard warning: the Announcer ignores
/// the speech, tones and vibration switches for those.
@MainActor
final class AppSettings: ObservableObject {
    private let defaults: UserDefaults

    @Published var speech: Bool { didSet { defaults.set(speech, forKey: Key.speech) } }
    @Published var tones: Bool { didSet { defaults.set(tones, forKey: Key.tones) } }
    @Published var haptics: Bool { didSet { defaults.set(haptics, forKey: Key.haptics) } }
    /// AVSpeechUtterance rate, 0.35 (slow) … 0.65 (fast).
    @Published var speechRate: Float { didSet { defaults.set(speechRate, forKey: Key.rate) } }
    /// Shows the live depth numbers and records test walks (the log and MARK WRONG).
    @Published var developerMode: Bool { didSet { defaults.set(developerMode, forKey: Key.dev) } }
    @Published var onboardingDone: Bool { didSet { defaults.set(onboardingDone, forKey: Key.onboarded) } }

    static let speechRateRange: ClosedRange<Float> = 0.35...0.65

    private enum Key {
        static let speech = "settings.speech", tones = "settings.tones",
                   haptics = "settings.haptics", rate = "settings.speechRate",
                   dev = "settings.developerMode", onboarded = "settings.onboardingDone"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Key.speech: true, Key.tones: true, Key.haptics: true,
                                     Key.rate: Float(0.5), Key.dev: false, Key.onboarded: false])
        speech = defaults.bool(forKey: Key.speech)
        tones = defaults.bool(forKey: Key.tones)
        haptics = defaults.bool(forKey: Key.haptics)
        speechRate = defaults.float(forKey: Key.rate)
        developerMode = defaults.bool(forKey: Key.dev)
        onboardingDone = defaults.bool(forKey: Key.onboarded)
    }
}
