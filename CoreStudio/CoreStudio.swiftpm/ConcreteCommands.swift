import Foundation

extension CommandRegistry {
    func registerStandardCommands() {
        
        register(CommandDefinition(
            name: "getProjectState",
            description: "Returns a compact JSON summary of the timeline layout, tracks, clips, and media bin. Use this to read the sequence state.",
            parameters: [],
            factory: { _ in GetProjectStateCommand() }
        ))
        
        register(CommandDefinition(
            name: "importMedia",
            description: "Registers a copied media file into the project's media bin.",
            parameters: [
                ParameterSchema(name: "id", type: "string", description: "UUID", isRequired: true),
                ParameterSchema(name: "name", type: "string", description: "File name", isRequired: true),
                ParameterSchema(name: "type", type: "string", description: "'video' or 'audio'", isRequired: true),
                ParameterSchema(name: "relativePath", type: "string", description: "Local path", isRequired: true),
                ParameterSchema(name: "durationSeconds", type: "number", description: "Duration in seconds", isRequired: true),
                ParameterSchema(name: "width", type: "number", description: "Width", isRequired: true),
                ParameterSchema(name: "height", type: "number", description: "Height", isRequired: true)
            ],
            factory: { args in
                guard let idStr = args["id"] as? String, let id = UUID(uuidString: idStr),
                      let name = args["name"] as? String,
                      let typeStr = args["type"] as? String, let type = MediaType(rawValue: typeStr),
                      let path = args["relativePath"] as? String,
                      let dur = args["durationSeconds"] as? Double,
                      let w = args["width"] as? Double, let h = args["height"] as? Double else {
                    throw EditorError.general("Invalid importMedia arguments")
                }
                let asset = MediaAsset(id: id, name: name, type: type, relativePath: path, durationSeconds: dur, naturalSizeWidth: w, naturalSizeHeight: h)
                return ImportMediaCommand(asset: asset)
            }
        ))
        
        register(CommandDefinition(
            name: "setSequenceFormat",
            description: "Updates the project sequence resolution (e.g. 1920x1080 or 1080x1920).",
            parameters: [
                ParameterSchema(name: "width", type: "number", description: "Sequence width", isRequired: true),
                ParameterSchema(name: "height", type: "number", description: "Sequence height", isRequired: true)
            ],
            factory: { args in
                guard let w = args["width"] as? Double, let h = args["height"] as? Double else {
                    throw EditorError.general("Invalid setSequenceFormat arguments")
                }
                return SetSequenceFormatCommand(width: Int(w), height: Int(h))
            }
        ))

        register(CommandDefinition(
            name: "addClipToTimeline",
            description: "Adds a media asset to the timeline as a clip.",
            parameters: [
                ParameterSchema(name: "mediaAssetID", type: "string", description: "UUID of the media asset", isRequired: true),
                ParameterSchema(name: "trackID", type: "string", description: "UUID of the track", isRequired: true),
                ParameterSchema(name: "startTime", type: "number", description: "Start time on timeline in seconds", isRequired: true)
            ],
            factory: { args in
                guard let assetIDStr = args["mediaAssetID"] as? String, let assetID = UUID(uuidString: assetIDStr),
                      let trackIDStr = args["trackID"] as? String, let trackID = UUID(uuidString: trackIDStr),
                      let startTime = args["startTime"] as? Double else {
                    throw EditorError.general("Invalid addClipToTimeline arguments")
                }
                return AddClipToTimelineCommand(mediaAssetID: assetID, trackID: trackID, startTime: startTime)
            }
        ))
        
        register(CommandDefinition(
            name: "moveClip",
            description: "Moves a clip to a new time and optionally a new track.",
            parameters: [
                ParameterSchema(name: "clipID", type: "string", description: "UUID of the clip", isRequired: true),
                ParameterSchema(name: "newStartTime", type: "number", description: "New timeline start position", isRequired: true),
                ParameterSchema(name: "newTrackID", type: "string", description: "UUID of new track (optional)", isRequired: false)
            ],
            factory: { args in
                guard let clipIDStr = args["clipID"] as? String, let clipID = UUID(uuidString: clipIDStr),
                      let newTime = args["newStartTime"] as? Double else {
                    throw EditorError.general("Invalid moveClip arguments")
                }
                let trackIDStr = args["newTrackID"] as? String
                let trackID = trackIDStr != nil ? UUID(uuidString: trackIDStr!) : nil
                return MoveClipCommand(clipID: clipID, newStartTime: newTime, newTrackID: trackID)
            }
        ))

        register(CommandDefinition(
            name: "trimClip",
            description: "Trims a clip's source in/out points and its timeline start position.",
            parameters: [
                ParameterSchema(name: "clipID", type: "string", description: "UUID of the clip", isRequired: true),
                ParameterSchema(name: "newSourceIn", type: "number", description: "New source in-point seconds", isRequired: false),
                ParameterSchema(name: "newSourceOut", type: "number", description: "New source out-point seconds", isRequired: false),
                ParameterSchema(name: "newStartTime", type: "number", description: "New timeline start seconds", isRequired: false)
            ],
            factory: { args in
                guard let clipIDStr = args["clipID"] as? String, let clipID = UUID(uuidString: clipIDStr) else {
                    throw EditorError.general("Invalid trimClip arguments")
                }
                return TrimClipCommand(clipID: clipID,
                                       newSourceIn: args["newSourceIn"] as? Double,
                                       newSourceOut: args["newSourceOut"] as? Double,
                                       newStartTime: args["newStartTime"] as? Double)
            }
        ))
        
        register(CommandDefinition(
            name: "setClipOpacity",
            description: "Sets the opacity of a clip.",
            parameters: [
                ParameterSchema(name: "clipID", type: "string", description: "UUID of the clip", isRequired: true),
                ParameterSchema(name: "opacity", type: "number", description: "Opacity between 0 and 1", isRequired: true)
            ],
            factory: { args in
                guard let clipIDStr = args["clipID"] as? String, let clipID = UUID(uuidString: clipIDStr),
                      let opacity = args["opacity"] as? Double else {
                    throw EditorError.general("Invalid setClipOpacity arguments")
                }
                return SetClipOpacityCommand(clipID: clipID, opacity: opacity)
            }
        ))
        
        register(CommandDefinition(
            name: "setClipTransform",
            description: "Updates spatial properties of a clip. Omit optional parameters to leave them unchanged.",
            parameters: [
                ParameterSchema(name: "clipID", type: "string", description: "UUID of the clip", isRequired: true),
                ParameterSchema(name: "positionX", type: "number", description: "X offset from center", isRequired: false),
                ParameterSchema(name: "positionY", type: "number", description: "Y offset from center", isRequired: false),
                ParameterSchema(name: "scale", type: "number", description: "Uniform scale multiplier", isRequired: false),
                ParameterSchema(name: "rotation", type: "number", description: "Rotation in degrees", isRequired: false)
            ],
            factory: { args in
                guard let clipIDStr = args["clipID"] as? String, let clipID = UUID(uuidString: clipIDStr) else {
                    throw EditorError.general("Invalid setClipTransform arguments")
                }
                return SetClipTransformCommand(clipID: clipID,
                                               posX: args["positionX"] as? Double,
                                               posY: args["positionY"] as? Double,
                                               scale: args["scale"] as? Double,
                                               rotation: args["rotation"] as? Double)
            }
        ))
        
        register(CommandDefinition(
            name: "splitClipAtTime",
            description: "Splits a clip into two at a specific timeline time.",
            parameters: [
                ParameterSchema(name: "clipID", type: "string", description: "UUID of the clip", isRequired: true),
                ParameterSchema(name: "splitTime", type: "number", description: "Timeline time to split at", isRequired: true)
            ],
            factory: { args in
                guard let clipIDStr = args["clipID"] as? String, let clipID = UUID(uuidString: clipIDStr),
                      let splitTime = args["splitTime"] as? Double else {
                    throw EditorError.general("Invalid arguments for splitClipAtTime")
                }
                return SplitClipAtTimeCommand(clipID: clipID, splitTime: splitTime)
            }
        ))

        register(CommandDefinition(
            name: "deleteClip",
            description: "Deletes a clip from the timeline.",
            parameters: [
                ParameterSchema(name: "clipID", type: "string", description: "UUID of the clip", isRequired: true)
            ],
            factory: { args in
                guard let clipIDStr = args["clipID"] as? String, let clipID = UUID(uuidString: clipIDStr) else {
                    throw EditorError.general("Invalid arguments for deleteClip")
                }
                return DeleteClipCommand(clipID: clipID)
            }
        ))
    }
}

