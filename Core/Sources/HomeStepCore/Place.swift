import Foundation

/// A spot with a printed marker taped about a stride before it.
public struct Landmark: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case landmark, stepDown, stepUp, stairs, hazard

        /// Every kind but a plain landmark interrupts as a warning.
        public var isHazard: Bool { self != .landmark }

        public var title: String {
            switch self {
            case .landmark: return "Landmark"
            case .stepDown: return "Step down"
            case .stepUp: return "Step up"
            case .stairs: return "Stairs"
            case .hazard: return "Other hazard"
            }
        }

        /// Said before the name, so a warning always says what it is warning about.
        var spokenPrefix: String? {
            switch self {
            case .landmark: return nil
            case .stepDown: return "Step down."
            case .stepUp: return "Step up."
            case .stairs: return "Stairs."
            case .hazard: return "Caution."
            }
        }
    }

    public var id = UUID()
    /// The number in the printed code.
    public var marker: Int
    public var name: String
    /// What to say. Empty means "build it from the name and kind".
    public var cue: String = ""
    public var kind: Kind
    /// For whoever tapes the marker up.
    public var note: String = ""

    public init(id: UUID = UUID(), marker: Int, name: String, cue: String = "", kind: Kind, note: String = "") {
        self.id = id
        self.marker = marker
        self.name = name
        self.cue = cue
        self.kind = kind
        self.note = note
    }

    public var isHazard: Bool { kind.isHazard }

    /// What HomeStep says when it reads this marker.
    public var spokenText: String {
        let custom = cue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            // Someone typing just "Living room" for a step down must not lose
            // the words that make it a warning.
            guard let prefix = kind.spokenPrefix else { return custom }
            let keyword = prefix.dropLast().lowercased()
            return custom.lowercased().contains(keyword) ? custom : "\(prefix) \(custom)"
        }
        let label = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let sentence = label.isEmpty ? nil : (label.hasSuffix(".") ? label : label + ".")
        return [kind.spokenPrefix, sentence].compactMap { $0 }.joined(separator: " ")
    }
}

/// A home, office or any indoor place someone knows and has marked up.
public struct Place: Codable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var landmarks: [Landmark] = []

    public init(id: UUID = UUID(), name: String, landmarks: [Landmark] = []) {
        self.id = id
        self.name = name
        self.landmarks = landmarks
    }

    public func landmark(forMarker marker: Int) -> Landmark? {
        landmarks.first { $0.marker == marker }
    }

    /// The lowest unused marker number, from 1, so deleted numbers are reused
    /// before the printed sheet grows.
    public var nextMarkerNumber: Int {
        let used = Set(landmarks.map(\.marker))
        var n = 1
        while used.contains(n) { n += 1 }
        return n
    }

    /// Four markers anyone can print to hear HomeStep work straight away,
    /// including both sides of one step.
    public static func sample() -> Place {
        Place(name: "Sample home", landmarks: [
            Landmark(marker: 1, name: "Front door", kind: .landmark,
                     note: "Inside, on the door frame at knee height."),
            Landmark(marker: 2, name: "Kitchen", kind: .landmark,
                     note: "On the kitchen door frame."),
            Landmark(marker: 3, name: "Living room", kind: .stepDown,
                     note: "One stride before the step, facing the hallway."),
            Landmark(marker: 4, name: "Hallway", cue: "Step up into the hallway.", kind: .stepUp,
                     note: "Same step, facing the living room."),
        ])
    }
}

/// What a printed marker's QR code holds.
///
/// Markers encode `akshi:<n>`, so another QR code in view, like a menu or a
/// Wi-Fi code, is never mistaken for one. A bare number also works, for the
/// first markers we printed.
public enum MarkerPayload {
    public static let prefix = "akshi:"
    /// Keeps a mistyped or hostile payload from being taken for a real marker.
    public static let maxMarker = 9999

    public static func encode(_ marker: Int) -> String { prefix + String(marker) }

    public static func decode(_ payload: String) -> Int? {
        var body = Substring(payload)
        if payload.lowercased().hasPrefix(prefix) { body = body.dropFirst(prefix.count) }
        guard !body.isEmpty, body.allSatisfy(\.isASCII), body.allSatisfy(\.isNumber),
              let n = Int(body), n <= maxMarker else { return nil }
        return n
    }
}

/// Converts the first version's single-house `home_map.json` into a Place, so
/// that setup can be imported rather than typed in again.
public enum LegacyHomeMap {
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

    public static func place(from data: Data) throws -> Place {
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
