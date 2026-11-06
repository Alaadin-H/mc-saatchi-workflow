import Foundation

final class AddEffectCommand: EditorCommand {
    let clipID: UUID
    let effectID: String

    init(clipID: UUID, effectID: String) { self.clipID = clipID; self.effectID = effectID }

    func execute(on project: inout Project) -> Result<String, Error> {
        guard let def = EffectCatalogue.definition(effectID) else {
            return .failure(EditorError.general("Unknown effect \(effectID)"))
        }
        let applied = AppliedEffect(effectID: def.id, params: EffectCatalogue.defaults(for: def))
        guard project.updateClip(clipID, { clip in
            clip.effects = (clip.effects ?? []) + [applied]
        }) != nil else { return .failure(EditorError.general("Clip not found")) }
        return .success("Added \(def.name). Effect instance id: \(applied.id.uuidString)")
    }
}

final class RemoveEffectCommand: EditorCommand {
    let clipID: UUID
    let instanceID: UUID

    init(clipID: UUID, instanceID: UUID) { self.clipID = clipID; self.instanceID = instanceID }

    func execute(on project: inout Project) -> Result<String, Error> {
        guard project.updateClip(clipID, { clip in
            clip.effects?.removeAll { $0.id == instanceID }
            if clip.effects?.isEmpty == true { clip.effects = nil }
        }) != nil else { return .failure(EditorError.general("Clip not found")) }
        return .success("Effect removed")
    }
}

final class UpdateEffectCommand: EditorCommand {
    let clipID: UUID
    let instanceID: UUID
    let parameter: String?
    let value: Double?
    let enabled: Bool?

    init(clipID: UUID, instanceID: UUID, parameter: String? = nil, value: Double? = nil, enabled: Bool? = nil) {
        self.clipID = clipID; self.instanceID = instanceID
        self.parameter = parameter; self.value = value; self.enabled = enabled
    }

    func execute(on project: inout Project) -> Result<String, Error> {
        var found = false
        project.updateClip(clipID) { clip in
            guard let i = clip.effects?.firstIndex(where: { $0.id == instanceID }) else { return }
            found = true
            if let key = parameter, let v = value { clip.effects?[i].params[key] = v }
            if let e = enabled { clip.effects?[i].enabled = e }
        }
        return found ? .success("Effect updated") : .failure(EditorError.general("Effect not found"))
    }
}

/// Lists the effect catalogue (for AI agents). Changes nothing.
final class ListEffectsCommand: EditorCommand {
    var isMutating: Bool { false }

    func execute(on project: inout Project) -> Result<String, Error> {
        let list = EffectCatalogue.all.map { def -> [String: Any] in
            ["id": def.id, "name": def.name, "category": def.category,
             "parameters": def.parameters.map { p -> [String: Any] in
                ["key": p.key, "name": p.name, "min": p.min, "max": p.max, "default": p.defaultValue]
             }]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: list, options: .prettyPrinted),
              let text = String(data: data, encoding: .utf8) else {
            return .failure(EditorError.general("Could not list effects"))
        }
        return .success(text)
    }
}

extension CommandRegistry {
    func registerEffectCommands() {
        register(CommandDefinition(
            name: "listEffects",
            description: "Lists every available effect with its id and parameters.",
            parameters: [],
            factory: { _ in ListEffectsCommand() }
        ))
        register(CommandDefinition(
            name: "addEffect",
            description: "Adds an effect (by catalogue id, see listEffects) to a clip. Returns the new effect instance id.",
            parameters: [
                ParameterSchema(name: "clipID", type: "string", description: "UUID of the clip", isRequired: true),
                ParameterSchema(name: "effectID", type: "string", description: "Catalogue id, e.g. color.adjust", isRequired: true)
            ],
            factory: { args in
                guard let s = args["clipID"] as? String, let id = UUID(uuidString: s),
                      let effectID = args["effectID"] as? String else { throw EditorError.general("Invalid addEffect arguments") }
                return AddEffectCommand(clipID: id, effectID: effectID)
            }
        ))
        register(CommandDefinition(
            name: "setEffectParameter",
            description: "Changes one parameter of an effect on a clip, or turns it on/off.",
            parameters: [
                ParameterSchema(name: "clipID", type: "string", description: "UUID of the clip", isRequired: true),
                ParameterSchema(name: "instanceID", type: "string", description: "Effect instance id from addEffect", isRequired: true),
                ParameterSchema(name: "parameter", type: "string", description: "Parameter key, e.g. inputRadius", isRequired: false),
                ParameterSchema(name: "value", type: "number", description: "New value", isRequired: false),
                ParameterSchema(name: "enabled", type: "boolean", description: "On/off", isRequired: false)
            ],
            factory: { args in
                guard let s = args["clipID"] as? String, let id = UUID(uuidString: s),
                      let i = args["instanceID"] as? String, let instance = UUID(uuidString: i) else {
                    throw EditorError.general("Invalid setEffectParameter arguments")
                }
                return UpdateEffectCommand(clipID: id, instanceID: instance,
                                           parameter: args["parameter"] as? String,
                                           value: args["value"] as? Double,
                                           enabled: args["enabled"] as? Bool)
            }
        ))
        register(CommandDefinition(
            name: "removeEffect",
            description: "Removes an effect instance from a clip.",
            parameters: [
                ParameterSchema(name: "clipID", type: "string", description: "UUID of the clip", isRequired: true),
                ParameterSchema(name: "instanceID", type: "string", description: "Effect instance id", isRequired: true)
            ],
            factory: { args in
                guard let s = args["clipID"] as? String, let id = UUID(uuidString: s),
                      let i = args["instanceID"] as? String, let instance = UUID(uuidString: i) else {
                    throw EditorError.general("Invalid removeEffect arguments")
                }
                return RemoveEffectCommand(clipID: id, instanceID: instance)
            }
        ))
    }
}
