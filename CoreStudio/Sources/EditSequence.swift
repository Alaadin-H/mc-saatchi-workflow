import Foundation
import CoreGraphics

enum SequenceFormat: String, Codable, CaseIterable {
    case widescreen16x9 = "16:9 (1920x1080)"
    case vertical9x16 = "9:16 (1080x1920)"
    case square1x1 = "1:1 (1080x1080)"
    case social4x5 = "4:5 (1080x1350)"
    
    var size: CGSize {
        switch self {
        case .widescreen16x9: return CGSize(width: 1920, height: 1080)
        case .vertical9x16: return CGSize(width: 1080, height: 1920)
        case .square1x1: return CGSize(width: 1080, height: 1080)
        case .social4x5: return CGSize(width: 1080, height: 1350)
        }
    }
}

struct EditSequence: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var frameRate: Double
    var width: Int
    var height: Int
    var tracks: [Track]

    init(id: UUID = UUID(), name: String, frameRate: Double = 30.0, format: SequenceFormat = .widescreen16x9, tracks: [Track] = []) {
        self.id = id
        self.name = name
        self.frameRate = frameRate
        self.width = Int(format.size.width)
        self.height = Int(format.size.height)
        self.tracks = tracks.isEmpty ? [
            Track(id: UUID(), name: "Video 1", type: .video),
            Track(id: UUID(), name: "Video 2", type: .video),
            Track(id: UUID(), name: "Audio 1", type: .audio)
        ] : tracks
    }
}

