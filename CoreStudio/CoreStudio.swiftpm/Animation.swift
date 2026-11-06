import Foundation

/// Keyframe animation for a clip.
///
/// Design (inspired by how Concat models it, written from scratch here):
/// - A key's position `at` is a FRACTION of the clip's timeline length (0...1),
///   so trimming or changing speed keeps the motion in proportion.
/// - Between two keys the value follows a CSS-style cubic-bezier timing curve
///   stored on the later key (how that key is approached).
/// - Values are absolute (like Premiere): once a property has keys,
///   the keys decide its value and the clip's static value is ignored.

enum AnimatableProperty: String, Codable, CaseIterable, Hashable {
    case scale, positionX, positionY, rotation, opacity

    var title: String {
        switch self {
        case .scale: return "Scale"
        case .positionX: return "Position X"
        case .positionY: return "Position Y"
        case .rotation: return "Rotation"
        case .opacity: return "Opacity"
        }
    }

    func clamp(_ v: Double) -> Double {
        switch self {
        case .scale: return min(max(v, 0.01), 20)
        case .opacity: return min(max(v, 0), 1)
        default: return v
        }
    }
}

/// A CSS timing function: cubic bezier from (0,0) to (1,1) through two control points.
struct CubicEase: Codable, Hashable {
    var x1: Double
    var y1: Double
    var x2: Double
    var y2: Double

    init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        self.x1 = min(max(x1, 0), 1)
        self.y1 = y1
        self.x2 = min(max(x2, 0), 1)
        self.y2 = y2
    }

    static let linear = CubicEase(0, 0, 1, 1)
    static let easeIn = CubicEase(0.42, 0, 1, 1)
    static let easeOut = CubicEase(0, 0, 0.58, 1)
    static let easeInOut = CubicEase(0.42, 0, 0.58, 1)

    static func named(_ name: String) -> CubicEase? {
        switch name.lowercased() {
        case "linear": return .linear
        case "easein", "ease-in": return .easeIn
        case "easeout", "ease-out": return .easeOut
        case "easeinout", "ease-in-out", "ease": return .easeInOut
        default: return nil
        }
    }

    /// Progress (y) for a given time fraction (x). x(t) is monotone because x1, x2 are in 0...1,
    /// so a bisection always finds t.
    func progress(at x: Double) -> Double {
        let x = min(max(x, 0), 1)
        if self == .linear { return x }
        func bez(_ t: Double, _ p1: Double, _ p2: Double) -> Double {
            let u = 1 - t
            return 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t
        }
        var lo = 0.0, hi = 1.0, t = x
        for _ in 0..<40 {
            let v = bez(t, x1, x2)
            if abs(v - x) < 1e-7 { break }
            if v < x { lo = t } else { hi = t }
            t = (lo + hi) / 2
        }
        return bez(t, y1, y2)
    }
}

struct Keyframe: Codable, Hashable {
    /// Fraction of the clip's timeline length, 0...1.
    var at: Double
    var value: Double
    /// How this key is approached from the previous one.
    var ease: CubicEase
}

struct ClipAnimation: Codable, Hashable {
    /// Keys per property name, each list sorted by `at`.
    var tracks: [String: [Keyframe]] = [:]

    var isEmpty: Bool { tracks.values.allSatisfy { $0.isEmpty } }

    func keys(for property: AnimatableProperty) -> [Keyframe] {
        tracks[property.rawValue] ?? []
    }

    /// nil when the property has no keys.
    func value(of property: AnimatableProperty, atFraction f: Double) -> Double? {
        let keys = self.keys(for: property)
        guard let first = keys.first, let last = keys.last else { return nil }
        let f = min(max(f, 0), 1)
        if f <= first.at { return first.value }
        if f >= last.at { return last.value }
        for i in 1..<keys.count where f <= keys[i].at {
            let a = keys[i - 1], b = keys[i]
            let span = b.at - a.at
            guard span > 0 else { return b.value }
            return a.value + (b.value - a.value) * b.ease.progress(at: (f - a.at) / span)
        }
        return last.value
    }

    /// Adds a key, replacing one already at (almost) the same place.
    mutating func setKey(_ property: AnimatableProperty, at: Double, value: Double, ease: CubicEase = .easeInOut) {
        let at = min(max(at, 0), 1)
        var keys = self.keys(for: property)
        keys.removeAll { abs($0.at - at) < 0.0005 }
        keys.append(Keyframe(at: at, value: property.clamp(value), ease: ease))
        keys.sort { $0.at < $1.at }
        tracks[property.rawValue] = keys
    }

    mutating func clear(_ property: AnimatableProperty) {
        tracks[property.rawValue] = nil
    }

    /// The part of this animation between fractions `from` and `to`, re-scaled to 0...1.
    /// Used when a clip is split, so each half keeps the motion it showed before.
    func slice(from: Double, to: Double) -> ClipAnimation {
        guard to > from else { return ClipAnimation() }
        var result = ClipAnimation()
        for property in AnimatableProperty.allCases {
            let keys = self.keys(for: property)
            guard !keys.isEmpty,
                  let startValue = value(of: property, atFraction: from),
                  let endValue = value(of: property, atFraction: to) else { continue }
            var newKeys = [Keyframe(at: 0, value: startValue, ease: .linear)]
            for k in keys where k.at > from + 0.0005 && k.at < to - 0.0005 {
                newKeys.append(Keyframe(at: (k.at - from) / (to - from), value: k.value, ease: k.ease))
            }
            let lastEase = keys.first(where: { $0.at >= to })?.ease ?? .linear
            newKeys.append(Keyframe(at: 1, value: endValue, ease: lastEase))
            result.tracks[property.rawValue] = newKeys
        }
        return result
    }
}
