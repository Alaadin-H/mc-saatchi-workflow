import Foundation

// MARK: - Helpers

extension Project {
    var activeSequenceIndex: Int? { sequences.firstIndex(where: { $0.id == activeSequenceID }) }

    /// Where a clip lives: (track index, clip index) in the active sequence.
    func locate(_ clipID: UUID) -> (track: Int, clip: Int)? {
        guard let s = activeSequenceIndex else { return nil }
        for t in sequences[s].tracks.indices {
            if let c = sequences[s].tracks[t].clips.firstIndex(where: { $0.id == clipID }) { return (t, c) }
        }
        return nil
    }

    /// A track of this type with nothing between `start` and `end`, preferring `preferred`,
    /// then the highest video track. Creates a new track if all are busy. Returns its index.
    mutating func freeTrack(type: TrackType, start: Double, end: Double, preferred: UUID? = nil) -> Int? {
        guard let s = activeSequenceIndex else { return nil }
        let tracks = sequences[s].tracks
        func isFree(_ t: Track) -> Bool {
            !t.clips.contains { $0.startTime < end - 0.001 && $0.endTime > start + 0.001 }
        }
        if let p = preferred, let i = tracks.firstIndex(where: { $0.id == p && $0.type == type }), isFree(tracks[i]) {
            return i
        }
        let candidates = tracks.indices.filter { tracks[$0].type == type }
        for i in candidates.reversed() where isFree(tracks[i]) { return i }
        let count = candidates.count + 1
        let newTrack = Track(name: "\(type == .video ? "Video" : "Audio") \(count)", type: type)
        // Keep video tracks before audio tracks in the list
        if type == .video, let lastVideo = candidates.last {
            sequences[s].tracks.insert(newTrack, at: lastVideo + 1)
            return lastVideo + 1
        }
        sequences[s].tracks.append(newTrack)
        return sequences[s].tracks.count - 1
    }
}

// MARK: - Titles

final class AddTitleCommand: EditorCommand {
    let presetID: String
    let startTime: Double
    let duration: Double
    let text: String?
    private(set) var createdClipID: UUID?

    init(presetID: String = "basic", startTime: Double, duration: Double = 3, text: String? = nil) {
        self.presetID = presetID; self.startTime = startTime; self.duration = duration; self.text = text
    }

    func execute(on project: inout Project) -> Result<String, Error> {
        let preset = TitlePreset.named(presetID)
        var style = preset.style
        if let text, !text.isEmpty { style.text = text }
        let start = max(0, startTime)
        let length = max(0.2, duration)
        guard let s = project.activeSequenceIndex,
              let t = project.freeTrack(type: .video, start: start, end: start + length) else {
            return .failure(EditorError.general("No sequence"))
        }
        let k = Double(project.sequences[s].height) / 1080
        var clip = Clip(mediaAssetID: Clip.titleAssetID, name: style.text, startTime: start,
                        sourceInPoint: 0, sourceOutPoint: length, title: style)
        clip.transform.positionY = preset.positionY * k
        clip.transitionIn = ClipTransition(type: "crossDissolve", duration: 0.4)
        project.sequences[s].tracks[t].clips.append(clip)
        createdClipID = clip.id
        return .success("Added title \"\(style.text)\" (clip id \(clip.id.uuidString)) on \(project.sequences[s].tracks[t].name)")
    }
}

final class UpdateTitleCommand: EditorCommand {
    let clipID: UUID
    let style: TitleStyle

    init(clipID: UUID, style: TitleStyle) { self.clipID = clipID; self.style = style }

    func execute(on project: inout Project) -> Result<String, Error> {
        guard project.clip(clipID)?.isTitle == true else { return .failure(EditorError.general("Not a title clip")) }
        project.updateClip(clipID) { clip in
            clip.title = style
            let firstLine = style.text.split(separator: "\n").first.map(String.init) ?? "Title"
            clip.name = firstLine.isEmpty ? "Title" : firstLine
        }
        return .success("Title updated")
    }
}

// MARK: - Transitions

final class SetTransitionCommand: EditorCommand {
    let clipID: UUID
    let transition: ClipTransition?

    init(clipID: UUID, transition: ClipTransition?) { self.clipID = clipID; self.transition = transition }

    func execute(on project: inout Project) -> Result<String, Error> {
        if let t = transition, TransitionKind.named(t.type) == nil {
            return .failure(EditorError.general("Unknown transition \(t.type)"))
        }
        let value = transition.map { ClipTransition(type: $0.type, duration: min(max($0.duration, 0.1), 5)) }
        guard project.updateClip(clipID, { $0.transitionIn = value }) != nil else {
            return .failure(EditorError.general("Clip not found"))
        }
        return .success(value.map { "Transition \($0.type), \($0.duration)s" } ?? "Transition removed")
    }
}

// MARK: - Ripple edits (Premiere: Shift+Delete, Q, W)

/// Deletes a clip and closes the gap: later clips on the same track move left.
final class RippleDeleteCommand: EditorCommand {
    let clipID: UUID

    init(clipID: UUID) { self.clipID = clipID }

    func execute(on project: inout Project) -> Result<String, Error> {
        guard let s = project.activeSequenceIndex, let location = project.locate(clipID) else {
            return .failure(EditorError.general("Clip not found"))
        }
        let t = location.track, c = location.clip
        let removed = project.sequences[s].tracks[t].clips.remove(at: c)
        for i in project.sequences[s].tracks[t].clips.indices where project.sequences[s].tracks[t].clips[i].startTime >= removed.endTime - 0.001 {
            project.sequences[s].tracks[t].clips[i].startTime -= removed.duration
        }
        return .success("Ripple deleted \(removed.name)")
    }
}

