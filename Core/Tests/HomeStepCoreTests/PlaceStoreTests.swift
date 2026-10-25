import XCTest
@testable import HomeStepCore

@MainActor
final class PlaceStoreTests: XCTestCase {
    private var dir: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlaceStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    // REQ-PLACE-01, REQ-PLACE-08
    func testPersistsAcrossLaunches() throws {
        let store = PlaceStore(directory: dir)
        let home = store.addPlace(named: "Home")
        store.upsert(Landmark(marker: 1, name: "Kitchen", kind: .landmark), in: home.id)
        store.upsert(Landmark(marker: 2, name: "Porch", kind: .stepDown), in: home.id)

        let reopened = PlaceStore(directory: dir)
        XCTAssertEqual(reopened.places.count, 1)
        XCTAssertEqual(reopened.activePlaceID, home.id)
        XCTAssertEqual(reopened.activePlace?.landmark(forMarker: 2)?.kind, .stepDown)
        XCTAssertEqual(reopened.activeSnapshot.get()?.landmarks.count, 2,
                       "the ARKit thread must see the restored place")
    }

    // REQ-PLACE-02, REQ-PLACE-08
    func testFirstPlaceBecomesActiveAndSnapshotFollowsEdits() {
        let store = PlaceStore(directory: dir)
        XCTAssertNil(store.activeSnapshot.get())
        let home = store.addPlace(named: "Home")
        XCTAssertEqual(store.activePlaceID, home.id)
        store.upsert(Landmark(marker: 4, name: "Desk", kind: .landmark), in: home.id)
        XCTAssertEqual(store.activeSnapshot.get()?.landmark(forMarker: 4)?.name, "Desk")
    }

    // REQ-PLACE-01
    func testUpsertReplacesExistingLandmark() {
        let store = PlaceStore(directory: dir)
        let home = store.addPlace(named: "Home")
        var lm = Landmark(marker: 1, name: "Kitchen", kind: .landmark)
        store.upsert(lm, in: home.id)
        lm.name = "Kitchen door"
        store.upsert(lm, in: home.id)
        XCTAssertEqual(store.activePlace?.landmarks.map(\.name), ["Kitchen door"])
    }

    // REQ-PLACE-06
    func testCorruptFileIsKeptAndStoreStartsEmpty() throws {
        let file = dir.appendingPathComponent("places.json")
        try Data("{not json".utf8).write(to: file)
        let store = PlaceStore(directory: dir)
        XCTAssertTrue(store.places.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("places.json.corrupt").path),
            "a corrupt file must be preserved, not silently overwritten")
    }

    // REQ-PLACE-03
    func testDeletingActivePlaceClearsSnapshotOrMovesOn() {
        let store = PlaceStore(directory: dir)
        let a = store.addPlace(named: "A")
        let b = store.addPlace(named: "B")
        store.activePlaceID = a.id
        store.delete(a.id)
        // Never silently switch places: the same printed numbers mean different
        // things in another place.
        XCTAssertNil(store.activePlaceID)
        XCTAssertNil(store.activeSnapshot.get())
        store.activePlaceID = b.id
        store.delete(b.id)
        XCTAssertNil(store.activePlaceID)
        XCTAssertNil(store.activeSnapshot.get())
    }

    // REQ-PLACE-04
    func testExportImportRoundTripGetsNewIdentity() throws {
        let store = PlaceStore(directory: dir)
        let home = store.addPlace(named: "Home")
        store.upsert(Landmark(marker: 1, name: "Kitchen", kind: .landmark), in: home.id)
        let data = try store.exportData(XCTUnwrap(store.activePlace))

        let imported = try store.importPlace(from: data)
        XCTAssertNotEqual(imported.id, home.id)
        XCTAssertEqual(imported.landmarks.first?.name, "Kitchen")
        XCTAssertEqual(store.places.count, 2)
    }

    // REQ-PLACE-04
    func testImportsLegacyHomeMap() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "legacy_home_map", withExtension: "json",
                                                    subdirectory: "Fixtures"))
        let store = PlaceStore(directory: dir)
        let place = try store.importPlace(from: Data(contentsOf: url))
        XCTAssertTrue(try XCTUnwrap(place.landmark(forMarker: 0)).isHazard)
    }

    // REQ-PLACE-05
    func testImportRenumbersDuplicatesButHazardsKeepTheirNumber() throws {
        let dup = Place(name: "Dup", landmarks: [
            Landmark(marker: 3, name: "A", kind: .landmark),
            Landmark(marker: 3, name: "B", kind: .stepDown),
        ])
        let store = PlaceStore(directory: dir)
        let imported = try store.importPlace(from: store.exportData(dup))
        let markers = imported.landmarks.map(\.marker)
        XCTAssertEqual(Set(markers).count, 2, "no two landmarks may share a marker")
        XCTAssertEqual(imported.landmark(forMarker: 3)?.name, "B",
                       "the printed #3 must keep meaning the hazard")
    }

    // REQ-PLACE-02
    func testImportDoesNotReplaceTheActivePlace() throws {
        let store = PlaceStore(directory: dir)
        let home = store.addPlace(named: "Home")
        let other = Place(name: "Other", landmarks: [Landmark(marker: 1, name: "X", kind: .landmark)])
        try store.importPlace(from: store.exportData(other))
        XCTAssertEqual(store.activePlaceID, home.id)
    }

    // REQ-PLACE-06
    func testCorruptLoadIsReported() throws {
        try Data("{not json".utf8).write(to: dir.appendingPathComponent("places.json"))
        XCTAssertNotNil(PlaceStore(directory: dir).problem)
    }

    // REQ-PLACE-04
    func testImportRejectsGarbage() {
        let store = PlaceStore(directory: dir)
        XCTAssertThrowsError(try store.importPlace(from: Data("hello".utf8)))
        XCTAssertTrue(store.places.isEmpty)
    }
}
