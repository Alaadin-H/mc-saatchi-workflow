import Foundation

final class CommandHistory {
    private var undoStack: [EditorCommand] = []
    private var redoStack: [EditorCommand] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func execute(_ command: EditorCommand, on project: inout Project) -> Result<String, Error> {
        var mutableProject = project
        let result = command.execute(on: &mutableProject)
        
        if case .success = result, command.isMutating {
            project = mutableProject
            undoStack.append(command)
            redoStack.removeAll()
        }
        return result
    }

    func undo(on project: inout Project) -> Bool {
        guard let command = undoStack.popLast() else { return false }
        var mutableProject = project
        if command.undo(on: &mutableProject) {
            project = mutableProject
            redoStack.append(command)
            return true
        } else {
            undoStack.append(command)
            return false
        }
    }

    func redo(on project: inout Project) -> Bool {
        guard let command = redoStack.popLast() else { return false }
        var mutableProject = project
        let result = command.execute(on: &mutableProject)
        if case .success = result {
            project = mutableProject
            undoStack.append(command)
            return true
        } else {
            redoStack.append(command)
            return false
        }
    }
}