// MARK: - Command Implementations

class GetProjectStateCommand: EditorCommand {
    var isMutating: Bool { false }

    func execute(on project: inout Project) -> Result<String, Error> {
        guard let seq = project.sequences.first(where: { $0.id == project.activeSequenceID }) else {
            return .failure(EditorError.general("No active sequence."))
        }
        
        let dict: [String: Any] = [
            "sequence": ["width": seq.width, "height": seq.height, "fps": seq.frameRate] as [String: Any],
            "mediaAssets": project.mediaAssets.map { ["id": $0.id.uuidString, "name": $0.name, "duration": $0.durationSeconds] as [String: Any] },
            "tracks": seq.tracks.map { track -> [String: Any] in
                return [
                    "id": track.id.uuidString, 
                    "name": track.name, 
                    "type": track.type.rawValue,
                    "clips": track.clips.map { c -> [String: Any] in
                        return ["id": c.id.uuidString, "name": c.name, "start": c.startTime, "duration": c.duration, "opacity": c.opacity]
                    }
                ]
            }
        ]
        
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
           let str = String(data: data, encoding: .utf8) {
            return .success(str)
        }
        return .failure(EditorError.general("Failed to serialize state."))
    }

}

class ImportMediaCommand: EditorCommand {
    let asset: MediaAsset
    private var didImport: Bool = false
    
