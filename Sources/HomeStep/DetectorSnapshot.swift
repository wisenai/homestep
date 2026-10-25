import simd

/// A copy of what the reflex layer measured in one frame, for the "See what
/// HomeStep sees" screen. Only made while that screen is open.
///
/// Points are classified with the same thresholds and comparisons as
/// `ReflexLayer.process`, so the colours on screen are the detector's own view
/// of the floor, not a second guess that could disagree with the warnings.
struct DetectorSnapshot: Sendable {
    struct Zone: OptionSet, Sendable {
        let rawValue: UInt8
        /// The reference strip: the floor just ahead of the stick.
        static let near = Zone(rawValue: 1 << 0)
        /// The probe strip: the floor out to the warning distance.
        static let far = Zone(rawValue: 1 << 1)
        /// Within obstacle range, at any height.
        static let candidate = Zone(rawValue: 1 << 2)
    }

    enum Kind: Sendable { case reference, level, low, high, obstacle }

    struct Sample: Sendable {
        let world: SIMD3<Float>
        let ahead: Float
        let height: Float
        let zone: Zone
    }

    struct Point: Sendable {
        let world: SIMD3<Float>
        let ahead: Float
        /// Height above the reference floor (negative is lower).
        let relative: Float
        let kind: Kind
    }

    struct Rules: Sendable {
        let stepDownDrop: Float
        let stepUpRise: Float
        let obstacleMinHeight: Float
        let obstacleRange: Float
    }

    var points: [Point]
    var reference: Float?
    var drop: Float?
    var stepDistance: Float?
    var obstacle: Float?
    var warnDistance: Float
    var rules: Rules

    /// How the detector sees one sample, or nil if it plays no part in any
    /// decision (and so isn't drawn).
    static func classify(_ s: Sample, reference: Float?, rules: Rules) -> Kind? {
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

    static func relativeHeight(_ height: Float, reference: Float) -> Float {
        height - reference
    }

    static func build(samples: [Sample], reference: Float?, drop: Float?, stepDistance: Float?,
                      obstacle: Float?, warnDistance: Float, rules: Rules) -> DetectorSnapshot {
        var points: [Point] = []
        points.reserveCapacity(samples.count)
        if let reference {
            for s in samples {
                guard let k = classify(s, reference: reference, rules: rules) else { continue }
                points.append(Point(world: s.world, ahead: s.ahead,
                                    relative: relativeHeight(s.height, reference: reference), kind: k))
            }
        }
        return DetectorSnapshot(points: points, reference: reference, drop: drop,
                                stepDistance: stepDistance, obstacle: obstacle,
                                warnDistance: warnDistance, rules: rules)
    }
}
