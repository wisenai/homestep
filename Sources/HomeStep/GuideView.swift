import SwiftUI

/// The guide screen. The user may not see it at all, so it's large,
/// high-contrast and labelled for VoiceOver.
///
/// The controls sit at the top, the only part of the screen the mount leaves
/// free when the phone is clamped to the stick.
struct GuideView: View {
    @EnvironmentObject var guide: GuideController
    @EnvironmentObject var places: PlaceStore
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                (guide.isRunning ? Color(red: 0, green: 0.42, blue: 0.16) : Color.black)   // dark green keeps white text readable
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    controls
                        // All controls in the top half: the mount covers the bottom.
                        .frame(height: geo.size.height * 0.5, alignment: .top)
                        .padding(.top, 8)

                    // The lower half shows the camera, for a helper.
                    CameraWindow()
                        .padding(.bottom, 12)
                }
                .padding(.horizontal, 20)
            }
        }
        .navigationTitle("HomeStep")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink { PlacesView() } label: {
                    Label("Places", systemImage: "map").labelStyle(.titleAndIcon)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { SettingsView() } label: {
                    Label("Settings", systemImage: "gearshape").labelStyle(.titleAndIcon)
                }
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
                // Silences everything now and mutes obstacle beeps until tapped
                // again. Step and hazard warnings stay on; no control turns them off.
                Button(guide.isQuiet ? "BEEPS OFF — tap to re-enable" : "STOP BEEPING") {
                    guide.toggleQuiet()
                }
                .buttonStyle(BigButton(background: guide.isQuiet ? .orange : .red,
                                       foreground: .white, height: 52, size: 18))
                .accessibilityHint("Silences obstacle beeps. Step warnings still play.")

                Text(placeLine)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Button(guide.isRunning ? "Stop" : "Start") {
                    guide.isRunning ? guide.stop() : guide.start()
                }
                .buttonStyle(BigButton(background: .white, foreground: .black,
                                       height: 68, size: 27))
                .accessibilityHint("Starts or stops guidance")

                // A button, not a tap anywhere: handling the phone on a moving
                // stick would set a full-screen target off all the time. The
                // Action button can do this too (WhereAmIIntent).
                Button("Where am I?") { guide.whereAmI() }
                    .buttonStyle(BigButton(background: .blue, foreground: .white,
                                           height: 48, size: 19))
                    .accessibilityHint("Repeats the last marker HomeStep read")

                // Fixed heights, so the text below doesn't jump around.
                Text(guide.statusText)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .frame(height: 24)
                    .accessibilityLabel(guide.statusText)

                // A helper aims the phone by this line, so it shows outside
                // developer mode too.
                if guide.isRunning && guide.hasDepth && !settings.developerMode {
                    Text(guide.aimHint)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(guide.aimHint.hasPrefix("Aim OK") ? .white : .yellow)
                        .multilineTextAlignment(.center)
                }

                if guide.isRunning && !guide.hasDepth {
                    Text("No LiDAR on this iPhone: reading markers only. Steps and obstacles are NOT detected.")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.yellow)
                        .multilineTextAlignment(.center)
                }

                if settings.developerMode {
                HStack(spacing: 10) {
                    warnDistanceControl
                    // Only the person walking knows when a warning was wrong.
                    // Tapping this marks the moment in the log.
                    Button("MARK\nWRONG") { guide.markWrong() }
                        .buttonStyle(BigButton(background: .yellow, foreground: .black,
                                               height: 38, size: 12))
                        .frame(width: 78)
                        .disabled(!guide.isRunning)
                        .accessibilityHint("Marks the last warning as incorrect in the log")
                }

                depthReadout
                }

                Spacer(minLength: 0)
            }
    }

    private var placeLine: String {
        let place = places.activePlace.map { "Place: \($0.name)" } ?? "No place in use"
        return place + (guide.hasDepth ? "" : " · no step detection on this iPhone")
    }

    /// How far ahead a step is announced. On screen so it can be tuned while
    /// walking at the real step.
    private var warnDistanceControl: some View {
        HStack(spacing: 10) {
            Button("−") { guide.adjustWarnDistance(by: -0.05) }
                .buttonStyle(BigButton(background: .white.opacity(0.9), foreground: .black,
                                       height: 38, size: 22))
                .frame(width: 54)
                .accessibilityLabel("Warn closer to the step")

            VStack(spacing: 0) {
                Text("SPEAK AT")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                Text(String(format: "%.2f m", guide.warnDistance))
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)

            Button("+") { guide.adjustWarnDistance(by: 0.05) }
                .buttonStyle(BigButton(background: .white.opacity(0.9), foreground: .black,
                                       height: 38, size: 22))
                .frame(width: 54)
                .accessibilityLabel("Warn further from the step")
        }
        .accessibilityElement(children: .contain)
    }

    /// Live numbers from the detector, for whoever is aiming and tuning. Heights
    /// are measured against gravity, so they hold still while the cane swings.
    private var depthReadout: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                metric("TILT", guide.reading?.pitchDegrees, "°")
                metric("DROP", guide.reading?.dropVsReference, "m")
                metric("STEP", guide.reading?.stepDistance, "m")
                metric("OBST", guide.reading?.obstacleAhead, "m")
            }
            HStack(spacing: 10) {
                Text("ref \(fmt(guide.reading?.floorReference))")
                Text("pts \(guide.reading?.nearCount ?? 0)/\(guide.reading?.farCount ?? 0)")
                Text("swing \(fmt(guide.reading?.swingDegreesPerSecond))")
                Text((guide.reading?.isWalking ?? false) ? "walking" : "still")
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.white.opacity(0.75))

            Text(guide.aimHint)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(guide.aimHint.hasPrefix("Aim OK") ? .white : .yellow)
                .multilineTextAlignment(.center)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private func metric(_ label: String, _ value: Float?, _ unit: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
            Text(value.map { $0.isFinite ? String(format: "%.2f\(unit)", $0) : "—" } ?? "—")
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
    }

    private func fmt(_ v: Float?) -> String {
        guard let v, v.isFinite else { return "—" }
        return String(format: "%.2f", v)
    }
}

/// The look shared by the large, high-contrast buttons.
struct BigButton: ButtonStyle {
    let background: Color
    let foreground: Color
    let height: CGFloat
    let size: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size, weight: .heavy))
            .frame(maxWidth: .infinity, minHeight: height)
            .background(background)
            .foregroundStyle(foreground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
