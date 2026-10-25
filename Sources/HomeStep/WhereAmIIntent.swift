import AppIntents
import HomeStepCore

/// "Where am I?" for the iPhone's Action button, Shortcuts, Back Tap or Siri:
/// HomeStep repeats the last marker it read. The user assigns it in the
/// iPhone's Settings. It brings the app to the front (ARKit only runs there)
/// and posts a notification that `GuideController` answers.
struct WhereAmIIntent: AppIntent {
    static let title: LocalizedStringResource = "Where am I?"
    static let description = IntentDescription(
        "Repeats the last place marker HomeStep read. Assign it to the Action button.")

    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .whereAmIRequested, object: nil)
        return .result()
    }
}

extension Notification.Name {
    /// Raised by `WhereAmIIntent`; observed by `GuideController`.
    static let whereAmIRequested = Notification.Name("whereAmIRequested")
}

struct HomeStepShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WhereAmIIntent(),
            phrases: ["Where am I in \(.applicationName)", "\(.applicationName) where am I"],
            shortTitle: "Where am I?",
            systemImageName: "mappin.and.ellipse"
        )
    }
}
