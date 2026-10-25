import XCTest
import simd
@testable import HomeStepCore

/// Settings, the test-walk recorder, the camera maths and the sample place.
@MainActor
final class StorageTests: XCTestCase {
    private var dir: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("HomeStepTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func freshDefaults() -> UserDefaults {
        let name = "HomeStepTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    // MARK: Settings

    // REQ-SET-01
    func testDefaults() {
        let s = AppSettings(defaults: freshDefaults())
        XCTAssertTrue(s.speech)
        XCTAssertTrue(s.tones)
        XCTAssertTrue(s.haptics)
        XCTAssertEqual(s.speechRate, 0.5)
        XCTAssertFalse(s.developerMode, "recording is off unless asked for")
        XCTAssertFalse(s.onboardingDone, "first launch shows the safety page")
    }

    // REQ-SET-01
    func testSettingsAreKept() {
        let d = freshDefaults()
        let s = AppSettings(defaults: d)
        s.tones = false
        s.speechRate = 0.6
        let again = AppSettings(defaults: d)
        XCTAssertFalse(again.tones)
        XCTAssertEqual(again.speechRate, 0.6, accuracy: 1e-6)
        XCTAssertEqual(again.announcerSettings, .init(speech: true, tones: false, haptics: true, rate: 0.6))
    }

    // MARK: Recorder

    // REQ-LOG-01
    func testRecorderWritesOneJSONObjectPerLine() throws {
        let log = SessionLogger(directory: dir)
        log.log("reading", ["drop": 0.01])
        XCTAssertNil(log.url, "nothing is written unless a recording was started")

        log.begin(device: "iPhone14,3")
        log.log("start", ["warnDistance": 0.45])
        log.log("event", ["event": "step:Step down. d=0.40 spoken=true"])
        log.log("mark", ["label": "wrong"])
        log.close()

        let rows = try String(contentsOf: XCTUnwrap(log.url)).split(separator: "\n").map {
            try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any]
        }
        XCTAssertEqual(rows.map { $0["kind"] as? String }, ["session", "start", "event", "mark"])
        XCTAssertEqual(rows[0]["device"] as? String, "iPhone14,3")
        XCTAssertTrue(rows.allSatisfy { $0["t"] is Double })
        XCTAssertEqual(log.sessionCount(), 1)
    }

    // REQ-LOG-03
    func testRecorderStopsAtItsSizeLimit() throws {
        let log = SessionLogger(directory: dir, maxBytes: 2_000)
        log.begin()
        for i in 0..<500 {
            log.log("reading", ["i": i])
            log.flush()
        }
        log.close()
        let size = try FileManager.default.attributesOfItem(atPath: XCTUnwrap(log.url).path)[.size] as! Int
        XCTAssertLessThan(size, 2_100)
    }

    // MARK: Camera maths

    // REQ-STEP-01
    func testCentrePixelLandsStraightAhead() {
        let pose = Rig.pose(pitch: 0, roll: 0)
        let p = pose.worldPoint(u: Rig.intrinsics.cx, v: Rig.intrinsics.cy, depth: 2, intrinsics: Rig.intrinsics)
        XCTAssertEqual(p.x, 0, accuracy: 1e-5)
        XCTAssertEqual(p.y, 0, accuracy: 1e-5)
        XCTAssertEqual(p.z, -2, accuracy: 1e-5)
    }

    // REQ-STEP-01
    func testLowerPixelsLandLower() {
        // Image rows count downward; a row below the centre must be below the
        // camera. Getting this sign wrong turns every step upside down.
        let pose = Rig.pose(pitch: 0, roll: 0)
        let p = pose.worldPoint(u: Rig.intrinsics.cx, v: Rig.intrinsics.cy + 50, depth: 2, intrinsics: Rig.intrinsics)
        XCTAssertLessThan(p.y, -0.1)
    }

    // REQ-STEP-01
    func testIntrinsicsScaleToTheDepthMap() {
        let colour = CameraIntrinsics(fx: 1450, fy: 1450, cx: 960, cy: 720)
        let k = colour.scaled(fromImage: CGSize(width: 1920, height: 1440), toDepth: 256, 192)
        XCTAssertEqual(k?.fx ?? 0, 193.33, accuracy: 0.01)
        XCTAssertEqual(k?.cx ?? 0, 128, accuracy: 1e-4)
        XCTAssertEqual(k?.cy ?? 0, 96, accuracy: 1e-4)
        XCTAssertNil(colour.scaled(fromImage: .zero, toDepth: 256, 192))
    }

    // REQ-STEP-01
    func testPitchIsReported() {
        XCTAssertEqual(Rig.pose(pitch: 45).pitchDown, 45, accuracy: 0.01)
        XCTAssertEqual(Rig.pose(pitch: 30, yaw: 20, roll: 0).pitchDown, 30, accuracy: 0.01)
    }

    // MARK: Sample place

    // REQ-PLACE-07
    func testSamplePlaceCoversBothSidesOfAStep() {
        let sample = Place.sample()
        XCTAssertEqual(sample.landmarks.map(\.marker), [1, 2, 3, 4])
        XCTAssertEqual(sample.landmarks.filter(\.isHazard).map(\.kind), [.stepDown, .stepUp])
    }

    // REQ-PLACE-07
    func testSampleImportsAsANewPlace() {
        let store = PlaceStore(directory: dir)
        let a = store.importSample()
        let b = store.importSample()
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertEqual(store.places.count, 2)
        XCTAssertEqual(store.activePlaceID, a.id)
    }
}
