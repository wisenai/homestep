import ARKit
import HomeStepCore

/// Connects ARKit to the step detector. Each frame's LiDAR depth map and camera
/// pose go in; an event and the frame's numbers come out. The rules themselves
/// live in `StepDetector` (HomeStepCore), where they are tested without a phone.
///
/// Runs on the ARKit thread, every frame, with no network.
final class ReflexLayer: Sendable {
    typealias Reading = StepDetector.Reading

    let settings: StepDetector.Settings

    /// How far ahead (m) a step is spoken. Set from the main actor, read here.
    let warnDistance: LockedBox<Float>

    /// For "See what HomeStep sees": while true, each frame also publishes the
    /// points it classified. Nothing here feeds back into a decision.
    let captureSnapshot = LockedBox<Bool>(false)
    let latestSnapshot = LockedBox<DetectorSnapshot?>(nil)

    private let detector: LockedBox<StepDetector>

    init(settings: StepDetector.Settings = .init()) {
        self.settings = settings
        detector = LockedBox(StepDetector(settings: settings))
        warnDistance = LockedBox(settings.defaultWarnDistance)
    }

    /// Nil when the frame has no LiDAR depth.
    func process(frame: ARFrame) -> StepDetector.Outcome? {
        guard let sceneDepth = frame.sceneDepth else { return nil }
        let camera = CameraPose(transform: frame.camera.transform, timestamp: frame.timestamp)
        let warn = warnDistance.get()
        let capture = captureSnapshot.get()
        let outcome = DepthBuffer.read(sceneDepth, withConfidence: settings.requireMediumConfidence) { depth in
            let image = frame.camera.imageResolution
            let intrinsics = CameraIntrinsics(frame.camera.intrinsics)
                .scaled(fromImage: Float(image.width), Float(image.height), toDepth: depth.width, depth.height)
            return detector.update {
                $0.process(depth: depth, camera: camera, intrinsics: intrinsics,
                           warnDistance: warn, captureSnapshot: capture)
            }
        }
        if let snapshot = outcome.snapshot { latestSnapshot.set(snapshot) }
        return outcome
    }

    /// Forget what earlier frames saw. Called on Start and after an interruption.
    func reset() {
        detector.update { $0.reset() }
    }
}

/// ARKit's depth and confidence maps, read in place while they are locked.
private enum DepthBuffer {
    static func read<R>(_ data: ARDepthData, withConfidence: Bool, _ body: (DepthMap) -> R) -> R {
        let depth = data.depthMap
        CVPixelBufferLockBaseAddress(depth, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depth, .readOnly) }

        let confidence = withConfidence ? data.confidenceMap : nil
        if let confidence { CVPixelBufferLockBaseAddress(confidence, .readOnly) }
        defer { if let confidence { CVPixelBufferUnlockBaseAddress(confidence, .readOnly) } }

        let map = DepthMap(
            width: CVPixelBufferGetWidth(depth),
            height: CVPixelBufferGetHeight(depth),
            depth: CVPixelBufferGetBaseAddress(depth).map { UnsafeRawPointer($0) },
            depthRowBytes: CVPixelBufferGetBytesPerRow(depth),
            confidence: confidence.flatMap { CVPixelBufferGetBaseAddress($0) }.map { UnsafeRawPointer($0) },
            confidenceRowBytes: confidence.map { CVPixelBufferGetBytesPerRow($0) } ?? 0)
        return body(map)
    }
}
