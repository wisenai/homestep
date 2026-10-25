import ARKit
import RealityKit
import SwiftUI

/// The live camera picture in the lower half of the guide screen, the part the
/// mount covers, so it never takes space from a control. It's for a sighted
/// helper: it shows what HomeStep is looking at when it speaks.
struct CameraWindow: View {
    @EnvironmentObject var guide: GuideController

    var body: some View {
        ZStack(alignment: .topLeading) {
            if guide.isRunning && Self.canDraw {
                SessionCameraView(session: guide.session) { guide.ensureSessionDelegate() }
            } else {
                Color.white.opacity(0.08)
                Text(guide.isRunning ? "Camera view unavailable" : "Camera view appears when guiding")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Text("CAMERA")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(.black.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Camera view, for a sighted helper")
    }

    /// The Simulator has no ARKit camera to draw.
    private static var canDraw: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        ARWorldTrackingConfiguration.isSupported
        #endif
    }
}

/// A RealityKit view that draws the guide's session. It never configures or
/// runs the session itself.
private struct SessionCameraView: UIViewRepresentable {
    let session: ARSession
    let onAttach: () -> Void

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        view.session = session
        view.renderOptions = [.disableMotionBlur, .disableDepthOfField, .disableHDR,
                              .disableCameraGrain, .disablePersonOcclusion]
        view.environment.sceneUnderstanding.options = []
        // Check now and once more after RealityKit has settled.
        onAttach()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { onAttach() }
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {}
}
