import AVFoundation
import SwiftUI
import HomeStepCore

/// First launch: what HomeStep is, the safety page (which has to be
/// acknowledged) and camera permission. Every page works with VoiceOver, since
/// the person setting it up may be the visually impaired user.
struct OnboardingView: View {
    let onDone: () -> Void
    @State private var page = 0

    var body: some View {
        // Not a swipeable TabView: the safety page must be acknowledged with
        // its button, not skipped with a swipe.
        Group {
            switch page {
            case 0:
            OnboardingPage(
                symbol: "house",
                title: "Welcome to HomeStep",
                lines: [
                    "HomeStep guides you around the indoor places you know — your home, office or a relative's house — by voice, tones and vibration.",
                    "On iPhones with LiDAR it warns about steps down, steps up and obstacles ahead, with no setup at all.",
                    "Tape printed markers at doorways, rooms and hazards, and HomeStep speaks where you are as you walk past them.",
                ],
                button: "Next") { page = 1 }
            case 1:
            OnboardingPage(
                symbol: "figure.walk",
                title: "HomeStep supplements your cane",
                lines: [
                    "Keep using your cane, guide dog and the people around you. HomeStep is an extra warning, not a replacement.",
                    "It can miss a step, an obstacle or a marker — for example in poor light, on reflective floors, or when the phone is aimed wrongly.",
                    "It is not a medical device and is not for outdoor or street navigation. Never rely on it in an emergency.",
                ],
                button: "I understand") { page = 2 }
            default:
            OnboardingPage(
                symbol: "camera",
                title: "Camera and mounting",
                lines: [
                    "HomeStep uses the rear camera to read markers and sense the floor. Images are processed on this iPhone and never leave it.",
                    MountingGuide.text,
                    "A single-ear or bone-conduction earpiece keeps your other ear free.",
                ],
                photo: MountingGuide.photos[0],
                button: "Allow camera and start") {
                    AVCaptureDevice.requestAccess(for: .video) { _ in
                        Task { @MainActor in onDone() }
                    }
                }
            }
        }
        .id(page)   // VoiceOver starts each page from its title
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

/// How to mount the phone, as on the rig the detector was tuned and tested on.
/// Onboarding and Help share this wording so they can't drift apart.
enum MountingGuide {
    struct Photo {
        let asset: String
        let description: String
    }

    static let text = "Clamp a phone holder about halfway up your walking stick or cane. Put the iPhone in upright, screen facing you, rear camera facing forward. The camera needs to see the floor about a stride ahead; if it can't, HomeStep says \"Cannot see the floor. Tilt the phone down.\""

    /// The phone holder on the tested rig. Nil hides the link.
    static let holderURL: URL? = URL(string: "https://www.amazon.com/clp/B0DK332BPS")

    static let photos = [
        Photo(asset: "app-ready-screen-on-stick",
              description: "An iPhone held upright in a phone clamp about halfway up a black walking stick, screen facing the person holding the stick."),
        Photo(asset: "rig-at-step-edge",
              description: "A person standing at the edge of a step down, the walking stick leaning slightly forward with the phone clamped to it, rear camera facing the floor ahead."),
    ]
}

struct MountingPhoto: View {
    let photo: MountingGuide.Photo
    var maxHeight: CGFloat = 360

    var body: some View {
        Image(photo.asset)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: maxHeight)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .accessibilityLabel(photo.description)
            .accessibilityAddTraits(.isImage)
    }
}

private struct OnboardingPage: View {
    let symbol: String
    let title: String
    let lines: [String]
    var photo: MountingGuide.Photo? = nil
    let button: String
    let action: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: symbol)
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(.yellow)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let photo { MountingPhoto(photo: photo, maxHeight: 320) }
                if photo != nil, let url = MountingGuide.holderURL {
                    Link(destination: url) {
                        Label("See the phone holder we use", systemImage: "cart")
                            .font(.title3.weight(.semibold))
                    }
                    .foregroundStyle(.yellow)
                    .accessibilityHint("Opens the product page in Safari")
                }
                Button(button, action: action)
                    .buttonStyle(BigButton(background: .yellow, foreground: .black, height: 64, size: 22))
                    .padding(.top, 12)
            }
            .padding(24)
            .padding(.bottom, 48)
        }
    }
}