    init(asset: MediaAsset) { self.asset = asset }
    
    func execute(on project: inout Project) -> Result<String, Error> {
        project.mediaAssets.append(asset)
        didImport = true
        return .success("Imported \(asset.name)")
    }
    
}

class SetSequenceFormatCommand: EditorCommand {
    let width: Int
    let height: Int
    private var oldWidth: Int?
    private var oldHeight: Int?
    
    init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
    
    func execute(on project: inout Project) -> Result<String, Error> {
        guard let seqIdx = project.sequences.firstIndex(where: { $0.id == project.activeSequenceID }) else { return .failure(EditorError.general("Sequence missing")) }
        oldWidth = project.sequences[seqIdx].width
        oldHeight = project.sequences[seqIdx].height
        project.sequences[seqIdx].width = width
        project.sequences[seqIdx].height = height
        return .success("Sequence format set to \(width)x\(height)")
    }
    
}

class TrimClipCommand: EditorCommand {
    let clipID: UUID
    let newSourceIn: Double?
    let newSourceOut: Double?
    let newStartTime: Double?
    
    private var oldSourceIn: Double?
    private var oldSourceOut: Double?
    private var oldStartTime: Double?
    
    init(clipID: UUID, newSourceIn: Double?, newSourceOut: Double?, newStartTime: Double?) {
        self.clipID = clipID
        self.newSourceIn = newSourceIn
        self.newSourceOut = newSourceOut
        self.newStartTime = newStartTime
    }
    
    func execute(on project: inout Project) -> Result<String, Error> {
        guard let seqIdx = project.sequences.firstIndex(where: { $0.id == project.activeSequenceID }) else { return .failure(EditorError.general("Sequence missing")) }
        
        for tIdx in project.sequences[seqIdx].tracks.indices {
            if let cIdx = project.sequences[seqIdx].tracks[tIdx].clips.firstIndex(where: { $0.id == clipID }) {
                let clip = project.sequences[seqIdx].tracks[tIdx].clips[cIdx]
                guard let asset = project.mediaAssets.first(where: { $0.id == clip.mediaAssetID }) else { return .failure(EditorError.general("Asset missing")) }
                
                let targetIn = newSourceIn ?? clip.sourceInPoint
                let targetOut = newSourceOut ?? clip.sourceOutPoint
                guard targetIn >= 0, targetOut <= asset.durationSeconds, targetIn < targetOut else {
                    return .failure(EditorError.general("Invalid trim range. Asset duration is \(asset.durationSeconds)"))
                }
                
                oldSourceIn = clip.sourceInPoint
                oldSourceOut = clip.sourceOutPoint
                oldStartTime = clip.startTime
                
                project.sequences[seqIdx].tracks[tIdx].clips[cIdx].sourceInPoint = targetIn
                project.sequences[seqIdx].tracks[tIdx].clips[cIdx].sourceOutPoint = targetOut
                if let st = newStartTime {
                    project.sequences[seqIdx].tracks[tIdx].clips[cIdx].startTime = max(0, st)
                }
                return .success("Trimmed clip \(clip.name)")
            }
        }
        return .failure(EditorError.general("Clip not found"))
    }
    
}

