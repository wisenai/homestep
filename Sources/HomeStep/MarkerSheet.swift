import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import HomeStepCore

/// Printable markers for a place: one US Letter page each, a large QR code
/// with the landmark's name and number underneath so whoever tapes them up can
/// tell them apart. Made on the phone and shared with the share sheet.
enum MarkerSheet {
    static let pageSize = CGSize(width: 612, height: 792)   // US Letter, points

    /// The QR code for one marker, with high error correction so a scuffed or
    /// shadowed marker low on a wall still reads.
    static func qrImage(for marker: Int, side: CGFloat) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(MarkerPayload.encode(marker).utf8)
        filter.correctionLevel = "H"
        guard let output = filter.outputImage else { return nil }
        let scale = side / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    static func pdf(for place: Place, landmarks: [Landmark]? = nil) -> Data {
        let items = landmarks ?? place.landmarks
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        return renderer.pdfData { ctx in
            for lm in items {
                ctx.beginPage()
                draw(lm, placeName: place.name)
            }
        }
    }

    /// Writes the PDF to a temporary file named after the place, for sharing.
    static func pdfFile(for place: Place) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeFileName(place.name)) markers.pdf")
        try pdf(for: place).write(to: url, options: .atomic)
        return url
    }

    static func safeFileName(_ name: String) -> String {
        let cleaned = name.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>"))
            .joined(separator: "-").trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "HomeStep" : cleaned
    }

    private static func draw(_ lm: Landmark, placeName: String) {
        let margin: CGFloat = 54
        let width = pageSize.width - margin * 2
        let qrSide: CGFloat = 432   // 6 inches: readable from about a stride away

        func text(_ s: String, _ font: UIFont, _ y: CGFloat, color: UIColor = .black) -> CGFloat {
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color,
                                                        .paragraphStyle: style]
            let rect = CGRect(x: margin, y: y, width: width, height: .greatestFiniteMagnitude)
            let h = (s as NSString).boundingRect(with: rect.size, options: .usesLineFragmentOrigin,
                                                 attributes: attrs, context: nil).height
            (s as NSString).draw(with: CGRect(x: margin, y: y, width: width, height: h),
                                 options: .usesLineFragmentOrigin, attributes: attrs, context: nil)
            return y + h
        }

        var y = text("\(placeName) · HomeStep marker \(lm.marker)",
                     .systemFont(ofSize: 14, weight: .medium), margin, color: .darkGray)
        y += 18
        if let qr = qrImage(for: lm.marker, side: qrSide) {
            qr.draw(in: CGRect(x: (pageSize.width - qrSide) / 2, y: y, width: qrSide, height: qrSide))
        }
        y += qrSide + 22
        y = text(lm.name.isEmpty ? "Marker \(lm.marker)" : lm.name,
                 .systemFont(ofSize: 34, weight: .heavy), y)
        y += 4
        y = text(lm.kind.title + (lm.isHazard ? " — hazard" : ""),
                 .systemFont(ofSize: 18, weight: .semibold), y,
                 color: lm.isHazard ? UIColor(red: 0.75, green: 0.1, blue: 0.1, alpha: 1) : .darkGray)
        y += 14
        let hint = lm.isHazard
            ? "Place about one stride BEFORE the hazard, low on a wall, door frame or baseboard, facing the way people approach. Put a marker on each side of a step."
            : "Place about one stride before the spot, low on a wall, door frame or baseboard, facing the way people approach. Keep it well lit and flat."
        _ = text(hint, .systemFont(ofSize: 13), y, color: .darkGray)
    }
}
