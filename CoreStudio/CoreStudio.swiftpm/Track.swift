import Foundation

enum TrackType: String, Codable {
    case video
    case audio
}

struct Track: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var type: TrackType
    var isMuted: Bool
    var isLocked: Bool
    var clips: [Clip]

    init(id: UUID = UUID(), name: String, type: TrackType, isMuted: Bool = false, isLocked: Bool = false, clips: [Clip] = []) {
        self.id = id
        self.name = name
        self.type = type
        self.isMuted = isMuted
        self.isLocked = isLocked
        self.clips = clips
    }
}

