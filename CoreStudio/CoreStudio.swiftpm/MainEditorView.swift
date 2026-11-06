import SwiftUI

struct MainEditorView: View {
    @EnvironmentObject var editorState: EditorState
    @State private var showAgentPanel = false
    @State private var showExport = false
    @FocusState private var isTyping: Bool
    @FocusState private var editorFocused: Bool

    @State private var selectedFormat: SequenceFormat = .widescreen16x9

    private let gap = DS.Space.s

    var body: some View {
        GeometryReader { geo in
            ZStack {
                keyboardShortcuts

                VStack(spacing: gap) {
                    toolbar

                    // Top row: media / preview / (agent) / inspector
                    let topHeight = max(0, (geo.size.height - DS.Size.toolbarHeight - gap * 3) * 0.56)
                    let available = max(0, geo.size.width - gap * 2)
                    HStack(spacing: gap) {
                        MediaBinView()
                            .frame(width: available * 0.22)
                            .dsPanel()

                        PreviewView()
                            .frame(maxWidth: .infinity)
                            .dsPanel()

                        if showAgentPanel {
                            AIAgentPanelView(isTyping: $isTyping)
                                .frame(width: available * 0.30)
                                .dsPanel()
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }

                        InspectorView(isTyping: $isTyping)
                            .frame(width: available * 0.24)
                            .dsPanel()
                    }
                    .frame(height: topHeight)

                    TimelineView()
                        .frame(maxHeight: .infinity)
                        .dsPanel()
                }
                .padding(.horizontal, gap)
                .padding(.bottom, gap)
            }
            .background(DS.Palette.canvas.ignoresSafeArea())
            // The whole editor takes keyboard focus so single-key shortcuts work
            .focusable()
            .focusEffectDisabled()
            .focused($editorFocused)
            .onKeyPress(phases: .down) { press in handleKey(press) }
            .onAppear { editorFocused = true }
            .onChange(of: isTyping) { _, typing in
                if !typing { editorFocused = true }
            }
        }
        .sheet(isPresented: $editorState.showShortcuts) {
            ShortcutsView()
        }
        .sheet(isPresented: $showExport) {
            ExportView()
                .environmentObject(editorState)
        }
        .onReceive(editorState.$project) { proj in
            // Keep the format menu in sync with the sequence (undo can change it)
            if let active = proj.sequences.first(where: { $0.id == proj.activeSequenceID }) {
                let activeSize = CGSize(width: active.width, height: active.height)
                if let match = SequenceFormat.allCases.first(where: { $0.size == activeSize }), selectedFormat != match {
                    selectedFormat = match
                }
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: DS.Space.m) {
            // Brand + project
            HStack(spacing: DS.Space.s) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(LinearGradient(colors: [DS.Palette.accent, Color(hex: 0xB04CFF)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 26, height: 26)
                    .overlay(Image(systemName: "film.stack").font(.system(size: 12, weight: .bold)).foregroundColor(.white))
                VStack(alignment: .leading, spacing: 0) {
                    Text("CoreStudio").font(DS.Typo.appTitle).foregroundColor(DS.Palette.textPrimary)
                    Text(editorState.project.name).font(DS.Typo.caption).foregroundColor(DS.Palette.textTertiary)
                }
            }

            Divider().frame(height: 22).overlay(DS.Palette.stroke)

            // Edit tools
            HStack(spacing: DS.Space.xs) {
                IconButton(systemName: "cursorarrow", isActive: editorState.activeTool == .select) { editorState.activeTool = .select }
                IconButton(systemName: "scissors", isActive: editorState.activeTool == .blade) { editorState.activeTool = .blade }
                IconButton(systemName: "rectangle.split.2x1") { editorState.addEdit(allTracks: false) }
                IconButton(systemName: "trash") { editorState.deleteSelected() }
                    .disabled(editorState.selectedClipID == nil)
                    .opacity(editorState.selectedClipID == nil ? 0.4 : 1)
            }

            Divider().frame(height: 22).overlay(DS.Palette.stroke)

            HStack(spacing: DS.Space.xs) {
                // Titles
                Menu {
                    ForEach(TitlePreset.all) { preset in
                        Button { editorState.addTitle(preset: preset.id) } label: { Label(preset.name, systemImage: preset.icon) }
                    }
                } label: {
                    Image(systemName: "textformat")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DS.Palette.textPrimary)
                        .frame(width: DS.Size.iconButton, height: DS.Size.iconButton)
                }
                // Transition on the selected clip
                IconButton(systemName: "square.on.square.dashed") { editorState.applyDefaultTransition() }
            }

            Divider().frame(height: 22).overlay(DS.Palette.stroke)

            HStack(spacing: DS.Space.xs) {
                IconButton(systemName: "arrow.uturn.backward") { editorState.undo() }
                    .disabled(!editorState.commandHistory.canUndo)
                    .opacity(editorState.commandHistory.canUndo ? 1 : 0.4)
                IconButton(systemName: "arrow.uturn.forward") { editorState.redo() }
                    .disabled(!editorState.commandHistory.canRedo)
                    .opacity(editorState.commandHistory.canRedo ? 1 : 0.4)
            }

            Spacer()

            // Sequence format
            Menu {
                Picker("Format", selection: $selectedFormat) {
                    ForEach(SequenceFormat.allCases, id: \.self) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
            } label: {
                HStack(spacing: DS.Space.xs) {
                    Image(systemName: "aspectratio").font(.system(size: 11, weight: .semibold))
                    Text(selectedFormat.rawValue).font(DS.Typo.label)
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                }
                .foregroundColor(DS.Palette.textPrimary)
                .padding(.horizontal, DS.Space.m)
                .padding(.vertical, DS.Space.s - 1)
                .background(RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous).fill(DS.Palette.raised))
            }
            .onChange(of: selectedFormat) { _, newFormat in
                guard let active = editorState.project.sequences.first(where: { $0.id == editorState.project.activeSequenceID }) else { return }
                if Int(newFormat.size.width) != active.width || Int(newFormat.size.height) != active.height {
                    editorState.execute(SetSequenceFormatCommand(width: Int(newFormat.size.width), height: Int(newFormat.size.height)))
                }
            }

            IconButton(systemName: "keyboard") { editorState.showShortcuts = true }

            IconButton(systemName: "terminal", isActive: showAgentPanel) { toggleTerminal() }

            Button {
                showExport = true
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(DSButtonStyle(kind: .primary))
        }
        .padding(.horizontal, DS.Space.m)
        .frame(height: DS.Size.toolbarHeight)
    }

    // MARK: - Keyboard shortcuts (Adobe Premiere Pro layout)
    // Hidden buttons; holding ⌘ on an iPad keyboard lists the ⌘ ones.

    private var keyboardShortcuts: some View {
        // ⌘ shortcuts: hidden buttons (iPadOS lists these when you hold ⌘).
        // Single keys (Space, J, K, L, arrows...) are handled in handleKey(_:).
        ZStack {
            Group {
                Button("Clear In and Out") { editorState.clearInOut() }.keyboardShortcut("x", modifiers: [.command, .shift])
                Button("Add Edit") { editorState.addEdit(allTracks: false) }.keyboardShortcut("k", modifiers: [.command])
                Button("Add Edit to All Tracks") { editorState.addEdit(allTracks: true) }.keyboardShortcut("k", modifiers: [.command, .shift])
                Button("Apply Video Transition") { editorState.applyDefaultTransition() }.keyboardShortcut("d", modifiers: [.command])
                Button("Copy") { editorState.copySelected() }.keyboardShortcut("c", modifiers: [.command])
                Button("Cut") { editorState.cutSelected() }.keyboardShortcut("x", modifiers: [.command])
                Button("Paste") { editorState.pasteAtPlayhead() }.keyboardShortcut("v", modifiers: [.command])
                Button("Undo") { editorState.undo() }.keyboardShortcut("z", modifiers: [.command])
                Button("Redo") { editorState.redo() }.keyboardShortcut("z", modifiers: [.command, .shift])
            }
            Group {
                Button("Save") { editorState.saveNow() }.keyboardShortcut("s", modifiers: [.command])
                Button("Export Media") { showExport = true }.keyboardShortcut("m", modifiers: [.command])
                Button("Export") { showExport = true }.keyboardShortcut("e", modifiers: [.command])
                Button("Terminal") { toggleTerminal() }.keyboardShortcut("j", modifiers: [.command])
                Button("Keyboard Shortcuts") { editorState.showShortcuts = true }.keyboardShortcut("/", modifiers: [.command])
            }
        }
        .opacity(0)
        .disabled(isTyping)
    }

    private func toggleTerminal() {
        withAnimation(.easeInOut(duration: 0.2)) { showAgentPanel.toggle() }
    }

    /// Single-key shortcuts, Premiere Pro layout.
    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        // Typing in a text field: let the field have the keys
        if isTyping { return .ignored }
        let mods = press.modifiers
        if mods.contains(.command) || mods.contains(.control) { return .ignored }
        let shift = mods.contains(.shift)
        let option = mods.contains(.option)
        let e = editorState

        switch press.key {
        case .space: e.togglePlayPause(); return .handled
        case .leftArrow: option ? e.nudgeSelected(frames: -1) : e.stepFrames(shift ? -5 : -1); return .handled
        case .rightArrow: option ? e.nudgeSelected(frames: 1) : e.stepFrames(shift ? 5 : 1); return .handled
        case .upArrow: e.goToEditPoint(next: false); return .handled
        case .downArrow: e.goToEditPoint(next: true); return .handled
        case .home: e.goToStart(); return .handled
        case .end: e.goToEnd(); return .handled
        case .delete, .deleteForward: shift ? e.rippleDeleteSelected() : e.deleteSelected(); return .handled
        default: break
        }

        switch press.characters.lowercased() {
        case "j": e.handleJ()
        case "k": e.handleK()
        case "l": e.handleL()
        case "i": shift ? e.goToIn() : e.markIn()
        case "o": shift ? e.goToOut() : e.markOut()
        case "v": e.activeTool = .select
        case "c": e.activeTool = .blade
        case "t": e.addTitle()
        case "q": e.rippleTrim(.start)
        case "w": e.rippleTrim(.end)
        case "=", "+": e.zoomIn()
        case "-", "_": e.zoomOut()
        case "\\": e.zoomToFit()
        default: return .ignored
        }
        return .handled
    }
}

// MARK: - Export sheet

struct ExportView: View {
    @EnvironmentObject var editorState: EditorState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var exporter = ExportService()
    @State private var quality: ExportService.Quality = .high
    @State private var showSaver = false