class SetClipTransformCommand: EditorCommand {
    let clipID: UUID
    let posX: Double?
    let posY: Double?
    let scale: Double?
    let rotation: Double?
    
    private var oldTransform: ClipTransform?
    
    init(clipID: UUID, posX: Double?, posY: Double?, scale: Double?, rotation: Double?) {
        self.clipID = clipID
        self.posX = posX
        self.posY = posY
        self.scale = scale
        self.rotation = rotation
    }
    
    func execute(on project: inout Project) -> Result<String, Error> {
        guard let seqIdx = project.sequences.firstIndex(where: { $0.id == project.activeSequenceID }) else { return .failure(EditorError.general("Sequence missing")) }
        for tIdx in project.sequences[seqIdx].tracks.indices {
            if let cIdx = project.sequences[seqIdx].tracks[tIdx].clips.firstIndex(where: { $0.id == clipID }) {
                let current = project.sequences[seqIdx].tracks[tIdx].clips[cIdx].transform
                oldTransform = current
                
                project.sequences[seqIdx].tracks[tIdx].clips[cIdx].transform.positionX = posX ?? current.positionX
                project.sequences[seqIdx].tracks[tIdx].clips[cIdx].transform.positionY = posY ?? current.positionY
                if let s = scale {
                    project.sequences[seqIdx].tracks[tIdx].clips[cIdx].transform.scaleX = s
                    project.sequences[seqIdx].tracks[tIdx].clips[cIdx].transform.scaleY = s
                }
                project.sequences[seqIdx].tracks[tIdx].clips[cIdx].transform.rotationDegrees = rotation ?? current.rotationDegrees
                return .success("Updated transform")
            }
        }
        return .failure(EditorError.general("Clip not found"))
    }
    
}

class AddClipToTimelineCommand: EditorCommand {
    let mediaAssetID: UUID
    let trackID: UUID
    let startTime: Double
    private var addedClipID: UUID?

    init(mediaAssetID: UUID, trackID: UUID, startTime: Double) {
        self.mediaAssetID = mediaAssetID
        self.trackID = trackID
        self.startTime = startTime
    }

    func execute(on project: inout Project) -> Result<String, Error> {
        guard let asset = project.mediaAssets.first(where: { $0.id == mediaAssetID }) else { return .failure(EditorError.general("Media asset not found")) }
        guard let seqIdx = project.sequences.firstIndex(where: { $0.id == project.activeSequenceID }),
              let trackIdx = project.sequences[seqIdx].tracks.firstIndex(where: { $0.id == trackID }) else { return .failure(EditorError.general("Track not found")) }
        
        let newClip = Clip(mediaAssetID: asset.id, name: asset.name, startTime: startTime, sourceInPoint: 0, sourceOutPoint: asset.durationSeconds)
        project.sequences[seqIdx].tracks[trackIdx].clips.append(newClip)
        addedClipID = newClip.id
        return .success("Added clip \(newClip.name) to timeline.")
    }

}

class MoveClipCommand: EditorCommand {
    let clipID: UUID
    let newStartTime: Double
    let newTrackID: UUID?
    private var oldStartTime: Double?
    private var oldTrackID: UUID?

    init(clipID: UUID, newStartTime: Double, newTrackID: UUID?) {
        self.clipID = clipID
        self.newStartTime = newStartTime
        self.newTrackID = newTrackID
    }

    func execute(on project: inout Project) -> Result<String, Error> {
        guard let seqIdx = project.sequences.firstIndex(where: { $0.id == project.activeSequenceID }) else { return .failure(EditorError.general("Sequence not found")) }
        var foundTrackIdx: Int?
        var foundClipIdx: Int?
        for tIdx in project.sequences[seqIdx].tracks.indices {
            if let cIdx = project.sequences[seqIdx].tracks[tIdx].clips.firstIndex(where: { $0.id == clipID }) {
                foundTrackIdx = tIdx; foundClipIdx = cIdx; break
            }
        }
        guard let sTrackIdx = foundTrackIdx, let cIdx = foundClipIdx else { return .failure(EditorError.general("Clip not found")) }
        let dTrackIdx = newTrackID != nil ? project.sequences[seqIdx].tracks.firstIndex(where: { $0.id == newTrackID! }) : sTrackIdx
        guard let dTrackIdx = dTrackIdx else { return .failure(EditorError.general("Destination track not found")) }
        
        var clip = project.sequences[seqIdx].tracks[sTrackIdx].clips.remove(at: cIdx)
        oldStartTime = clip.startTime
        oldTrackID = project.sequences[seqIdx].tracks[sTrackIdx].id
        clip.startTime = max(0, newStartTime)
        project.sequences[seqIdx].tracks[dTrackIdx].clips.append(clip)
        return .success("Moved clip to \(clip.startTime)s.")
    }

}

