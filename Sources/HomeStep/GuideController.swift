import ARKit
import AVFoundation
import Combine

/// Runs a guiding session. Owns the ARSession, passes every frame to the step
/// detector (`ReflexLayer`) and the marker reader (`MarkerLayer`), and sends what
/// they find to the Announcer. Markers are looked up in the active place.
@MainActor
final class GuideController: NSObject, ObservableObject, ARSessionDelegate {
    @Published var isRunning = false
    @Published var statusText = "Ready"
    /// Live depth numbers for the developer readout, updated about 8 times a second.
    @Published var reading: ReflexLayer.Reading?
    @Published var isQuiet = false
    /// How far ahead a step is announced, in metres. It's a setting because the
    /// right value depends on walking pace and the room, and is found by walking
    /// at the real step.
    @Published var warnDistance: Float = 0.45
    /// False on iPhones without LiDAR: markers are read, steps aren't detected.
    @Published private(set) var hasDepth = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    /// Name of the last landmark read, for "Where am I?".
    @Published private(set) var lastLandmark: (name: String, at: Date)?
    private static let warnDistanceKey = "reflex.warnDistance"

    func adjustWarnDistance(by delta: Float) {
        let t = reflex.t
        let next = min(t.maxWarnDistance, max(t.minWarnDistance, warnDistance + delta))
        warnDistance = next
        reflex.warnDistance.set(next)
        UserDefaults.standard.set(Double(next), forKey: Self.warnDistanceKey)
        logger.log("warnDistance", ["value": next])
        announcer.status(String(format: "Step warning at %.2f metres", next))
    }

    private func restoreWarnDistance() {
        let stored = UserDefaults.standard.object(forKey: Self.warnDistanceKey) as? Double
        let v = stored.map { Float($0) } ?? 0.45
        warnDistance = min(reflex.t.maxWarnDistance, max(reflex.t.minWarnDistance, v))
        reflex.warnDistance.set(warnDistance)
    }

    /// Tells whoever is aiming the phone whether the floor is in view.
    #if DEBUG
    private var demoAim = false
    #endif

    var aimHint: String {
        guard isRunning else { return "Press Start" }
        #if DEBUG
        if demoAim { return "Aim OK (42°)" }
        #endif
        guard let r = reading else { return "Waiting for depth…" }
        // Tilt comes first: aimed too flat, the floor never reaches the
        // reference strip and steps can't be detected at all.
        if r.pitchDegrees < 25 { return "TILT DOWN — aiming too flat (\(Int(r.pitchDegrees))°)" }
        if r.pitchDegrees > 58 { return "TILT UP — aiming too steep (\(Int(r.pitchDegrees))°)" }
        if r.nearCount < 12 { return "Can't see the floor underfoot — tilt down" }
        if r.farCount < 12 { return "Can't see the floor ahead — tilt up" }
        return "Aim OK (\(Int(r.pitchDegrees))°)"
    }

    /// Not private only so the camera window and "See what HomeStep sees" can
    /// draw it. Nothing else may run or reconfigure it.
    let session = ARSession()
    /// Room-mesh scanning for "See what HomeStep sees". Display only.
    private var roomScan = false
    /// The last spoken warning, flashed on "See what HomeStep sees".
    @Published private(set) var lastWarning: (text: String, at: Date)?
    private let announcer = Announcer()
    // The detector and marker reader run on the ARKit thread, off the main
    // actor, so a busy screen can't delay a warning. Only the Announcer runs on
    // the main actor, reached with Task { @MainActor }.
    private nonisolated let reflex = ReflexLayer()
    private nonisolated let markers = MarkerLayer()
    /// The active place, published by `PlaceStore` for the ARKit thread.
    private nonisolated let activePlace: LockedBox<Place?>
    private let settings: AppSettings
    private var settingsSink: AnyCancellable?
    private var placeSink: AnyCancellable?

    /// The newest depth numbers, written every frame on the ARKit thread.
    private nonisolated let latestReading = LockedBox<ReflexLayer.Reading?>(nil)
    private nonisolated let lastPublish = LockedBox<Date>(.distantPast)