    private var sequence: EditSequence? {
        editorState.project.sequences.first(where: { $0.id == editorState.project.activeSequenceID })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            HStack {
                Text("Export").font(.system(size: 20, weight: .bold)).foregroundColor(DS.Palette.textPrimary)
                Spacer()
                IconButton(systemName: "xmark", tint: DS.Palette.textSecondary) {
                    exporter.cancel()
                    dismiss()
                }
            }

            SectionCard(title: "Settings", icon: "gearshape") {
                if let seq = sequence {
                    row("Resolution", "\(seq.width) × \(seq.height)")
                    row("Frame rate", String(format: "%.2f fps", seq.frameRate))
                    row("Duration", formatTimecode(TimelineEngine.calculateSequenceDuration(sequence: seq), fps: seq.frameRate))
                }
                row("Format", "QuickTime (.mov)")
                Picker("Quality", selection: $quality) {
                    ForEach(ExportService.Quality.allCases) { q in Text(q.rawValue).tag(q) }
                }
                .pickerStyle(.segmented)
            }

            statusView

            Spacer(minLength: 0)
        }
        .padding(DS.Space.xl)
        .background(DS.Palette.panel.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSaver) {
            if case .finished(let url) = exporter.state {
                ExportSaver(url: url)
            }
        }
        .onDisappear { if case .exporting = exporter.state { exporter.cancel() } }
    }

