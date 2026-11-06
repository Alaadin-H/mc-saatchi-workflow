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
    
    var startTime: Double
    var sourceInPoint: Double
    var sourceOutPoint: Double
    
    var opacity: Double
    var transform: ClipTransform

    var duration: Double {
        max(0, sourceOutPoint - sourceInPoint)
    }
    var endTime: Double {
        startTime + duration
    }

    init(id: UUID = UUID(), mediaAssetID: UUID, name: String, startTime: Double, sourceInPoint: Double, sourceOutPoint: Double, opacity: Double = 1.0, transform: ClipTransform = ClipTransform()) {
        self.id = id
        self.mediaAssetID = mediaAssetID
        self.name = name
        self.startTime = startTime
        self.sourceInPoint = sourceInPoint
        self.sourceOutPoint = sourceOutPoint
        self.opacity = opacity
        self.transform = transform
    }
}

