import Combine
import Foundation

/// The user's places, saved on this iPhone only.
///
/// The ARKit thread reads the active place without touching the main actor,
/// so every change also publishes a copy of it into `activeSnapshot`.
@MainActor
public final class PlaceStore: ObservableObject {
    @Published public private(set) var places: [Place] = []
    @Published public var activePlaceID: UUID? {
        didSet { publishSnapshot(); save() }
    }

    public nonisolated let activeSnapshot = LockedBox<Place?>(nil)

    /// A storage problem the user has to hear about. Losing places silently
    /// would mean hazard markers quietly stop working.
    @Published public var problem: String?

    public var activePlace: Place? { places.first { $0.id == activePlaceID } }

    public let fileURL: URL

    private struct File: Codable {
        var version = 1
        var activePlaceID: UUID?
        var places: [Place]
    }

    /// A shared place, as a `.homestep` file.
    private struct Export: Codable {
        var format = "akshi.place"
        var version = 1
        var place: Place
    }

    public init(directory: URL = PlaceStore.defaultDirectory) {
        fileURL = directory.appendingPathComponent("places.json")
        load()
    }

    public nonisolated static var defaultDirectory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: Places

    /// The first place added becomes the one in use.
    @discardableResult
    public func addPlace(named name: String) -> Place {
        let place = Place(name: name)
        places.append(place)
        if activePlaceID == nil { activePlaceID = place.id } else { save() }
        return place
    }

    public func rename(_ id: UUID, to name: String) {
        mutate(id) { $0.name = name }
    }

    /// Deleting the place in use leaves no place in use rather than switching
    /// to another. Every place numbers its markers from 1, so a silent switch
    /// would change what the markers on the walls mean.
    public func delete(_ id: UUID) {
        places.removeAll { $0.id == id }
        if activePlaceID == id { activePlaceID = nil } else { save() }
    }

    // MARK: Landmarks

    public func upsert(_ landmark: Landmark, in placeID: UUID) {
        mutate(placeID) { place in
            if let i = place.landmarks.firstIndex(where: { $0.id == landmark.id }) {
                place.landmarks[i] = landmark
            } else {
                place.landmarks.append(landmark)
            }
            place.landmarks.sort { $0.marker < $1.marker }
        }
    }

    public func deleteLandmark(_ id: UUID, in placeID: UUID) {
        mutate(placeID) { $0.landmarks.removeAll { $0.id == id } }
    }

    // MARK: Sharing

    public func exportData(_ place: Place) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Export(place: place))
    }

    /// Adds a shared place, or the first version's `home_map.json`. It gets new
    /// identities, so importing a file twice gives two copies, and it isn't
    /// switched on: changing places changes what every marker means, so that
    /// stays the user's choice.
    @discardableResult
    public func importPlace(from data: Data) throws -> Place {
        var place: Place
        if let export = try? JSONDecoder().decode(Export.self, from: data) {
            place = export.place
        } else {
            place = try LegacyHomeMap.place(from: data)
        }
        place.id = UUID()
        place.landmarks = Self.renumberingDuplicates(place.landmarks)
        places.append(place)
        if activePlaceID == nil { activePlaceID = place.id } else { save() }
        return place
    }

    /// Adds the sample place, through import so it gets fresh identities.
    @discardableResult
    public func importSample() -> Place {
        (try? importPlace(from: exportData(.sample()))) ?? addPlace(named: "Sample home")
    }

    /// Two landmarks with one number would make one unreachable, so duplicates
    /// get the next free number. Hazards go first, so a printed hazard marker
    /// keeps meaning the hazard.
    private static func renumberingDuplicates(_ landmarks: [Landmark]) -> [Landmark] {
        var used = Set<Int>()
        var result: [Landmark] = []
        let hazardsFirst = landmarks.filter(\.isHazard) + landmarks.filter { !$0.isHazard }
        for var lm in hazardsFirst {
            lm.id = UUID()
            if used.contains(lm.marker) {
                var n = 1
                while used.contains(n) || landmarks.contains(where: { $0.marker == n }) { n += 1 }
                lm.marker = n
            }
            used.insert(lm.marker)
            result.append(lm)
        }
        return result.sorted { $0.marker < $1.marker }
    }

    // MARK: Saving

    private func mutate(_ id: UUID, _ change: (inout Place) -> Void) {
        guard let i = places.firstIndex(where: { $0.id == id }) else { return }
        change(&places[i])
        publishSnapshot()
        save()
    }

    private func publishSnapshot() {
        activeSnapshot.set(activePlace)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            let file = try JSONDecoder().decode(File.self, from: data)
            places = file.places
            activePlaceID = file.activePlaceID ?? places.first?.id
        } catch {
            // Keep the unreadable file instead of overwriting it on the next
            // save: it's the user's work and may be recoverable.
            var backup = fileURL.appendingPathExtension("corrupt")
            if FileManager.default.fileExists(atPath: backup.path) {
                backup = fileURL.appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970))")
            }
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            problem = "HomeStep couldn't read your saved places, so none are loaded. Markers won't be announced until you set up or import a place again."
        }
        publishSnapshot()
    }

    private func save() {
        let file = File(activePlaceID: activePlaceID, places: places)
        do {
            let data = try JSONEncoder().encode(file)
            #if os(iOS)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: fileURL, options: .atomic)
            #endif
        } catch {
            problem = "HomeStep couldn't save your places (\(error.localizedDescription)). Recent changes may be lost."
        }
    }
}