    @ViewBuilder
    private var statusView: some View {
        switch exporter.state {
        case .idle:
            Button {
                editorState.playbackEngine.player.pause()
                if let assets = editorState.playbackEngine.exportAssets() {
                    exporter.start(composition: assets.0, videoComposition: assets.1, name: editorState.project.name, quality: quality)
                }
            } label: {
                Label("Start Export", systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(DSButtonStyle(kind: .primary))

        case .exporting(let progress):
            VStack(alignment: .leading, spacing: DS.Space.s) {
                HStack {
                    Text("Exporting…").font(DS.Typo.label).foregroundColor(DS.Palette.textPrimary)
                    Spacer()
                    Text("\(Int(progress * 100))%").font(DS.Typo.value).foregroundColor(DS.Palette.textSecondary)
                }
                ProgressView(value: progress).tint(DS.Palette.accent)
                Button("Cancel") { exporter.cancel() }.buttonStyle(DSButtonStyle(kind: .danger))
            }

        case .finished:
            VStack(alignment: .leading, spacing: DS.Space.s) {
                Label("Export complete", systemImage: "checkmark.circle.fill")
                    .font(DS.Typo.label)
                    .foregroundColor(DS.Palette.success)
                Button {
                    showSaver = true
                } label: {
                    Label("Save to Files", systemImage: "folder").frame(maxWidth: .infinity)
                }
                .buttonStyle(DSButtonStyle(kind: .primary))
                Text("Tip: from the Files app you can share the video or save it to Photos.")
                    .font(DS.Typo.caption).foregroundColor(DS.Palette.textTertiary)
            }

        case .failed(let message):
            VStack(alignment: .leading, spacing: DS.Space.s) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(DS.Typo.label)
                    .foregroundColor(DS.Palette.danger)
                Button("Try again") { exporter.state = .idle }.buttonStyle(DSButtonStyle())
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(DS.Typo.label).foregroundColor(DS.Palette.textSecondary)
            Spacer()
            Text(value).font(DS.Typo.value).foregroundColor(DS.Palette.textPrimary)
        }
    }
}

// MARK: - Shortcuts sheet

struct ShortcutsView: View {
    @Environment(\.dismiss) private var dismiss

    private let sections: [(String, [(String, String)])] = [
        ("Playback", [("Space", "Play / Pause"), ("J  K  L", "Shuttle back / stop / forward (press again = faster)"),
                      ("← →", "Back / forward 1 frame"), ("⇧ ← →", "Back / forward 5 frames"),
                      ("↑ ↓", "Previous / next edit point"), ("Home  End", "Start / end of sequence")]),
        ("Marking", [("I  O", "Mark In / Out"), ("⇧I  ⇧O", "Go to In / Out"), ("⌘⇧X", "Clear In and Out")]),
        ("Tools", [("V", "Selection tool"), ("C", "Razor tool (tap a clip to cut it)"), ("T", "Add title at playhead")]),
        ("Editing", [("⌘K", "Add edit (cut at playhead)"), ("⌘⇧K", "Add edit to all tracks"),
                     ("Q", "Ripple trim start to playhead"), ("W", "Ripple trim end to playhead"),
                     ("Delete", "Delete clip"), ("⇧ Delete", "Ripple delete"),
                     ("⌥ ← →", "Nudge clip 1 frame"), ("⌘D", "Apply Cross Dissolve"),
                     ("⌘C  ⌘X  ⌘V", "Copy / cut / paste at playhead"), ("⌘Z  ⌘⇧Z", "Undo / redo")]),
        ("View & File", [("=  −", "Zoom timeline in / out"), ("\\", "Zoom to sequence"),
                         ("⌘S", "Save"), ("⌘M", "Export media"), ("⌘J", "Terminal / Claude"), ("⌘/", "This list")])
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            HStack {
                Text("Keyboard Shortcuts").font(.system(size: 20, weight: .bold)).foregroundColor(DS.Palette.textPrimary)
                Chip(text: "Premiere Pro", color: DS.Palette.accent)
                Spacer()
                IconButton(systemName: "xmark", tint: DS.Palette.textSecondary) { dismiss() }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    ForEach(sections, id: \.0) { section in
                        SectionCard(title: section.0) {
                            ForEach(section.1, id: \.0) { item in
                                HStack(alignment: .firstTextBaseline) {
                                    Text(item.0)
                                        .font(DS.Typo.value)
                                        .foregroundColor(DS.Palette.textPrimary)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(RoundedRectangle(cornerRadius: 4).fill(DS.Palette.panel))
                                        .frame(width: 120, alignment: .leading)
                                    Text(item.1).font(DS.Typo.label).foregroundColor(DS.Palette.textSecondary)
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(DS.Space.xl)
        .background(DS.Palette.panel.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}
