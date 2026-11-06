import Foundation

protocol EditorCommand: AnyObject {
    var isMutating: Bool { get }
    func execute(on project: inout Project) -> Result<String, Error>
    func undo(on project: inout Project) -> Bool
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