/// Trims a clip's start or end to `time` and ripples later clips on its track.
final class RippleTrimCommand: EditorCommand {
    enum Edge { case start, end }
    let clipID: UUID
    let edge: Edge
    let time: Double

    init(clipID: UUID, edge: Edge, time: Double) { self.clipID = clipID; self.edge = edge; self.time = time }

    func execute(on project: inout Project) -> Result<String, Error> {
        guard let s = project.activeSequenceIndex, let location = project.locate(clipID) else {
            return .failure(EditorError.general("Clip not found"))
        }
        let t = location.track, c = location.clip
        let clip = project.sequences[s].tracks[t].clips[c]
        guard time > clip.startTime + 0.01, time < clip.endTime - 0.01 else {
            return .failure(EditorError.general("The playhead must be inside the clip"))
        }
        let removed: Double
        switch edge {
        case .start:
            removed = time - clip.startTime
            project.sequences[s].tracks[t].clips[c].sourceInPoint += removed * clip.playbackRate
        case .end:
            removed = clip.endTime - time
            project.sequences[s].tracks[t].clips[c].sourceOutPoint -= removed * clip.playbackRate
        }
        for i in project.sequences[s].tracks[t].clips.indices where i != c
            && project.sequences[s].tracks[t].clips[i].startTime >= clip.endTime - 0.001 {
            project.sequences[s].tracks[t].clips[i].startTime -= removed
        }
        return .success("Ripple trimmed \(clip.name)")
    }
}

/// Pastes a copy of a clip at a time (on its own track if free, else another one).
final class PasteClipCommand: EditorCommand {
    let clip: Clip
    let startTime: Double
    let preferredTrack: UUID?
    private(set) var createdClipID: UUID?

    init(clip: Clip, startTime: Double, preferredTrack: UUID?) {
        self.clip = clip; self.startTime = startTime; self.preferredTrack = preferredTrack
    }

    func execute(on project: inout Project) -> Result<String, Error> {
        guard let s = project.activeSequenceIndex else { return .failure(EditorError.general("No sequence")) }
        let isAudio = project.sequences[s].tracks.first(where: { $0.id == preferredTrack })?.type == .audio
        let start = max(0, startTime)
        guard let t = project.freeTrack(type: isAudio ? .audio : .video, start: start, end: start + clip.duration, preferred: preferredTrack) else {
            return .failure(EditorError.general("No track"))
        }
        var copy = Clip(mediaAssetID: clip.mediaAssetID, name: clip.name, startTime: start,
                        sourceInPoint: clip.sourceInPoint, sourceOutPoint: clip.sourceOutPoint,
                        opacity: clip.opacity, transform: clip.transform, speed: clip.speed,
                        animation: clip.animation, effects: clip.effects, title: clip.title, transitionIn: clip.transitionIn)
        copy.effects = copy.effects?.map { var e = $0; e.id = UUID(); return e }
        project.sequences[s].tracks[t].clips.append(copy)
        createdClipID = copy.id
        return .success("Pasted \(clip.name)")
    }
}

// MARK: - AI agent access

extension CommandRegistry {
    func registerEditingCommands() {
        let presets = TitlePreset.all.map(\.id).joined(separator: ", ")
        let transitions = TransitionKind.all.map(\.id).joined(separator: ", ")

        register(CommandDefinition(
            name: "addTitle",
            description: "Adds a text title to the timeline. Presets: \(presets).",
            parameters: [
                ParameterSchema(name: "text", type: "string", description: "Title text", isRequired: true),
                ParameterSchema(name: "startTime", type: "number", description: "Timeline start in seconds", isRequired: true),
                ParameterSchema(name: "duration", type: "number", description: "Seconds (default 3)", isRequired: false),
                ParameterSchema(name: "preset", type: "string", description: presets, isRequired: false)
            ],
            factory: { args in
                guard let text = args["text"] as? String, let start = args["startTime"] as? Double else {
                    throw EditorError.general("Invalid addTitle arguments")
                }
                return AddTitleCommand(presetID: args["preset"] as? String ?? "basic", startTime: start,
                                       duration: args["duration"] as? Double ?? 3, text: text)
            }
        ))
        register(CommandDefinition(
            name: "setTransition",
            description: "Sets the transition INTO a clip (from the clip before it, or a fade-in). Types: \(transitions). Omit type to remove.",
            parameters: [
                ParameterSchema(name: "clipID", type: "string", description: "UUID of the clip", isRequired: true),
                ParameterSchema(name: "type", type: "string", description: transitions, isRequired: false),
                ParameterSchema(name: "duration", type: "number", description: "Seconds (default 0.8)", isRequired: false)
            ],
            factory: { args in
                guard let s = args["clipID"] as? String, let id = UUID(uuidString: s) else {
                    throw EditorError.general("Invalid setTransition arguments")
                }
                let transition = (args["type"] as? String).map {
                    ClipTransition(type: $0, duration: args["duration"] as? Double ?? ClipTransition.defaultDuration)
                }
                return SetTransitionCommand(clipID: id, transition: transition)
            }
        ))
        register(CommandDefinition(
            name: "rippleDelete",
            description: "Deletes a clip and moves later clips on its track left to close the gap.",
            parameters: [ParameterSchema(name: "clipID", type: "string", description: "UUID of the clip", isRequired: true)],
            factory: { args in
                guard let s = args["clipID"] as? String, let id = UUID(uuidString: s) else {
                    throw EditorError.general("Invalid rippleDelete arguments")
                }
                return RippleDeleteCommand(clipID: id)
            }
        ))
    }
}