    /// When the last camera frame arrived, and whether we've already said that
    /// frames stopped. He can't see that the app has stopped, so it has to be
    /// said (see `checkLiveness`).
    private nonisolated let lastFrameAt = LockedBox<Date>(.distantPast)
    private var guidanceStalled = false
    private var watchdog: Task<Void, Never>?
    /// Frames can pause briefly. Longer than this and something is wrong: the
    /// app is in the background, the phone is locked or too hot.
    private let stallSeconds: TimeInterval = 2.5
    private var blindFrames = 0
    private var lastAimWarningAt = Date.distantPast
    private let logger = SessionLogger()
    @Published var sessionCount = SessionLogger.sessionCount()

    /// Mark the last few seconds as wrong in the log. Only the person walking
    /// knows whether a warning was right, so this is how a bad one gets found
    /// later in the readings.
    func markWrong() {
        logger.log("mark", ["label": "wrong", "reading": readingFields(reading)])
        announcer.say("Marked.")
    }

    private func readingFields(_ r: ReflexLayer.Reading?) -> [String: Any] {
        guard let r else { return [:] }
        var f: [String: Any] = [
            "near": r.nearCount, "far": r.farCount,
            "pitch": r.pitchDegrees, "swing": r.swingDegreesPerSecond,
            "speed": r.groundSpeed, "walking": r.isWalking,
        ]
        if let v = r.floorReference, v.isFinite { f["ref"] = v }
        if let v = r.floorNow, v.isFinite { f["probe"] = v }
        if let v = r.probeLow, v.isFinite { f["low"] = v }
        if let v = r.dropVsReference, v.isFinite { f["drop"] = v }
        if let v = r.obstacleAhead, v.isFinite { f["obstacle"] = v }
        if let v = r.fallCoverage { f["fallCov"] = v }
        if let v = r.riseCoverage { f["riseCov"] = v }
        return f
    }

    private func eventName(_ e: AnnouncerEvent) -> String {
        switch e {
        case .hazard(let text): return "hazard:\(text)"
        case .step(let text, let d, let speak):
            return "step:\(text) d=\(String(format: "%.2f", d)) spoken=\(speak)"
        case .proximity: return "proximity"
        case .clear: return "clear"
        case .landmark(let lm): return "landmark:\(lm.marker)"
        case .cognition: return "cognition"
        }
    }

