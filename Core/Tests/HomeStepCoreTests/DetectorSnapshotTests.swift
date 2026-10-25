import XCTest
import simd
@testable import HomeStepCore

final class DetectorSnapshotTests: XCTestCase {
    // The thresholds the detector ships with.
    private let rules = DetectorSnapshot.Rules(stepDownDrop: 0.07, stepUpRise: 0.07,
                                               obstacleMinHeight: 0.25, obstacleRange: 0.90)
    private let floor: Float = -1.0   // reference floor height (world y, metres)

    private func kind(_ zone: DetectorSnapshot.Zone, ahead: Float = 0.6, height: Float) -> DetectorSnapshot.Kind? {
        DetectorSnapshot.classify(DetectorSnapshot.Sample(world: .zero, ahead: ahead, height: height, zone: zone),
                                  reference: floor, rules: rules)
    }

    // REQ-UI-02
    func testNearSliceIsTheReference() {
        XCTAssertEqual(kind([.near], height: floor), .reference)
    }

    // REQ-UI-02
    func testProbeClassesMatchTheDetectorThresholds() {
        XCTAssertEqual(kind([.far], height: floor), .level)
        XCTAssertEqual(kind([.far], height: floor - 0.069), .level, "just inside the band is still floor")
        XCTAssertEqual(kind([.far], height: floor - 0.071), .low, "below the 7 cm step-down threshold")
        XCTAssertEqual(kind([.far], height: floor + 0.071), .high)
    }

    // REQ-UI-02
    func testObstacleWinsOverRaisedFloorWithinRange() {
        XCTAssertEqual(kind([.far, .candidate], ahead: 0.5, height: floor + 0.30), .obstacle)
        XCTAssertEqual(kind([.candidate], ahead: 0.5, height: floor + 0.24), nil,
                       "below obstacle height and not ground: not drawn")
        XCTAssertEqual(kind([.candidate], ahead: 0.95, height: floor + 0.5), nil,
                       "beyond obstacle range: the detector ignores it, so do we")
    }

    // REQ-UI-02
    func testNoReferenceMeansNothingButRawProbe() {
        let s = DetectorSnapshot.Sample(world: .zero, ahead: 0.6, height: -1, zone: [.far])
        XCTAssertNil(DetectorSnapshot.classify(s, reference: nil, rules: rules),
                     "without a reference floor the detector decides nothing; show nothing")
    }

    // REQ-UI-02
    func testProfileMapping() {
        // Each point keeps its height above the reference floor.
        let s = DetectorSnapshot.Sample(world: .zero, ahead: 0.6, height: -1.2, zone: [.far])
        let snap = DetectorSnapshot.build(samples: [s], reference: -1.0, drop: nil, stepDistance: nil,
                                          obstacle: nil, warnDistance: 0.45, rules: rules)
        XCTAssertEqual(snap.points.first?.relative ?? 0, -0.2, accuracy: 1e-5)
    }
}
