import XCTest
@testable import HomeStepCore

final class PlaceTests: XCTestCase {

    // MARK: Marker payload

    // REQ-MARK-01
    func testDecodesHomeStepPayload() {
        XCTAssertEqual(MarkerPayload.decode("akshi:7"), 7)
        XCTAssertEqual(MarkerPayload.decode("AKSHI:12"), 12)
    }

    // REQ-MARK-01
    func testDecodesBareIntegerFromOriginalMarkers() {
        // The first markers we printed encode bare numbers.
        XCTAssertEqual(MarkerPayload.decode("3"), 3)
        XCTAssertEqual(MarkerPayload.decode("0"), 0)
    }

    // REQ-MARK-01
    func testIgnoresUnrelatedQRCodes() {
        for junk in ["https://example.com", "12abc", "akshi:", "akshi:-1", "-4", "",
                     "WIFI:S:home;T:WPA;P:pw;;", "akshi:99999999999999999999"] {
            XCTAssertNil(MarkerPayload.decode(junk), junk)
        }
    }

    // REQ-MARK-01
    func testEncodeRoundTrips() {
        XCTAssertEqual(MarkerPayload.encode(5), "akshi:5")
        XCTAssertEqual(MarkerPayload.decode(MarkerPayload.encode(42)), 42)
    }

    // MARK: Place

    // REQ-MARK-02, REQ-MARK-06
    func testLookupAndNextMarkerNumberFillsGaps() {
        var place = Place(name: "Home")
        XCTAssertEqual(place.nextMarkerNumber, 1)
        place.landmarks = [
            Landmark(marker: 1, name: "Kitchen", kind: .landmark),
            Landmark(marker: 3, name: "Bath", kind: .landmark),
        ]
        XCTAssertEqual(place.nextMarkerNumber, 2)
        XCTAssertEqual(place.landmark(forMarker: 3)?.name, "Bath")
        XCTAssertNil(place.landmark(forMarker: 2))
    }

    // REQ-MARK-03
    func testSpokenTextUsesCueOrKindDefault() {
        let custom = Landmark(marker: 1, name: "Living room", cue: "Mind the step", kind: .stepDown)
        XCTAssertEqual(custom.spokenText, "Step down. Mind the step")
        let plain = Landmark(marker: 2, name: "Living room", kind: .stepDown)
        XCTAssertEqual(plain.spokenText, "Step down. Living room.")
        let door = Landmark(marker: 3, name: "Front door", kind: .landmark)
        XCTAssertEqual(door.spokenText, "Front door.")
    }

    // REQ-MARK-03
    func testCustomCueOnHazardKeepsTheHazardWords() {
        // A helper typing just a room name must not strip "Step down" from a step.
        let lm = Landmark(marker: 1, name: "Living room", cue: "Living room", kind: .stepDown)
        XCTAssertEqual(lm.spokenText, "Step down. Living room")
        let phrased = Landmark(marker: 2, name: "x", cue: "One step down into the den.", kind: .stepDown)
        XCTAssertEqual(phrased.spokenText, "One step down into the den.")
        let stairs = Landmark(marker: 3, name: "x", cue: "Basement", kind: .stairs)
        XCTAssertEqual(stairs.spokenText, "Stairs. Basement")
    }

    // REQ-MARK-04
    func testHazardKinds() {
        XCTAssertFalse(Landmark.Kind.landmark.isHazard)
        for k in [Landmark.Kind.stepDown, .stepUp, .stairs, .hazard] {
            XCTAssertTrue(k.isHazard, k.rawValue)
        }
    }

    // MARK: Importing the first version's house map

    // REQ-PLACE-04
    func testLegacyHomeMapConverts() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "legacy_home_map", withExtension: "json",
                                                    subdirectory: "Fixtures"))
        let place = try LegacyHomeMap.place(from: Data(contentsOf: url))
        XCTAssertEqual(place.name, "Grandpa's house")
        let step = try XCTUnwrap(place.landmark(forMarker: 0))
        XCTAssertEqual(step.kind, .stepDown)
        XCTAssertTrue(step.isHazard, "Marker 0 (the sunken step) must stay a hazard")
        XCTAssertEqual(step.spokenText, "One step down into the living room.")
        XCTAssertEqual(place.landmark(forMarker: 1)?.kind, .stepUp)
        XCTAssertEqual(place.landmark(forMarker: 2)?.kind, .landmark)
        XCTAssertEqual(place.landmarks.count, 6)
    }
}
