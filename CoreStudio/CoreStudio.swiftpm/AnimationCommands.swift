import Foundation

// Commands for speed and keyframes. With snapshot undo (see CommandHistory)
// a command only has to describe the change; undo comes for free.

extension Project {
    /// Runs `body` on the clip with this id in the active sequence. Returns the updated clip, or nil if not found.
    @discardableResult
    mutating func updateClip(_ clipID: UUID, _ body: (inout Clip) -> Void) -> Clip? {
        guard let s = sequences.firstIndex(where: { $0.id == activeSequenceID }) else { return nil }
        for t in sequences[s].tracks.indices {
            if let c = sequences[s].tracks[t].clips.firstIndex(where: { $0.id == clipID }) {
                body(&sequences[s].tracks[t].clips[c])
                return sequences[s].tracks[t].clips[c]
            }
        }
        return nil
    }

    func clip(_ clipID: UUID) -> Clip? {
        guard let seq = sequences.first(where: { $0.id == activeSequenceID }) else { return nil }
        for track in seq.tracks {
            if let c = track.clips.first(where: { $0.id == clipID }) { return c }
        }
        return nil
    }
}

/// Sets a property's static value (used when the property has no keyframes).
final class SetClipPropertyCommand: EditorCommand {
    let clipID: UUID
    let property: AnimatableProperty
    let value: Double

    init(clipID: UUID, property: AnimatableProperty, value: Double) {
        self.clipID = clipID; self.property = property; self.value = value
    }

    func execute(on project: inout Project) -> Result<String, Error> {
        guard project.updateClip(clipID, { $0.setBaseValue(property, value) }) != nil else {
            return .failure(EditorError.general("Clip not found"))
        }
        return .success("\(property.title) set to \(value)")
    }
}

final class SetClipSpeedCommand: EditorCommand {
    let clipID: UUID
    let speed: Double

    init(clipID: UUID, speed: Double) { self.clipID = clipID; self.speed = speed }

    func execute(on project: inout Project) -> Result<String, Error> {
        let s = min(max(speed, Clip.speedRange.lowerBound), Clip.speedRange.upperBound)
        guard let clip = project.updateClip(clipID, { $0.speed = abs(s - 1) < 0.0001 ? nil : s }) else {
            return .failure(EditorError.general("Clip not found"))
        }
        return .success(String(format: "Speed %.2fx, clip is now %.2fs long", clip.playbackRate, clip.duration))
    }
}

/// Adds (or replaces) a keyframe at a timeline time inside the clip.
final class SetKeyframeCommand: EditorCommand {
    let clipID: UUID
    let property: AnimatableProperty
    let timelineTime: Double
    let value: Double
    let ease: CubicEase

    init(clipID: UUID, property: AnimatableProperty, timelineTime: Double, value: Double, ease: CubicEase = .easeInOut) {
        self.clipID = clipID; self.property = property; self.timelineTime = timelineTime; self.value = value; self.ease = ease
    }

    func execute(on project: inout Project) -> Result<String, Error> {
        guard let original = project.clip(clipID) else { return .failure(EditorError.general("Clip not found")) }
        let at = original.fraction(atTimeline: timelineTime)
        project.updateClip(clipID) { clip in
            var anim = clip.animation ?? ClipAnimation()
            if anim.keys(for: property).isEmpty && abs(at) > 0.0005 {
                // First key on a property: also pin the current value at the clip's start,
                // so the clip animates FROM where it was TO the new value.
                anim.setKey(property, at: 0, value: clip.baseValue(property), ease: .linear)
            }
            anim.setKey(property, at: at, value: value, ease: ease)
            clip.animation = anim
        }
        return .success(String(format: "Keyframe %@ = %.2f at %.2fs", property.title, value, timelineTime))
    }
}

final class ClearKeyframesCommand: EditorCommand {
    let clipID: UUID
    let property: AnimatableProperty?

    init(clipID: UUID, property: AnimatableProperty?) { self.clipID = clipID; self.property = property }

    func execute(on project: inout Project) -> Result<String, Error> {
        guard project.updateClip(clipID, { clip in
            guard var anim = clip.animation else { return }
            if let p = property { anim.clear(p) } else { anim = ClipAnimation() }
            clip.animation = anim.isEmpty ? nil : anim
        }) != nil else { return .failure(EditorError.general("Clip not found")) }
        return .success("Keyframes cleared")
    }
}

// MARK: - AI agent / JSON access

extension CommandRegistry {
    func registerAnimationCommands() {
        let propertyNames = AnimatableProperty.allCases.map(\.rawValue).joined(separator: ", ")

        register(CommandDefinition(
            name: "setClipSpeed",
            description: "Changes a clip's playback speed (0.1 to 16; 1 = normal, 2 = twice as fast). The clip's timeline length changes accordingly.",
            parameters: [
                ParameterSchema(name: "clipID", type: "string", description: "UUID of the clip", isRequired: true),
                ParameterSchema(name: "speed", type: "number", description: "Speed multiplier", isRequired: true)
            ],
            factory: { args in
                guard let idStr = args["clipID"] as? String, let id = UUID(uuidString: idStr),
                      let speed = args["speed"] as? Double else { throw EditorError.general("Invalid setClipSpeed arguments") }
                return SetClipSpeedCommand(clipID: id, speed: speed)
            }
        ))

        register(CommandDefinition(
            name: "setKeyframe",
            description: "Adds a keyframe to a clip property at a timeline time. Properties: \(propertyNames). Values: scale is a multiplier, positions are pixels from center, rotation in degrees, opacity 0-1.",
            parameters: [
                ParameterSchema(name: "clipID", type: "string", description: "UUID of the clip", isRequired: true),
                ParameterSchema(name: "property", type: "string", description: propertyNames, isRequired: true),
                ParameterSchema(name: "time", type: "number", description: "Timeline time in seconds", isRequired: true),
                ParameterSchema(name: "value", type: "number", description: "Property value at that time", isRequired: true),
                ParameterSchema(name: "ease", type: "string", description: "linear, easeIn, easeOut or easeInOut (default)", isRequired: false)
            ],
            factory: { args in
                guard let idStr = args["clipID"] as? String, let id = UUID(uuidString: idStr),
                      let pStr = args["property"] as? String, let p = AnimatableProperty(rawValue: pStr),
                      let time = args["time"] as? Double, let value = args["value"] as? Double else {
                    throw EditorError.general("Invalid setKeyframe arguments")
                }
                let ease = (args["ease"] as? String).flatMap(CubicEase.named) ?? .easeInOut
                return SetKeyframeCommand(clipID: id, property: p, timelineTime: time, value: value, ease: ease)
            }
        ))

        register(CommandDefinition(
            name: "clearKeyframes",
            description: "Removes keyframes from a clip: one property, or all when property is omitted.",
            parameters: [
                ParameterSchema(name: "clipID", type: "string", description: "UUID of the clip", isRequired: true),
                ParameterSchema(name: "property", type: "string", description: propertyNames, isRequired: false)
            ],
            factory: { args in
                guard let idStr = args["clipID"] as? String, let id = UUID(uuidString: idStr) else {
                    throw EditorError.general("Invalid clearKeyframes arguments")
                }
                let p = (args["property"] as? String).flatMap(AnimatableProperty.init(rawValue:))
                return ClearKeyframesCommand(clipID: id, property: p)
            }
        ))
    }
}
