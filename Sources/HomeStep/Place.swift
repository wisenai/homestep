import Foundation

/// A spot with a printed marker taped about a stride before it.
///
/// Hazard kinds are spoken as warnings, so a step tagged here is caught twice:
/// by its marker and by the LiDAR detector, which needs no marker.
struct Landmark: Codable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case landmark, stepDown, stepUp, stairs, hazard

        var isHazard: Bool { self != .landmark }

        /// Shown in the editor's type picker.
        var title: String {
            switch self {
            case .landmark: "Landmark"
            case .stepDown: "Step down"
            case .stepUp: "Step up"
            case .stairs: "Stairs"
            case .hazard: "Other hazard"
            }
        }

        /// Said before the name, and before a custom cue that doesn't already
        /// say what the hazard is.
        fileprivate var spokenPrefix: String? {
            switch self {
            case .landmark: nil
            case .stepDown: "Step down."
            case .stepUp: "Step up."
            case .stairs: "Stairs."
            case .hazard: "Caution."
            }
        }
    }

    var id = UUID()
    /// The number encoded in the printed QR code.
    var marker: Int
    var name: String
    /// What to say when the marker is read. Empty means "build it from the name and kind".
    var cue: String = ""
    var kind: Kind
    var note: String = ""

    var isHazard: Bool { kind.isHazard }

    var spokenText: String {
        let custom = cue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            // A warning must still say what it is: someone typing just "Living
            // room" for a step down mustn't lose the words "Step down".
            guard let prefix = kind.spokenPrefix else { return custom }
            let keyword = prefix.dropLast().lowercased()   // "step down", "stairs", …
            return custom.lowercased().contains(keyword) ? custom : "\(prefix) \(custom)"
        }
        let label = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let sentence = label.isEmpty ? "" : (label.hasSuffix(".") ? label : label + ".")
        return [kind.spokenPrefix, sentence.isEmpty ? nil : sentence]
            .compactMap { $0 }.joined(separator: " ")
    }
}

/// A home, office or any indoor place someone knows and has marked up.
struct Place: Codable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var landmarks: [Landmark] = []

    func landmark(forMarker marker: Int) -> Landmark? {
        landmarks.first { $0.marker == marker }
    }

    /// The lowest unused marker number, from 1, so deleted numbers are reused
    /// before the printed sheet grows.
    var nextMarkerNumber: Int {
        let used = Set(landmarks.map(\.marker))
        var n = 1
        while used.contains(n) { n += 1 }
        return n
    }
}

/// What a printed marker's QR code contains.
///
/// Markers encode `akshi:<n>`, so another QR code in view, like a menu or a
/// Wi-Fi code, is never mistaken for one. A bare number also works, for the
/// first markers we printed.
enum MarkerPayload {
    static let prefix = "akshi:"
    /// Keeps a mistyped or hostile payload from being treated as a real marker.
    static let maxMarker = 9999

    static func encode(_ marker: Int) -> String { prefix + String(marker) }

    static func decode(_ payload: String) -> Int? {
        var body = Substring(payload)
        if payload.lowercased().hasPrefix(prefix) { body = body.dropFirst(prefix.count) }
        guard !body.isEmpty, body.allSatisfy(\.isASCII), body.allSatisfy(\.isNumber),
              let n = Int(body), n <= maxMarker else { return nil }
        return n
    }
}

/// Converts the first version's single-house `home_map.json` into a Place, so
/// that setup can be imported rather than typed in again.
enum LegacyHomeMap {
    private struct Node: Decodable {
        let say: String
        let hazard: Bool
        let room: String
        let note: String?
    }
    private struct Map: Decodable {
        let home: String
        let nodes: [String: Node]
    }

    static func place(from data: Data) throws -> Place {
        let map = try JSONDecoder().decode(Map.self, from: data)
        let landmarks = map.nodes.compactMap { key, node -> Landmark? in
            guard let marker = MarkerPayload.decode(key) else { return nil }
            return Landmark(marker: marker,
                            name: node.room.replacingOccurrences(of: "_", with: " ").capitalized,
                            cue: node.say,
                            kind: kind(for: node),
                            note: node.note ?? "")
        }
        return Place(name: map.home, landmarks: landmarks.sorted { $0.marker < $1.marker })
    }

    private static func kind(for node: Node) -> Landmark.Kind {
        guard node.hazard else { return .landmark }
        let s = node.say.lowercased()
        if s.contains("step down") { return .stepDown }
        if s.contains("step up") { return .stepUp }
        if s.contains("stair") { return .stairs }
        return .hazard
    }
}
