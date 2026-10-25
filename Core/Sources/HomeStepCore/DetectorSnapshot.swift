import simd

/// A copy of what the detector measured in one frame, for the "See what
/// HomeStep sees" screen. Only made while that screen is open.
///
/// Points are classified with the same thresholds and comparisons the
/// detector uses, so the colours on screen are its own view of the floor.
public struct DetectorSnapshot: Sendable {
    public struct Zone: OptionSet, Sendable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }
        /// The reference strip, just ahead of the stick.
        public static let near = Zone(rawValue: 1 << 0)
        /// The probe strip, out to the warning distance.
        public static let far = Zone(rawValue: 1 << 1)
        /// Within obstacle range, at any height.
        public static let candidate = Zone(rawValue: 1 << 2)
    }

    public enum Kind: Sendable, CaseIterable { case reference, level, low, high, obstacle }

    public struct Sample: Sendable {
        public let world: SIMD3<Float>
        public let ahead: Float
        public let height: Float
        public let zone: Zone

        public init(world: SIMD3<Float>, ahead: Float, height: Float, zone: Zone) {
            self.world = world
            self.ahead = ahead
            self.height = height
            self.zone = zone
        }
    }

    public struct Point: Sendable {
        public let world: SIMD3<Float>
        public let ahead: Float
        /// Height above the reference floor (negative is lower).
        public let relative: Float
        public let kind: Kind
    }

    public struct Rules: Sendable {
        public let stepDownDrop: Float
        public let stepUpRise: Float
        public let obstacleMinHeight: Float
        public let obstacleRange: Float

        public init(stepDownDrop: Float, stepUpRise: Float, obstacleMinHeight: Float, obstacleRange: Float) {
            self.stepDownDrop = stepDownDrop
            self.stepUpRise = stepUpRise
            self.obstacleMinHeight = obstacleMinHeight
            self.obstacleRange = obstacleRange
        }
    }

    public var points: [Point]
    public var reference: Float?
    public var drop: Float?
    public var stepDistance: Float?
    public var obstacle: Float?
    public var warnDistance: Float
    public var rules: Rules

    /// How the detector sees one sample, or nil if it plays no part in any
    /// decision (and so isn't drawn).
    public static func classify(_ s: Sample, reference: Float?, rules: Rules) -> Kind? {
        guard let reference else { return nil }
        if s.zone.contains(.candidate), s.ahead <= rules.obstacleRange,
           s.height > reference + rules.obstacleMinHeight {
            return .obstacle
        }
        if s.zone.contains(.near) { return .reference }
        if s.zone.contains(.far) {
            if s.height < reference - rules.stepDownDrop { return .low }
            if s.height > reference + rules.stepUpRise { return .high }
            return .level
        }
        return nil
    }

    public static func build(samples: [Sample], reference: Float?, drop: Float?, stepDistance: Float?,
                             obstacle: Float?, warnDistance: Float, rules: Rules) -> DetectorSnapshot {
        var points: [Point] = []
        if let reference {
            points.reserveCapacity(samples.count)
            for s in samples {
                guard let kind = classify(s, reference: reference, rules: rules) else { continue }
                points.append(Point(world: s.world, ahead: s.ahead, relative: s.height - reference, kind: kind))
            }
        }
        return DetectorSnapshot(points: points, reference: reference, drop: drop,
                                stepDistance: stepDistance, obstacle: obstacle,
                                warnDistance: warnDistance, rules: rules)
    }
}
