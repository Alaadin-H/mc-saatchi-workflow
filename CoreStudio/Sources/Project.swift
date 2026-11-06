import Foundation

struct Project: Identifiable, Codable {
    let id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var activeSequenceID: UUID
    var sequences: [EditSequence]
    var mediaAssets: [MediaAsset]

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
        self.createdAt = Date()
        self.updatedAt = Date()
        
        let initialSequence = EditSequence(name: "Main Sequence")
        self.activeSequenceID = initialSequence.id
        self.sequences = [initialSequence]
        self.mediaAssets = []
    }
}

