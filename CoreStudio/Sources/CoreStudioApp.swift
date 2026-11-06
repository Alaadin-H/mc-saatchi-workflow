import SwiftUI
import Combine

@main
struct CoreStudioApp: App {
    @StateObject private var editorState = EditorState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(editorState)
                .preferredColorScheme(.dark)
        }
    }
}

enum EditorError: Error, LocalizedError {
    case general(String)
    var errorDescription: String? {
        switch self { case .general(let msg): return msg }
    }
}

enum EditorTool {
    case select
    case blade
}

final class EditorState: ObservableObject {
    @Published var project: Project
    @Published var selectedClipID: UUID?
    @Published var selectedTrackID: UUID?
    @Published var currentTime: Double = 0.0
    
    @Published var zoomScale: CGFloat = 20.0
    @Published var activeTool: EditorTool = .select
    @Published var inMark: Double? = nil
    @Published var outMark: Double? = nil

    let commandRegistry = CommandRegistry()
    let commandHistory = CommandHistory()
    let projectStorage = ProjectStorageService()
    let mediaImporter = MediaImportService()
    let playbackEngine = PlaybackEngine()

    private var cancellables = Set<AnyCancellable>()
    private var lastRebuildTime: Date = .distantPast

    init() {
        self.project = Project(name: "Untitled Project")
        
        commandRegistry.registerStandardCommands()
        
        playbackEngine.onTimeChanged = { [weak self] time in
            self?.currentTime = time
        }
        
        playbackEngine.onStatusChanged = { [weak self] playing in
            self?.objectWillChange.send()
        }
        
        $project
            .dropFirst()
            .debounce(for: .seconds(2.0), scheduler: RunLoop.main)
            .sink { [weak self] proj in
                self?.projectStorage.saveProject(proj)
            }
            .store(in: &cancellables)
    }

    func execute(_ command: EditorCommand) {
        let result = commandHistory.execute(command, on: &project)
        if case .success = result, command.isMutating {
            project.updatedAt = Date()
            rebuildComposition()
            objectWillChange.send()
        }
    }
    
    func executeFromJSON(name: String, argumentsJSON: String) -> Result<String, Error> {
        do {
            guard let data = argumentsJSON.data(using: .utf8),
                  let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .failure(EditorError.general("Invalid JSON arguments."))
            }
            
            let command = try commandRegistry.makeCommand(name: name, arguments: dict)
            let executionResult = commandHistory.execute(command, on: &project)
            
            if case .success(let summary) = executionResult, command.isMutating {
                project.updatedAt = Date()
                rebuildComposition()
                objectWillChange.send()
                return .success(summary)
            }
            return executionResult
        } catch {
            return .failure(error)
        }
    }

    func undo() {
        if commandHistory.undo(on: &project) {
            project.updatedAt = Date()
            rebuildComposition()
            objectWillChange.send()
        }
    }

    func redo() {
        if commandHistory.redo(on: &project) {
            project.updatedAt = Date()
            rebuildComposition()
            objectWillChange.send()
        }
    }

    func rebuildComposition() {
        guard let activeSequence = project.sequences.first(where: { $0.id == project.activeSequenceID }) else { return }
        playbackEngine.updateComposition(sequence: activeSequence, mediaAssets: project.mediaAssets)
    }
    
    // MARK: - Live Preview Helpers (Throttled)
    func transientUpdate(clipID: UUID, apply: (inout Clip) -> Void) {
        guard let seqIdx = project.sequences.firstIndex(where: { $0.id == project.activeSequenceID }) else { return }
        for tIdx in project.sequences[seqIdx].tracks.indices {
            if let cIdx = project.sequences[seqIdx].tracks[tIdx].clips.firstIndex(where: { $0.id == clipID }) {
                apply(&project.sequences[seqIdx].tracks[tIdx].clips[cIdx])
                
                // Throttle the heavy rebuild operation to max once per 150ms
                if Date().timeIntervalSince(lastRebuildTime) > 0.15 {
                    rebuildComposition()
                    lastRebuildTime = Date()
                }
                objectWillChange.send()
                return
            }
        }
    }

    func commitTransientUpdate() {
        rebuildComposition()
        lastRebuildTime = Date()
        objectWillChange.send()
    }

    // MARK: - Keyboard Shortcuts
    func handleJ() { playbackEngine.jklReverse() }
    func handleK() { playbackEngine.jklStop() }
    func handleL() { playbackEngine.jklForward() }
    func togglePlayPause() { playbackEngine.togglePlayPause() }
    
    func stepForward() {
        let fps = project.sequences.first(where: { $0.id == project.activeSequenceID })?.frameRate ?? 30.0
        playbackEngine.step(frames: 1, fps: fps)
    }
    
    func stepBackward() {
        let fps = project.sequences.first(where: { $0.id == project.activeSequenceID })?.frameRate ?? 30.0
        playbackEngine.step(frames: -1, fps: fps)
    }
    
    func splitAtPlayhead() {
        guard let clipID = selectedClipID else { return }
        let cmd = SplitClipAtTimeCommand(clipID: clipID, splitTime: currentTime)
        execute(cmd)
    }
    
    func deleteSelected() {
        guard let clipID = selectedClipID else { return }
        let cmd = DeleteClipCommand(clipID: clipID)
        execute(cmd)
        selectedClipID = nil
    }
    
    func markIn() { inMark = currentTime }
    func markOut() { outMark = currentTime }
    func zoomIn() { zoomScale = min(zoomScale * 1.5, 100.0) }
    func zoomOut() { zoomScale = max(zoomScale / 1.5, 5.0) }
}

