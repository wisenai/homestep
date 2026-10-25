import Combine
import Foundation

/// The user's preferences, kept in UserDefaults.
///
/// None of these can silence a step or hazard warning; the announcer ignores
/// them for those.
@MainActor
public final class AppSettings: ObservableObject {
    private let defaults: UserDefaults

    @Published public var speech: Bool { didSet { defaults.set(speech, forKey: Key.speech) } }
    @Published public var tones: Bool { didSet { defaults.set(tones, forKey: Key.tones) } }
    @Published public var haptics: Bool { didSet { defaults.set(haptics, forKey: Key.haptics) } }
    @Published public var speechRate: Float { didSet { defaults.set(speechRate, forKey: Key.rate) } }
    /// Shows the live depth numbers and records test walks.
    @Published public var developerMode: Bool { didSet { defaults.set(developerMode, forKey: Key.dev) } }
    @Published public var onboardingDone: Bool { didSet { defaults.set(onboardingDone, forKey: Key.onboarded) } }

    public static let speechRateRange: ClosedRange<Float> = 0.35...0.65

    enum Key {
        static let speech = "settings.speech"
        static let tones = "settings.tones"
        static let haptics = "settings.haptics"
        static let rate = "settings.speechRate"
        static let dev = "settings.developerMode"
        static let onboarded = "settings.onboardingDone"
    }

    public init(defaults: UserDefaults = .standard) {
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

    /// The parts the announcer needs.
    public var announcerSettings: AnnouncerPolicy.Settings {
        .init(speech: speech, tones: tones, haptics: haptics, rate: speechRate)
    }
}
