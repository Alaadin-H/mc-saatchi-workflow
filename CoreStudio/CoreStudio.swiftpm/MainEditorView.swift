import SwiftUI

struct MainEditorView: View {
    @EnvironmentObject var editorState: EditorState
    @State private var showAgentPanel = false
    @FocusState private var isTyping: Bool
    
    @State private var selectedFormat: SequenceFormat = .widescreen16x9

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Group {
                    Button("") { editorState.togglePlayPause() }.keyboardShortcut(.space, modifiers: [])
                    Button("") { editorState.handleJ() }.keyboardShortcut("j", modifiers: [])
                    Button("") { editorState.handleK() }.keyboardShortcut("k", modifiers: [])
                    Button("") { editorState.handleL() }.keyboardShortcut("l", modifiers: [])
                    Button("") { editorState.stepBackward() }.keyboardShortcut(.leftArrow, modifiers: [])
                    Button("") { editorState.stepForward() }.keyboardShortcut(.rightArrow, modifiers: [])
                    Button("") { editorState.splitAtPlayhead() }.keyboardShortcut("c", modifiers: [])
                    Button("") { editorState.activeTool = .select }.keyboardShortcut("v", modifiers: [])
                    Button("") { editorState.deleteSelected() }.keyboardShortcut(.delete, modifiers: [])
                }
                .opacity(0)
                .disabled(isTyping)

                Group {
                    Button("") { editorState.undo() }.keyboardShortcut("z", modifiers: [.command])
                    Button("") { editorState.redo() }.keyboardShortcut("z", modifiers: [.command, .shift])
                    Button("") { editorState.zoomIn() }.keyboardShortcut("=", modifiers: [])
                    Button("") { editorState.zoomIn() }.keyboardShortcut("+", modifiers: [])
                    Button("") { editorState.zoomOut() }.keyboardShortcut("-", modifiers: [])
                    Button("") { editorState.markIn() }.keyboardShortcut("i", modifiers: [])
                    Button("") { editorState.markOut() }.keyboardShortcut("o", modifiers: [])
                }
                .opacity(0)
                .disabled(isTyping)

                VStack(spacing: 0) {
                    // Toolbar
                    HStack {
                        Text(editorState.project.name).font(.headline).padding(.leading)
                        Text(editorState.activeTool == .select ? "[V] Select" : "[C] Razor").font(.caption2).foregroundColor(.gray).padding(.leading, 12)

                        Spacer()
                        
                        Picker("Format", selection: $selectedFormat) {
                            ForEach(SequenceFormat.allCases, id: \.self) { format in
                                Text(format.rawValue).tag(format)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .onChange(of: selectedFormat) { newFormat in
                            guard let active = editorState.project.sequences.first(where: { $0.id == editorState.project.activeSequenceID }) else { return }
                            if Int(newFormat.size.width) != active.width || Int(newFormat.size.height) != active.height {
                                let cmd = SetSequenceFormatCommand(width: Int(newFormat.size.width), height: Int(newFormat.size.height))
                                editorState.execute(cmd)
                            }
                        }
                        .onReceive(editorState.$project) { proj in
                            // Sync picker state to active sequence without causing command loops
                            if let active = proj.sequences.first(where: { $0.id == proj.activeSequenceID }) {
                                let activeSize = CGSize(width: active.width, height: active.height)
                                if let matchingFormat = SequenceFormat.allCases.first(where: { $0.size == activeSize }), selectedFormat != matchingFormat {
                                    selectedFormat = matchingFormat
                                }
                            }
                        }

                        Button(action: { editorState.undo() }) { Image(systemName: "arrow.uturn.backward.circle") }
                            .disabled(!editorState.commandHistory.canUndo)
                            .padding(.horizontal, 4)

                        Button(action: { editorState.redo() }) { Image(systemName: "arrow.uturn.forward.circle") }
                            .disabled(!editorState.commandHistory.canRedo)
                            .padding(.trailing, 8)
                        
                        Button(action: { editorState.splitAtPlayhead() }) { Image(systemName: "scissors") }
                            .disabled(editorState.selectedClipID == nil)
                            .padding(.trailing, 8)

                        Button(action: { showAgentPanel.toggle() }) { Label("AI Agent", systemName: "cpu") }
                            .padding(.trailing)
                    }
                    .frame(height: 44)
                    .background(Color(UIColor.secondarySystemBackground))

                    Divider()

                    HStack(spacing: 0) {
                        MediaBinView()
                            .frame(width: geo.size.width * 0.25)
                        Divider()
                        PreviewView()
                            .frame(width: showAgentPanel ? geo.size.width * 0.35 : geo.size.width * 0.50)
                        Divider()

                        if showAgentPanel {
                            AIAgentPanelView(isTyping: $isTyping)
                                .frame(width: geo.size.width * 0.25)
                            Divider()
                        }

                        InspectorView()
                            .frame(width: geo.size.width * (showAgentPanel ? 0.15 : 0.25))
                    }
                    .frame(height: max(0, geo.size.height * 0.55))

                    Divider()
                    TimelineView()
                        .frame(height: max(0, geo.size.height * 0.45 - 44))
                }
            }
        }
    }
}

