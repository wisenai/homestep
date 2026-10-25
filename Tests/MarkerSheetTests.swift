import CoreImage
import PDFKit
import XCTest
@testable import HomeStep

final class MarkerSheetTests: XCTestCase {

    func testOnePagePerLandmark() throws {
        let place = Place(name: "Home", landmarks: [
            Landmark(marker: 1, name: "Kitchen", kind: .landmark),
            Landmark(marker: 2, name: "Porch", kind: .stepDown),
            Landmark(marker: 3, name: "Bath", kind: .landmark),
        ])
        let doc = try XCTUnwrap(PDFDocument(data: MarkerSheet.pdf(for: place)))
        XCTAssertEqual(doc.pageCount, 3)
        XCTAssertTrue(doc.page(at: 1)?.string?.contains("Porch") ?? false)
    }

    func testPrintedQRDecodesBackToItsMarker() throws {
        let image = try XCTUnwrap(MarkerSheet.qrImage(for: 17, side: 300))
        let ci = try XCTUnwrap(CIImage(image: image))
        let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                                options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        let payload = try XCTUnwrap((detector.features(in: ci).first as? CIQRCodeFeature)?.messageString)
        XCTAssertEqual(MarkerPayload.decode(payload), 17)
    }

    func testFileNameIsSafe() {
        XCTAssertEqual(MarkerSheet.safeFileName("Mum's flat/2nd floor"), "Mum's flat-2nd floor")
        XCTAssertEqual(MarkerSheet.safeFileName("  "), "HomeStep")
    }

    /// Writes the sample place's markers to build/sample-markers.pdf when run
    /// from the HomeStep scheme, which sets ARTIFACT_DIR.
    func testWritesReviewMarkerSheet() throws {
        let pdf = MarkerSheet.pdf(for: .sample())
        XCTAssertEqual(PDFDocument(data: pdf)?.pageCount, 4)
        guard let dir = ProcessInfo.processInfo.environment["ARTIFACT_DIR"] else { return }
        try pdf.write(to: URL(fileURLWithPath: dir).appendingPathComponent("sample-markers.pdf"))
    }
}
