// Renders the HomeStep app icon (1024x1024, opaque) to the path given as argv[1].
// Run: swift tools/make-icon.swift Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
import AppKit

let size = 1024
let out = CommandLine.arguments.dropFirst().first ?? "AppIcon-1024.png"
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let s = CGFloat(size)

// Dark background, bright lines: high contrast for low-vision users.
let ink = CGColor(red: 0.06, green: 0.08, blue: 0.14, alpha: 1)
let yellow = CGColor(red: 1.0, green: 0.82, blue: 0.1, alpha: 1)
let cream = CGColor(red: 1.0, green: 0.96, blue: 0.88, alpha: 1)
ctx.setFillColor(ink)
ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
ctx.setLineCap(.round)
ctx.setLineJoin(.round)

func line(_ pts: [(CGFloat, CGFloat)], width: CGFloat, color: CGColor) {
    ctx.setStrokeColor(color)
    ctx.setLineWidth(s * width)
    ctx.move(to: CGPoint(x: s * pts[0].0, y: s * pts[0].1))
    for p in pts.dropFirst() { ctx.addLine(to: CGPoint(x: s * p.0, y: s * p.1)) }
    ctx.strokePath()
}

// The house.
line([(0.14, 0.50), (0.50, 0.84), (0.86, 0.50)], width: 0.055, color: yellow)
line([(0.24, 0.58), (0.24, 0.16), (0.76, 0.16), (0.76, 0.58)], width: 0.055, color: yellow)

// The floor stepping down inside it.
line([(0.32, 0.36), (0.54, 0.36), (0.54, 0.24), (0.68, 0.24)], width: 0.045, color: cream)

// The walking stick, leaning forward, its tip on the floor just short of the edge.
let hook = s * 0.045, length = s * 0.19
ctx.saveGState()
ctx.translateBy(x: s * 0.48, y: s * 0.405)
ctx.rotate(by: .pi / 12)
ctx.setStrokeColor(yellow)
ctx.setLineWidth(s * 0.042)
ctx.move(to: .zero)
ctx.addLine(to: CGPoint(x: 0, y: length))
ctx.addArc(center: CGPoint(x: hook, y: length), radius: hook,
           startAngle: .pi, endAngle: 0, clockwise: true)
ctx.strokePath()
ctx.restoreGState()

// Sound coming from the stick: the warning, spoken before the edge.
ctx.setStrokeColor(yellow)
ctx.setLineWidth(s * 0.034)
for r in [0.07, 0.12, 0.17] as [CGFloat] {
    ctx.addArc(center: CGPoint(x: s * 0.51, y: s * 0.50), radius: s * r,
               startAngle: -.pi / 5, endAngle: .pi / 5, clockwise: false)
    ctx.strokePath()
}

let img = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: img)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
