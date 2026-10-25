import ARKit
import SwiftUI
import HomeStepCore

/// "See what HomeStep sees", for helpers setting it up and anyone curious.
///
/// Draws the guide's own session with switchable layers (camera, room mesh,
/// LiDAR depth, the detector's classified points) and a side view of the floor
/// ahead. Everything comes from the same frames the warnings come from. The room
/// mesh is labelled display-only because no decision reads it.
struct VisionView: View {
    @EnvironmentObject var guide: GuideController
    @State private var showMesh = true
    // Off at first: the colour wash hides the camera and the mesh.
    @State private var showDepth = false
    @State private var showDetector = true
    @State private var startedHere = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()

                // The camera picture and every layer are drawn here from the
                // current frame, about 15 times a second. Not a second RealityKit
                // view: two views on one session leave one of them blank.
                TimelineView(.periodic(from: .now, by: 1.0 / 15)) { tl in
                    LiveOverlay(tick: tl.date, guide: guide, viewport: geo.size, showMesh: showMesh,
                                showDepth: showDepth, showDetector: showDetector)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)

                VStack(spacing: 8) {
                    layerToggles
                    WarningFlash()
                    Spacer()
                    TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                        ProfilePanel(snapshot: guide.detectorSnapshot, reading: guide.reading)
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(meshCaption)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(.black.opacity(0.55), in: Capsule())
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .navigationTitle("See what HomeStep sees")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            // Start guiding if it isn't running, and on leaving stop it only
            // if this screen started it.
            if !guide.isRunning { guide.start(); startedHere = guide.isRunning }
            guide.setVisualization(true)
        }
        .onDisappear {
            guide.setVisualization(false)
            if startedHere { guide.stop(); startedHere = false }
        }
    }

    /// Shows whether the room scan is arriving.
    private var meshCaption: String {
        let pieces = guide.session.currentFrame?.anchors.filter { $0 is ARMeshAnchor }.count ?? 0
        let scan = pieces == 0 ? "Scanning the room… move the phone slowly" : "Room mesh: \(pieces) pieces"
        return scan + " · for display only; warnings come from live depth"
    }

    private var layerToggles: some View {
        HStack(spacing: 8) {
            LayerChip(title: "Mesh", color: .cyan, isOn: $showMesh)
            LayerChip(title: "Depth", color: .orange, isOn: $showDepth)
            LayerChip(title: "Detector", color: .green, isOn: $showDetector)
        }
        .padding(.top, 8)
    }
}

// MARK: - Overlays

private struct LiveOverlay: View {
    /// Changes every refresh. Without it SwiftUI sees the same inputs, never
    /// redraws, and the picture freezes.
    let tick: Date
    let guide: GuideController
    let viewport: CGSize
    let showMesh: Bool
    let showDepth: Bool
    let showDetector: Bool

    var body: some View {
        let frame = guide.session.currentFrame
        ZStack {
            if let frame, let img = CameraImage.image(for: frame, viewport: viewport) {
                Image(decorative: img, scale: CameraImage.scale)
                    .resizable()
                    .frame(width: viewport.width, height: viewport.height)
            }
            if showDepth, let frame, let img = DepthHeatmap.image(for: frame, viewport: viewport) {
                Image(decorative: img, scale: 1)
                    .resizable()
                    .frame(width: viewport.width, height: viewport.height)
            }
            if showMesh, let frame {
                Canvas { ctx, size in
                    let meshes = frame.anchors.compactMap { $0 as? ARMeshAnchor }
                    ctx.stroke(MeshWire.path(meshes, camera: frame.camera, size: size),
                               with: .color(.cyan.opacity(0.55)), lineWidth: 0.7)
                }
            }
            if showDetector, let frame, let snap = guide.detectorSnapshot {
                Canvas { ctx, size in
                    let camera = frame.camera
                    for p in snap.points {
                        let pt = camera.projectPoint(p.world, orientation: .portrait, viewportSize: size)
                        guard pt.x.isFinite, pt.y.isFinite,
                              (0...size.width).contains(pt.x), (0...size.height).contains(pt.y) else { continue }
                        let r: CGFloat = p.kind == .level || p.kind == .reference ? 2.5 : 3.5
                        ctx.fill(Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)),
                                 with: .color(p.kind.color))
                    }
                }
            }
        }
        .frame(width: viewport.width, height: viewport.height)
    }
}

extension DetectorSnapshot.Kind {
    var color: Color {
        switch self {
        case .reference: .blue
        case .level: .green
        case .low: .red
        case .high: .yellow
        case .obstacle: .orange
        }
    }
    var label: String {
        switch self {
        case .reference: "Floor underfoot"
        case .level: "Level floor"
        case .low: "Step down"
        case .high: "Step up"
        case .obstacle: "Obstacle"
        }
    }
}