    init(places: PlaceStore, settings: AppSettings) {
        self.activePlace = places.activeSnapshot
        self.settings = settings
        super.init()
        restoreWarnDistance()
        session.delegate = self
        settingsSink = settings.objectWillChange.sink { [weak self] in
            // objectWillChange fires before the new value lands.
            DispatchQueue.main.async { self?.applySettings() }
        }
        applySettings()
        // The active place decides what every marker means, so a change while
        // guiding is always said out loud.
        placeSink = places.$activePlaceID.dropFirst().removeDuplicates().sink { [weak self, weak places] id in
            DispatchQueue.main.async {
                guard let self, self.isRunning else { return }
                let name = places?.places.first { $0.id == id }?.name
                self.announcer.alert(name.map { "Now using place \($0)." } ?? "No place in use. Markers are off.")
            }
        }
        // Action button or Shortcut: "Where am I?"
        NotificationCenter.default.addObserver(
            forName: .whereAmIRequested, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.whereAmI() }
        }
    }

    #if DEBUG
    /// For screenshots and UI tests only, never in Release: shows the running
    /// screen in the Simulator, which has no camera or LiDAR.
    func showDemoRunningState(places: PlaceStore) {
        if places.places.isEmpty { places.activePlaceID = places.importSample().id }
        // Screenshots show a LiDAR iPhone, the phone HomeStep is built for.
        hasDepth = true
        demoAim = true
        isRunning = true
        statusText = "Kitchen"
        lastLandmark = ("Kitchen", Date())
    }
    #endif

    private func applySettings() {
        announcer.settings = .init(speech: settings.speech, tones: settings.tones,
                                   haptics: settings.haptics, rate: settings.speechRate)
    }

    private func makeConfiguration() -> ARWorldTrackingConfiguration {
        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravity
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics = .sceneDepth
        }
        // The room mesh is only drawn on "See what HomeStep sees"; no decision
        // reads it. Off whenever that screen is closed.
        if roomScan, ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .meshWithClassification
        }
        return config
    }

    var canVisualize: Bool {
        ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    }

    /// Called when "See what HomeStep sees" opens and closes. Turns the detector
    /// snapshot and room mesh on and off. Re-running the configuration without a
    /// reset keeps tracking, so guiding carries on undisturbed.
    func setVisualization(_ on: Bool) {
        reflex.captureSnapshot.set(on)
        if !on { reflex.latestSnapshot.set(nil) }
        roomScan = on
        if isRunning { session.run(makeConfiguration()) }
    }

    /// RealityKit may draw the session but must never take its delegate, or the
    /// detector would stop getting frames. Called after a view attaches; puts
    /// the delegate back if anything replaced it.
    func ensureSessionDelegate() {
        if session.delegate !== self {
            session.delegate = self
            logger.log("delegateRestored")
        }
    }

    /// Newest detector snapshot (nil unless the visualization screen is open).
    nonisolated var detectorSnapshot: DetectorSnapshot? { reflex.latestSnapshot.get() }

    /// Repeat the last marker read. This is the Action button's job.
    func whereAmI() {
        guard let last = lastLandmark else {
            announcer.status(isRunning ? "No marker read yet." : "HomeStep is stopped. No marker read yet.")
            return
        }
        let minutes = Int(Date().timeIntervalSince(last.at) / 60)
        let when = minutes < 1 ? "just now" : minutes == 1 ? "a minute ago" : "\(minutes) minutes ago"
        announcer.status("Last marker: \(last.name), \(when).")
    }

    /// Say a landmark exactly as it will sound while walking, so it can be
    /// checked without printing the marker.
    func preview(_ landmark: Landmark) {
        announcer.emit(.landmark(landmark))
    }

    func start() {
        guard ARWorldTrackingConfiguration.isSupported else {
            statusText = "This iPhone can't run HomeStep."
            announcer.alert("This phone does not support HomeStep's camera tracking.")
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted:
            statusText = "Camera access is off. Turn it on in Settings, HomeStep."
            announcer.alert("HomeStep needs the camera. Turn on camera access in the Settings app.")
            return
        default: break   // .notDetermined: ARKit asks on first run
        }
        let config = makeConfiguration()
        // Steps and obstacles need LiDAR. Without it HomeStep still reads
        // markers, and says out loud that steps won't be detected.
        hasDepth = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        if hasDepth { config.frameSemantics = .sceneDepth }
        // The detector measures floor height, which needs a world aligned with
        // gravity. Set explicitly rather than left to the default.
        config.worldAlignment = .gravity
        // Start fresh, not with whatever the phone saw while stopped.
        reflex.reset()
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        UIApplication.shared.isIdleTimerDisabled = true
        isRunning = true
        guidanceStalled = false
        blindFrames = 0
        lastAimWarningAt = .distantPast
        lastFrameAt.set(Date())
        startWatchdog()
        if settings.developerMode { logger.begin() }
        logger.log("start", ["warnDistance": warnDistance,
                             "lowPower": ProcessInfo.processInfo.isLowPowerModeEnabled])
        statusText = "Guiding"
        if !hasDepth {
            statusText = "Markers only"
            announcer.alert("Step detection needs a LiDAR iPhone. Reading markers only. Use your cane.")
        } else {
            // Always answer Start out loud.
            let place = activePlace.get()?.name
            announcer.status(place.map { "Guiding. \($0)." } ?? "Guiding. Watching for steps and obstacles.")
        }

        // Low Power Mode can lower the frame rate the detector relies on.
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            announcer.say("Low power mode is on.")
        }
    }

    /// Checks once a second that camera frames are still arriving. iOS stops
    /// them when the phone locks, a call comes in or it gets too hot. The app
    /// can't fix that, but it can say so, because silence sounds like a clear
    /// path.
    private func startWatchdog() {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.checkLiveness()
                self?.checkAim()
            }
        }
    }

    /// Says so when the phone can't see the floor.
    ///
    /// One test walk was lost to this: the phone sat almost level instead of
    /// about 40° down, so steps couldn't be detected at all. The screen said so
    /// the whole time, but nobody looks at the screen while he walks.
    private func checkAim() {
        guard isRunning, hasDepth, !guidanceStalled, let r = reading else { return }
        let blind = r.nearCount < 12
        if blind {
            blindFrames += 1
            // A sweep can lift the floor out of view briefly, but not for 3 s.
            if blindFrames >= 3, Date().timeIntervalSince(lastAimWarningAt) > 12 {
                lastAimWarningAt = Date()
                announcer.alert("Cannot see the floor. Tilt the phone down.")
                logger.log("aimFault", ["pitch": r.pitchDegrees, "near": r.nearCount])
            }
        } else {
            blindFrames = 0
        }
    }

    private func checkLiveness() {
        guard isRunning else { return }
        let stale = Date().timeIntervalSince(lastFrameAt.get()) > stallSeconds
        if stale && !guidanceStalled {
            guidanceStalled = true
            statusText = "NOT GUIDING"
            announcer.alert("Guidance stopped. Use your cane.")
        } else if !stale && guidanceStalled {
            guidanceStalled = false
            statusText = hasDepth ? "Guiding" : "Markers only"
            // ARKit's origin may have moved during the gap, so start fresh.
            reflex.reset()
            announcer.alert("Guidance resumed.")
        }
    }

    func stop() {
        watchdog?.cancel()
        watchdog = nil
        guidanceStalled = false
        session.pause()
        // Pausing stops new events, but speech and queued tones are already
        // playing. Stop silences those too.
        announcer.silence()
        announcer.quietProximity = false
        UIApplication.shared.isIdleTimerDisabled = false
        isRunning = false
        reading = nil
        logger.log("stop")
        logger.close()
        sessionCount = SessionLogger.sessionCount()
        statusText = "Stopped"
    }

    /// The STOP BEEPING button: silences everything now and mutes obstacle
    /// beeps until tapped again. Step and hazard warnings stay on.
    func toggleQuiet() {
        announcer.silence()
        announcer.quietProximity.toggle()
        isQuiet = announcer.quietProximity
    }


    // MARK: ARSessionDelegate

    /// A call, Siri or a locked phone stops the frames. Say so, because the app
    /// going quiet would sound like a clear path.
    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor in
            guard isRunning else { return }
            statusText = "PAUSED"
            announcer.alert("Guidance paused. Use your cane.")
        }
    }

    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        Task { @MainActor in
            guard isRunning else { return }
            // ARKit's origin can move after an interruption, so start fresh.
            reflex.reset()
            lastFrameAt.set(Date())
            guidanceStalled = false
            statusText = hasDepth ? "Guiding" : "Markers only"
            announcer.alert("Guidance resumed.")
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor in
            // stop() silences the announcer, so it goes first; otherwise it
            // would cut off this warning.
            stop()
            statusText = "GUIDANCE FAILED"
            announcer.alert("Guidance failed. Use your cane.")
        }
    }

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        lastFrameAt.set(Date())
        // Steps and obstacles, on this thread, every frame.
        let outcome = reflex.process(frame: frame)
        if let event = outcome.event {
            Task { @MainActor in
                announcer.emit(event)
                switch event {
                case .hazard(let text): self.lastWarning = (text, Date())
                case .step(let text, _, true): self.lastWarning = (text, Date())
                default: break
                }
                // Log every event with the numbers behind it, except "clear",
                // which fires all the time while walking.
                if case .clear = event {} else {
                    self.logger.log("event", ["event": self.eventName(event),
                                              "reading": self.readingFields(outcome.reading)])
                }
            }
        }
        // Numbers for the readout: stored every frame, shown about 8 times a
        // second so the screen never slows the detector down.
        if let r = outcome.reading {
            latestReading.set(r)
            let now = Date()
            if now.timeIntervalSince(lastPublish.get()) > 0.12 {
                lastPublish.set(now)
                Task { @MainActor in
                    self.reading = r
                    // About 8 readings a second, as context for events and marks.
                    self.logger.log("reading", self.readingFields(r))
                }
            }
        }
        // Markers: look the number up in the active place. Unknown numbers are
        // ignored.
        markers.scan(frame: frame) { [weak self] marker in
            guard let self, let landmark = self.activePlace.get()?.landmark(forMarker: marker)
            else { return }
            Task { @MainActor in
                self.statusText = landmark.name
                self.lastLandmark = (landmark.name, Date())
                self.announcer.emit(.landmark(landmark))
            }
        }
    }
}
