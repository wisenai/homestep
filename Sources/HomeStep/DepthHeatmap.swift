import ARKit
import CoreImage
import UIKit
import HomeStepCore

/// Turns the LiDAR depth map into a coloured overlay lined up with the camera
/// picture: near is warm (red, yellow), far is cool (blue). Display only.
enum DepthHeatmap {
    static let nearMetres: Float = 0.2
    static let farMetres: Float = 4.0

    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// Rendered at the viewport's point size (not pixels) to keep it cheap.
    static func image(for frame: ARFrame, viewport: CGSize, opacity: Float = 0.6) -> CGImage? {
        guard let depth = frame.sceneDepth?.depthMap, viewport.width > 0, viewport.height > 0,
              let colored = colorize(depth, opacity: opacity) else { return nil }
        let w = CGFloat(CVPixelBufferGetWidth(depth)), h = CGFloat(CVPixelBufferGetHeight(depth))
        // Normalize, flip for portrait, apply the camera's display transform,
        // then scale to the viewport. It's the mapping ARKit uses to draw the
        // camera picture, so the colours land on the right objects.
        let normalize = CGAffineTransform(scaleX: 1 / w, y: 1 / h)
        let flip = CGAffineTransform(scaleX: -1, y: -1).translatedBy(x: -1, y: -1)
        let display = frame.displayTransform(for: .portrait, viewportSize: viewport)
        let toView = CGAffineTransform(scaleX: viewport.width, y: viewport.height)
        let ci = CIImage(cgImage: colored)
            .transformed(by: normalize.concatenating(flip).concatenating(display).concatenating(toView))
            .cropped(to: CGRect(origin: .zero, size: viewport))
        return context.createCGImage(ci, from: CGRect(origin: .zero, size: viewport))
    }

    /// Depth (Float32 metres) → RGBA8 with the turbo colour map.
    private static func colorize(_ depth: CVPixelBuffer, opacity: Float) -> CGImage? {
        CVPixelBufferLockBaseAddress(depth, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depth, .readOnly) }
        let w = CVPixelBufferGetWidth(depth), h = CVPixelBufferGetHeight(depth)
        guard let base = CVPixelBufferGetBaseAddress(depth) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(depth)
        var out = [UInt8](repeating: 0, count: w * h * 4)
        let alpha = UInt8(max(0, min(1, opacity)) * 255)
        for y in 0..<h {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float32.self)
            for x in 0..<w {
                let d = row[x]
                guard d.isFinite, d > 0 else { continue }
                // Near = 1 (warm), far = 0 (cool).
                let t = 1 - max(0, min(1, (d - nearMetres) / (farMetres - nearMetres)))
                let (r, g, b) = turbo(t)
                let i = (y * w + x) * 4
                // Premultiplied alpha.
                out[i] = UInt8(r * Float(alpha)); out[i + 1] = UInt8(g * Float(alpha))
                out[i + 2] = UInt8(b * Float(alpha)); out[i + 3] = alpha
            }
        }
        return out.withUnsafeMutableBytes { buf -> CGImage? in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            return ctx.makeImage()
        }
    }

    /// Polynomial approximation of Google's Turbo colour map, t in 0…1.
    static func turbo(_ t: Float) -> (Float, Float, Float) {
        let x = max(0, min(1, t))
        let r = 0.13572138 + x * (4.61539260 + x * (-42.66032258 + x * (132.13108234 + x * (-152.94239396 + x * 59.28637943))))
        let g = 0.09140261 + x * (2.19418839 + x * (4.84296658 + x * (-14.18503333 + x * (4.27729857 + x * 2.82956604))))
        let b = 0.10667330 + x * (12.64194608 + x * (-60.58204836 + x * (110.36276771 + x * (-89.90310912 + x * 27.34824973))))
        return (max(0, min(1, r)), max(0, min(1, g)), max(0, min(1, b)))
    }
}
