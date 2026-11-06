import SwiftUI
import Combine

@main
struct CoreStudioApp: App {
    init() {
        CrashReporter.install()
        CrashReporter.log("app launch")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
    }
}

/// Safe mode: if the previous run crashed, show the crash report FIRST,
/// without creating the editor (so a crash at startup can't hide the report).
struct RootView: View {
    @State private var crashReport: String? = CrashReporter.reportFromPreviousSession()

    var body: some View {
        if let report = crashReport {
            CrashReportView(report: report) {
                CrashReporter.log("user continued past crash report")
                crashReport = nil
            }
        } else {
            EditorRootView()
        }
    }
}

struct EditorRootView: View {
    @StateObject private var editorState: EditorState = {
        CrashReporter.log("EditorState init start")
        let state = EditorState()
        CrashReporter.log("EditorState init done")
        return state
    }()

    var body: some View {
        ContentView()
            .environmentObject(editorState)
    }
}

struct CrashReportView: View {
    let report: String
    let onContinue: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(report)
                    .font(.system(size: 13, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("Last run crashed — screenshot this")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Open editor", action: onContinue)
                }
            }
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
    @Published var showShortcuts = false

    /// Copied clip (Cmd+C)
    var clipboard: Clip?
    /// The terminal (and Claude conversation); kept here so it survives closing the panel
    lazy var terminal = TerminalSession(editor: self)
    /// Visible width of the timeline, for "zoom to fit"
    var timelineViewportWidth: CGFloat = 800

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
        commandRegistry.registerAnimationCommands()
        commandRegistry.registerEffectCommands()
        commandRegistry.registerEditingCommands()
        
        playbackEngine.onTimeChanged = { [weak self] time in
            // FIX: ignore invalid/unchanged times so we don't re-render the whole UI for nothing
            guard let self, time.isFinite, abs(time - self.currentTime) > 0.0001 else { return }
            self.currentTime = time
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

    func execute(_ command: EditorCommand, gesture: String? = nil) {
        CrashReporter.log("execute \(type(of: command))")
        let result = commandHistory.execute(command, on: &project, gesture: gesture)
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
        playbackEngine.updateComposition(sequence: activeSequence, mediaAssets: project.mediaAssets, resumeAt: currentTime)
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
    func togglePlayPause() { CrashReporter.log("play/pause"); playbackEngine.togglePlayPause() }
    
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
        let cmd = SplitClipAtTimeCommand(clipID: clipID, splitTime: snapToFrame(currentTime))
        execute(cmd)
    }
    
    func deleteSelected() {
        guard let clipID = selectedClipID else { return }
        let cmd = DeleteClipCommand(clipID: clipID)
        execute(cmd)
        selectedClipID = nil
    }
    
    // MARK: - Frames, properties, keyframes

    var frameRate: Double {
        project.sequences.first(where: { $0.id == project.activeSequenceID })?.frameRate ?? 30.0
    }

    /// Edits land on whole frames, so cuts never fall between two frames.
    func snapToFrame(_ t: Double) -> Double {
        let fps = frameRate
        guard fps > 0 else { return t }
        return max(0, (t * fps).rounded() / fps)
    }

    /// Commits a property change from the Inspector: a keyframe at the playhead
    /// if the property is animated, otherwise its static value.
    func commitProperty(_ property: AnimatableProperty, value: Double, clipID: UUID) {
        guard let clip = project.clip(clipID) else { return }
        if clip.isAnimated(property) {
            execute(SetKeyframeCommand(clipID: clipID, property: property, timelineTime: currentTime, value: value))
        } else {
            execute(SetClipPropertyCommand(clipID: clipID, property: property, value: value))
        }
    }

    /// The diamond button: records the value currently shown at the playhead as a keyframe.
    func addKeyframeAtPlayhead(clipID: UUID, property: AnimatableProperty) {
        guard let clip = project.clip(clipID) else { return }
        let value = clip.value(of: property, atTimeline: currentTime)
        execute(SetKeyframeCommand(clipID: clipID, property: property, timelineTime: snapToFrame(currentTime), value: value))
    }

    func markIn() { inMark = currentTime }
    func markOut() { outMark = currentTime }
    func zoomIn() { zoomScale = min(zoomScale * 1.5, 100.0) }
    func zoomOut() { zoomScale = max(zoomScale / 1.5, 5.0) }
}