class SetClipOpacityCommand: EditorCommand {
    let clipID: UUID
    let opacity: Double
    private var oldOpacity: Double?

    init(clipID: UUID, opacity: Double) { self.clipID = clipID; self.opacity = opacity }

    func execute(on project: inout Project) -> Result<String, Error> {
        guard let seqIdx = project.sequences.firstIndex(where: { $0.id == project.activeSequenceID }) else { return .failure(EditorError.general("Sequence missing")) }
        for tIdx in project.sequences[seqIdx].tracks.indices {
            if let cIdx = project.sequences[seqIdx].tracks[tIdx].clips.firstIndex(where: { $0.id == clipID }) {
                oldOpacity = project.sequences[seqIdx].tracks[tIdx].clips[cIdx].opacity
                project.sequences[seqIdx].tracks[tIdx].clips[cIdx].opacity = opacity
                return .success("Set opacity to \(opacity)")
            }
        }
        return .failure(EditorError.general("Clip not found"))
    }

}

class SplitClipAtTimeCommand: EditorCommand {
    let clipID: UUID
    let splitTime: Double
    private var createdClipID: UUID?

    init(clipID: UUID, splitTime: Double) { self.clipID = clipID; self.splitTime = splitTime }

    func execute(on project: inout Project) -> Result<String, Error> {
        guard let seqIdx = project.sequences.firstIndex(where: { $0.id == project.activeSequenceID }) else { return .failure(EditorError.general("Sequence missing")) }
        for tIdx in project.sequences[seqIdx].tracks.indices {
            if let cIdx = project.sequences[seqIdx].tracks[tIdx].clips.firstIndex(where: { $0.id == clipID }) {
                let original = project.sequences[seqIdx].tracks[tIdx].clips[cIdx]
                guard splitTime > original.startTime && splitTime < original.endTime else { return .failure(EditorError.general("Split time is outside clip bounds")) }
                // Timeline offset -> source offset goes through the clip's speed
                let offset = splitTime - original.startTime
                let sourceSplit = original.sourceInPoint + offset * original.playbackRate
                let splitFraction = original.fraction(atTimeline: splitTime)
                project.sequences[seqIdx].tracks[tIdx].clips[cIdx].sourceOutPoint = sourceSplit
                project.sequences[seqIdx].tracks[tIdx].clips[cIdx].animation = original.animation?.slice(from: 0, to: splitFraction)
                let newID = UUID()
                createdClipID = newID
                let secondClip = Clip(id: newID, mediaAssetID: original.mediaAssetID, name: "\(original.name) (Part 2)", startTime: splitTime, sourceInPoint: sourceSplit, sourceOutPoint: original.sourceOutPoint, opacity: original.opacity, transform: original.transform, speed: original.speed, animation: original.animation?.slice(from: splitFraction, to: 1))
                project.sequences[seqIdx].tracks[tIdx].clips.append(secondClip)
                return .success("Split clip at \(splitTime)s")
            }
        }
        return .failure(EditorError.general("Clip not found"))
    }

}

class DeleteClipCommand: EditorCommand {
    let clipID: UUID
    private var deletedClip: Clip?
    private var oldTrackID: UUID?

    init(clipID: UUID) { self.clipID = clipID }

    func execute(on project: inout Project) -> Result<String, Error> {
        guard let seqIdx = project.sequences.firstIndex(where: { $0.id == project.activeSequenceID }) else { return .failure(EditorError.general("Sequence missing")) }
        for tIdx in project.sequences[seqIdx].tracks.indices {
            if let cIdx = project.sequences[seqIdx].tracks[tIdx].clips.firstIndex(where: { $0.id == clipID }) {
                deletedClip = project.sequences[seqIdx].tracks[tIdx].clips[cIdx]
                oldTrackID = project.sequences[seqIdx].tracks[tIdx].id
                project.sequences[seqIdx].tracks[tIdx].clips.remove(at: cIdx)
                return .success("Clip deleted")
            }
        }
        return .failure(EditorError.general("Clip not found"))
    }

}