/// Side view of the floor ahead: what the step decision is made on.
private struct ProfilePanel: View {
    let snapshot: DetectorSnapshot?
    let reading: ReflexLayer.Reading?

    private let maxAhead: Float = 1.3
    private let band: ClosedRange<Float> = -0.30...0.40

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Canvas { ctx, size in draw(ctx, size) }
                .frame(height: 130)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
            numbers
            legend
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .environment(\.colorScheme, .dark)
    }

    private func x(_ ahead: Float, _ w: CGFloat) -> CGFloat { CGFloat(ahead / maxAhead) * w }
    private func y(_ rel: Float, _ h: CGFloat) -> CGFloat {
        let t = (min(band.upperBound, max(band.lowerBound, rel)) - band.lowerBound) / (band.upperBound - band.lowerBound)
        return h - CGFloat(t) * h
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height
        guard let snap = snapshot else {
            ctx.draw(Text("Point the camera at the floor ahead").font(.caption).foregroundStyle(.white),
                     at: CGPoint(x: w / 2, y: h / 2))
            return
        }
        let t = snap.rules
        // Threshold band: inside it the floor counts as level.
        let band = Path(CGRect(x: 0, y: y(t.stepUpRise, h), width: w,
                               height: y(-t.stepDownDrop, h) - y(t.stepUpRise, h)))
        ctx.fill(band, with: .color(.green.opacity(0.12)))
        for (v, c) in [(Float(0), Color.white.opacity(0.6)), (-t.stepDownDrop, .red.opacity(0.7)),
                       (t.stepUpRise, .yellow.opacity(0.7))] {
            var line = Path(); line.move(to: CGPoint(x: 0, y: y(v, h))); line.addLine(to: CGPoint(x: w, y: y(v, h)))
            ctx.stroke(line, with: .color(c), style: StrokeStyle(lineWidth: 1, dash: v == 0 ? [] : [4, 3]))
        }
        // Where the step warning is spoken.
        var warn = Path(); warn.move(to: CGPoint(x: x(snap.warnDistance, w), y: 0))
        warn.addLine(to: CGPoint(x: x(snap.warnDistance, w), y: h))
        ctx.stroke(warn, with: .color(.white.opacity(0.8)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
        ctx.draw(Text("speaks here").font(.system(size: 9)).foregroundStyle(.white.opacity(0.8)),
                 at: CGPoint(x: x(snap.warnDistance, w) + 30, y: 8))

        for p in snap.points where p.ahead <= maxAhead {
            let r: CGFloat = 1.6
            ctx.fill(Path(ellipseIn: CGRect(x: x(p.ahead, w) - r, y: y(p.relative, h) - r, width: 2 * r, height: 2 * r)),
                     with: .color(p.kind.color))
        }
        if let edge = snap.stepDistance {
            var e = Path(); e.move(to: CGPoint(x: x(edge, w), y: 0)); e.addLine(to: CGPoint(x: x(edge, w), y: h))
            ctx.stroke(e, with: .color(.red), lineWidth: 2.5)
            ctx.draw(Text(String(format: "edge %.2f m", edge)).font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.red),
                     at: CGPoint(x: min(w - 40, x(edge, w) + 36), y: h - 10))
        }
        ctx.draw(Text("0 m").font(.system(size: 9)).foregroundStyle(.white.opacity(0.6)), at: CGPoint(x: 10, y: h - 8))
        ctx.draw(Text(String(format: "%.1f m ahead", maxAhead)).font(.system(size: 9)).foregroundStyle(.white.opacity(0.6)),
                 at: CGPoint(x: w - 34, y: h - 8))
    }

    private var numbers: some View {
        let drop = snapshot?.drop
        let threshold = snapshot?.rules.stepDownDrop ?? 0.07
        return HStack(spacing: 10) {
            stat("DROP", drop.map { String(format: "%.3f m", $0) } ?? "—")
            stat("THRESHOLD", String(format: "%.3f m", threshold))
            stat("MARGIN", drop.map { String(format: "%+.3f", threshold - $0) } ?? "—")
            stat("OBSTACLE", snapshot?.obstacle.map { String(format: "%.2f m", $0) } ?? "none")
            stat("TILT", reading.map { "\(Int($0.pitchDegrees))°" } ?? "—")
        }
        .accessibilityElement(children: .combine)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(label).font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(.primary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private var legend: some View {
        HStack(spacing: 10) {
            ForEach([DetectorSnapshot.Kind.reference, .level, .low, .high, .obstacle], id: \.self) { k in
                HStack(spacing: 3) {
                    Circle().fill(k.color).frame(width: 7, height: 7)
                    Text(k.label).font(.system(size: 9, weight: .medium))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// A banner for a moment after a spoken warning, so whoever is watching can
/// match the words to the picture.
private struct WarningFlash: View {
    @EnvironmentObject var guide: GuideController

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { ctx in
            if let w = guide.lastWarning, ctx.date.timeIntervalSince(w.at) < 1.5 {
                Text(w.text)
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20).padding(.vertical, 8)
                    .background(.red, in: RoundedRectangle(cornerRadius: 14))
                    .transition(.opacity)
            }
        }
    }
}

private struct LayerChip: View {
    let title: String
    let color: Color
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 5) {
                Circle().fill(isOn ? color : .gray).frame(width: 9, height: 9)
                Text(title).font(.subheadline.weight(.bold))
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(.black.opacity(isOn ? 0.7 : 0.4), in: Capsule())
            .foregroundStyle(.white)
        }
        .accessibilityLabel("\(title) layer")
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

/// The room mesh as a wireframe over the camera picture, projected the same
/// way as the detector points.
enum MeshWire {
    /// Triangles drawn per refresh; larger scans are thinned evenly.
    static let faceBudget = 6000

    static func path(_ anchors: [ARMeshAnchor], camera: ARCamera, size: CGSize) -> Path {
        var path = Path()
        guard !anchors.isEmpty, size.width > 0, size.height > 0 else { return path }
        let viewProj = camera.projectionMatrix(for: .portrait, viewportSize: size, zNear: 0.05, zFar: 8)
            * camera.viewMatrix(for: .portrait)
        let total = anchors.reduce(0) { $0 + $1.geometry.faces.count }
        let step = max(1, total / faceBudget)
        for anchor in anchors {
            let g = anchor.geometry
            let m = viewProj * anchor.transform
            let verts = g.vertices, faces = g.faces
            let vbase = verts.buffer.contents().advanced(by: verts.offset)
            let fbase = faces.buffer.contents()
            func screen(_ index: Int) -> CGPoint? {
                let v = vbase.advanced(by: verts.stride * index).assumingMemoryBound(to: Float.self)
                let c = m * SIMD4<Float>(v[0], v[1], v[2], 1)
                guard c.w > 0.05 else { return nil }   // behind the camera
                let x = c.x / c.w, y = c.y / c.w
                guard abs(x) < 1.2, abs(y) < 1.2 else { return nil }
                return CGPoint(x: CGFloat((x + 1) / 2) * size.width, y: CGFloat((1 - y) / 2) * size.height)
            }
            func index(_ i: Int) -> Int {
                faces.bytesPerIndex == 2
                    ? Int(fbase.advanced(by: i * 2).assumingMemoryBound(to: UInt16.self).pointee)
                    : Int(fbase.advanced(by: i * 4).assumingMemoryBound(to: UInt32.self).pointee)
            }
            var f = 0
            while f < faces.count {
                let base = f * faces.indexCountPerPrimitive
                if let a = screen(index(base)), let b = screen(index(base + 1)), let c = screen(index(base + 2)) {
                    path.move(to: a); path.addLine(to: b); path.addLine(to: c); path.closeSubpath()
                }
                f += step
            }
        }
        return path
    }
}

/// The live camera picture, cropped and rotated as ARKit would show it, so the
/// mesh and detector points line up with it.
enum CameraImage {
    /// Rendered a little above point size: sharp enough, cheap enough.
    static let scale: CGFloat = 1.5
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func image(for frame: ARFrame, viewport: CGSize) -> CGImage? {
        guard viewport.width > 0, viewport.height > 0 else { return nil }
        let buffer = frame.capturedImage
        let w = CGFloat(CVPixelBufferGetWidth(buffer)), h = CGFloat(CVPixelBufferGetHeight(buffer))
        let size = CGSize(width: viewport.width * scale, height: viewport.height * scale)
        // Same recipe as DepthHeatmap: normalize, flip for portrait, apply the
        // camera's display transform, then scale to the output size.
        let normalize = CGAffineTransform(scaleX: 1 / w, y: 1 / h)
        let flip = CGAffineTransform(scaleX: -1, y: -1).translatedBy(x: -1, y: -1)
        let display = frame.displayTransform(for: .portrait, viewportSize: viewport)
        let toOutput = CGAffineTransform(scaleX: size.width, y: size.height)
        let ci = CIImage(cvPixelBuffer: buffer)
            .transformed(by: normalize.concatenating(flip).concatenating(display).concatenating(toOutput))
            .cropped(to: CGRect(origin: .zero, size: size))
        return context.createCGImage(ci, from: CGRect(origin: .zero, size: size))
    }
}
