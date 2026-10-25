import ARKit
import Vision
import HomeStepCore

/// Reads printed markers (QR codes) in the camera picture with Vision and
/// reports their numbers.
///
/// It has no stored state, so it's `Sendable` and can run on the ARKit thread.
final class MarkerLayer: Sendable {

    /// Calls `onMarker` with the number of each HomeStep marker in the frame.
    /// Any other QR code is ignored (see `MarkerPayload`).
    func scan(frame: ARFrame, onMarker: @escaping (Int) -> Void) {
        let request = VNDetectBarcodesRequest { request, _ in
            guard let obs = request.results?.compactMap({ $0 as? VNBarcodeObservation }) else { return }
            for o in obs where o.symbology == .qr {
                if let payload = o.payloadStringValue, let id = MarkerPayload.decode(payload) {
                    onMarker(id)
                }
            }
        }
        request.symbologies = [.qr]

        // The captured image is in the sensor's own orientation; .right matches
        // the rear camera with the phone held upright, as on the stick.
        let handler = VNImageRequestHandler(cvPixelBuffer: frame.capturedImage,
                                            orientation: .right, options: [:])
        try? handler.perform([request])
    }

}
