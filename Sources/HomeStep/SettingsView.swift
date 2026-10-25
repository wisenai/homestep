import SwiftUI
import HomeStepCore

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var guide: GuideController

    var body: some View {
        Form {
            Section {
                Toggle("Speak landmarks and cues", isOn: $settings.speech)
                Toggle("Obstacle tones", isOn: $settings.tones)
                Toggle("Vibration", isOn: $settings.haptics)
                VStack(alignment: .leading) {
                    Text("Speaking rate")
                    Slider(value: $settings.speechRate, in: AppSettings.speechRateRange) {
                        Text("Speaking rate")
                    } minimumValueLabel: {
                        Image(systemName: "tortoise").accessibilityLabel("Slower")
                    } maximumValueLabel: {
                        Image(systemName: "hare").accessibilityLabel("Faster")
                    }
                }
            } header: {
                Text("Feedback")
            } footer: {
                Text("Step and hazard warnings always play, whatever these are set to. With tones off, obstacles always vibrate. Replies to Start and Where am I? are always spoken.")
            }

            Section {
                Stepper(value: Binding(get: { guide.warnDistance },
                                       set: { guide.adjustWarnDistance(by: $0 - guide.warnDistance) }),
                        in: 0.30...0.90, step: 0.05) {
                    LabeledContent("Say \"Step\" at", value: String(format: "%.2f m", guide.warnDistance))
                }
            } header: {
                Text("Step warnings (LiDAR iPhones)")
            } footer: {
                Text("How far ahead a step is announced. Beeping starts a little earlier. Increase it if you walk quickly.")
            }

            if guide.canVisualize {
                Section {
                    NavigationLink("See what HomeStep sees") { VisionView() }
                } footer: {
                    Text("A live view for sighted helpers and evaluators: the LiDAR depth, a scan of the room, and exactly which floor points HomeStep reads as level, a step or an obstacle.")
                }
            }

            Section("Help") {
                NavigationLink("How to set up HomeStep") { HelpView() }
            }

            Section {
                Toggle("Developer mode", isOn: $settings.developerMode)
            } footer: {
                Text("Shows live depth readings and records test walks on this iPhone for tuning. Recordings stay on the device.")
            }

            Section {
                Text("HomeStep supplements your cane, guide dog and the people around you. It can miss things. Do not rely on it in an emergency.")
                    .font(.footnote)
                LabeledContent("Version", value: Self.version)
            }
        }
        .navigationTitle("Settings")
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}

struct HelpView: View {
    var body: some View {
        List {
            Section("1. Mount the phone") {
                Text(MountingGuide.text)
                ForEach(MountingGuide.photos, id: \.asset) { MountingPhoto(photo: $0) }
                if let url = MountingGuide.holderURL {
                    Link("See the phone holder we use", destination: url)
                }
                Text("While guiding, the screen shows TILT DOWN or TILT UP to help a sighted helper aim the phone. Keep the camera lenses uncovered.")
            }
            Section("2. Steps and obstacles (LiDAR iPhones)") {
                Text("Press Start. HomeStep beeps as a step edge approaches and says \"Step down\" or \"Step up\" near it. Obstacles give a lower beep that speeds up as you get closer. \"Proceed\" means it sees a clear floor ahead. No setup or markers are needed.")
                Text("iPhone Pro models from iPhone 12 Pro onward have LiDAR. Other iPhones read markers only.")
            }
            Section("3. Markers") {
                Text("In Places, add a place and its landmarks — doorways, rooms, and hazards like steps. Print the markers (any printer, or save the PDF and print elsewhere) and tape each about one stride before its spot, low on a wall, door frame or baseboard, well lit and flat. HomeStep speaks the landmark when the camera sees it.")
                Text("Give each step two markers, one on each side, so it is announced from both directions.")
            }
            Section("4. Where am I?") {
                Text("Tap Where am I? — or assign it to the Action button in the iPhone's Settings — to hear the last marker again.")
            }
            Section("Safety") {
                Text("Keep using your cane or guide dog. HomeStep is an extra warning and can miss things in poor light, on shiny or dark floors, or when the phone is aimed wrongly. If HomeStep stops working it says \"Guidance stopped. Use your cane.\"")
            }
        }
        .navigationTitle("How to set up")
    }
}
