import SwiftUI

@main
struct HomeStepApp: App {
    @StateObject private var places: PlaceStore
    @StateObject private var settings: AppSettings
    @StateObject private var guide: GuideController

    init() {
        #if DEBUG
        // UI tests start from a clean slate.
        if ProcessInfo.processInfo.arguments.contains("-resetPlaces") {
            try? FileManager.default.removeItem(
                at: PlaceStore.defaultDirectory.appendingPathComponent("places.json"))
        }
        #endif
        let places = PlaceStore()
        let settings = AppSettings()
        _places = StateObject(wrappedValue: places)
        _settings = StateObject(wrappedValue: settings)
        _guide = StateObject(wrappedValue: GuideController(places: places, settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(places)
                .environmentObject(settings)
                .environmentObject(guide)
        }
    }
}

/// Onboarding once, then the guide screen.
struct RootView: View {
    @EnvironmentObject var places: PlaceStore
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var guide: GuideController
    @State private var importError: String?
    @State private var importNotice: String?

    var body: some View {
        Group {
            if settings.onboardingDone {
                NavigationStack { GuideView() }
                    #if DEBUG
                    .onAppear {
                        if ProcessInfo.processInfo.arguments.contains("-demoRunning") {
                            guide.showDemoRunningState(places: places)
                        }
                    }
                    #endif
            } else {
                OnboardingView { settings.onboardingDone = true }
            }
        }
        // A place shared as a .homestep file (AirDrop, Messages, Files) opens here.
        .onOpenURL { url in
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                // Added but not switched on: changing places changes what every
                // marker means, so that stays the user's choice.
                let place = try places.importPlace(from: Data(contentsOf: url))
                importNotice = "\"\(place.name)\" was added to Places. Open Places and choose Use this place to switch to it."
            } catch {
                importError = "That file isn't a HomeStep place."
            }
        }
        .alert("Couldn't import", isPresented: .constant(importError != nil)) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .alert("Place imported", isPresented: .constant(importNotice != nil)) {
            Button("OK") { importNotice = nil }
        } message: {
            Text(importNotice ?? "")
        }
        .alert("Places problem", isPresented: .constant(places.problem != nil)) {
            Button("OK") { places.problem = nil }
        } message: {
            Text(places.problem ?? "")
        }
    }
}
