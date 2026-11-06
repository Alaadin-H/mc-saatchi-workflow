import Foundation

struct ClipTransform: Codable, Hashable {
    var positionX: Double
    var positionY: Double
    var scaleX: Double
    var scaleY: Double
    var rotationDegrees: Double

    init(positionX: Double = 0, positionY: Double = 0, scaleX: Double = 1.0, scaleY: Double = 1.0, rotationDegrees: Double = 0) {
        self.positionX = positionX
        self.positionY = positionY
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.rotationDegrees = rotationDegrees
    }
}

struct Clip: Identifiable, Codable, Hashable {
    let id: UUID
    var mediaAssetID: UUID
    var name: String

    /// Where the clip starts on the timeline (seconds).
    var startTime: Double
    /// The span of the media file the clip uses (seconds in the source).
    var sourceInPoint: Double
    var sourceOutPoint: Double

    var opacity: Double
    var transform: ClipTransform

    /// Source seconds played per timeline second. nil means 1x (projects saved before speed existed).
    /// This is the ONLY definition of speed: duration, split and rendering all derive from it.
    var speed: Double?
    /// Keyframes. nil means "not animated" (and keeps older project files loading).
    var animation: ClipAnimation?

    static let speedRange: ClosedRange<Double> = 0.1...16

    var playbackRate: Double { min(max(speed ?? 1, Clip.speedRange.lowerBound), Clip.speedRange.upperBound) }

    /// Length of media consumed.
    var sourceDuration: Double { max(0, sourceOutPoint - sourceInPoint) }
    /// Length on the timeline (after speed).
    var duration: Double { sourceDuration / playbackRate }
    var endTime: Double { startTime + duration }

    init(id: UUID = UUID(), mediaAssetID: UUID, name: String, startTime: Double, sourceInPoint: Double, sourceOutPoint: Double, opacity: Double = 1.0, transform: ClipTransform = ClipTransform(), speed: Double? = nil, animation: ClipAnimation? = nil) {
        self.id = id
        self.mediaAssetID = mediaAssetID
        self.name = name
        self.startTime = startTime
        self.sourceInPoint = sourceInPoint
        self.sourceOutPoint = sourceOutPoint
        self.opacity = opacity
        self.transform = transform
        self.speed = speed
        self.animation = animation
    }
}

// MARK: - Animatable properties

extension Clip {
    /// 0 at the clip's first frame, 1 at its last.
    func fraction(atTimeline t: Double) -> Double {
        guard duration > 0 else { return 0 }
        return min(max((t - startTime) / duration, 0), 1)
    }

    func isAnimated(_ property: AnimatableProperty) -> Bool {
        !(animation?.keys(for: property).isEmpty ?? true)
    }

    /// The static (un-animated) value of a property.
    func baseValue(_ property: AnimatableProperty) -> Double {
        switch property {
        case .scale: return transform.scaleX
        case .positionX: return transform.positionX
        case .positionY: return transform.positionY
        case .rotation: return transform.rotationDegrees
        case .opacity: return opacity
        }
    }

    mutating func setBaseValue(_ property: AnimatableProperty, _ value: Double) {
        let v = property.clamp(value)
        switch property {
        case .scale: transform.scaleX = v; transform.scaleY = v
        case .positionX: transform.positionX = v
        case .positionY: transform.positionY = v
        case .rotation: transform.rotationDegrees = v
        case .opacity: opacity = v
        }
    }

    /// The value actually shown at timeline time `t`: the keyframes if the property has any, else the base value.
    func value(of property: AnimatableProperty, atTimeline t: Double) -> Double {
        animation?.value(of: property, atFraction: fraction(atTimeline: t)) ?? baseValue(property)
    }
}
