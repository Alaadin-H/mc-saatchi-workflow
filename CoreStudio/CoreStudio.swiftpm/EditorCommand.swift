import Foundation

protocol EditorCommand: AnyObject {
    var isMutating: Bool { get }
    /// Applies the edit. Undo is handled by CommandHistory snapshots, so commands don't implement it.
    func execute(on project: inout Project) -> Result<String, Error>
}

extension EditorCommand {
    var isMutating: Bool { true }
}

struct ParameterSchema: Codable {
    let name: String
    let type: String
    let description: String
    let isRequired: Bool
}

struct CommandDefinition {
    let name: String
    let description: String
    let parameters: [ParameterSchema]
    let factory: ([String: Any]) throws -> EditorCommand
}

