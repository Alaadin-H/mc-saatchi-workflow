import Foundation

enum MediaType: String, Codable {
    case video
    case audio
}

struct MediaAsset: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var type: MediaType
    var relativePath: String
    var durationSeconds: Double
    var naturalSizeWidth: Double
    var naturalSizeHeight: Double

    init(id: UUID = UUID(), name: String, type: MediaType, relativePath: String, durationSeconds: Double, naturalSizeWidth: Double = 1920, naturalSizeHeight: Double = 1080) {
        self.id = id
        self.name = name
        self.type = type
        self.relativePath = relativePath
        self.durationSeconds = durationSeconds
        self.naturalSizeWidth = naturalSizeWidth
        self.naturalSizeHeight = naturalSizeHeight
    }
}

