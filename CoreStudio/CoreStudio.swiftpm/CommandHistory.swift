import Foundation

/// Undo by snapshots (idea from Concat's editor): before each edit we keep the
/// whole Project as it was. Project is a value type, so a snapshot is a cheap
/// copy-on-write copy, and undo can never get out of sync the way hand-written
/// inverse operations can.
///
/// A *gesture* groups many edits into ONE undo step (e.g. dragging a slider):
/// consecutive edits that name the same gesture fold into the first one.
final class CommandHistory {
    private struct Step {
        let before: Project
    }

    private var undoStack: [Step] = []
    private var redoStack: [Project] = []
    private var openGesture: String?
    private let maxDepth = 200

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func execute(_ command: EditorCommand, on project: inout Project, gesture: String? = nil) -> Result<String, Error> {
        var working = project
        let result = command.execute(on: &working)
        guard case .success = result, command.isMutating else { return result }

        let continuesGesture = gesture != nil && gesture == openGesture && !undoStack.isEmpty
        if !continuesGesture {
            undoStack.append(Step(before: project))
            if undoStack.count > maxDepth { undoStack.removeFirst() }
        }
        openGesture = gesture
        redoStack.removeAll()
        project = working
        return result
    }

    /// Ends the current gesture: the next edit starts a new undo step.
    func endGesture() { openGesture = nil }

    func undo(on project: inout Project) -> Bool {
        openGesture = nil
        guard let step = undoStack.popLast() else { return false }
        redoStack.append(project)
        project = step.before
        return true
    }

    func redo(on project: inout Project) -> Bool {
        openGesture = nil
        guard let next = redoStack.popLast() else { return false }
        undoStack.append(Step(before: project))
        project = next
        return true
    }
}
