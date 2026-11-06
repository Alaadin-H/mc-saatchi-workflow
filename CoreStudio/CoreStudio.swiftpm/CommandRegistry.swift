import Foundation

final class CommandRegistry {
    private var commands: [String: CommandDefinition] = [:]

    func register(_ definition: CommandDefinition) {
        commands[definition.name] = definition
    }

    func makeCommand(name: String, arguments: [String: Any]) throws -> EditorCommand {
        guard let definition = commands[name] else {
            throw EditorError.general("Command \(name) not found.")
        }
        return try definition.factory(arguments)
    }

    func exportToolSchemas() -> String {
        let tools = commands.values.map { def -> [String: Any] in
            var properties: [String: Any] = [:]
            var required: [String] = []
            
            for param in def.parameters {
                properties[param.name] = [
                    "type": param.type,
                    "description": param.description
                ] as [String: Any]
                if param.isRequired { required.append(param.name) }
            }
            
            return [
                "type": "function",
                "function": [
                    "name": def.name,
                    "description": def.description,
                    "parameters": [
                        "type": "object",
                        "properties": properties,
                        "required": required
                    ] as [String: Any]
                ] as [String: Any]
            ] as [String: Any]
        }
        
        guard let data = try? JSONSerialization.data(withJSONObject: tools, options: .prettyPrinted) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }
    
    func getAllDefinitions() -> [CommandDefinition] {
        Array(commands.values).sorted(by: { $0.name < $1.name })
    }
}

