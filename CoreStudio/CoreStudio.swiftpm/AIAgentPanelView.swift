import SwiftUI

/// The terminal: run editor commands directly, or ask Claude to edit for you.
struct AIAgentPanelView: View {
    @EnvironmentObject var editorState: EditorState
    var isTyping: FocusState<Bool>.Binding

    var body: some View {
        TerminalView(session: editorState.terminal, isTyping: isTyping)
    }
}

struct TerminalView: View {
    @ObservedObject var session: TerminalSession
    var isTyping: FocusState<Bool>.Binding
    @State private var input = ""
    @State private var history: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Terminal", icon: "terminal") {
                HStack(spacing: DS.Space.xs) {
                    if session.isBusy {
                        ProgressView().controlSize(.small).tint(DS.Palette.accent)
                        IconButton(systemName: "stop.fill", tint: DS.Palette.danger, size: 26) { session.cancel() }
                    }
                    Chip(text: session.hasKey ? "Claude ●" : "No key", color: session.hasKey ? DS.Palette.success : DS.Palette.textTertiary)
                    IconButton(systemName: "trash", tint: DS.Palette.textTertiary, size: 26) { session.submit("clear") }
                }
            }

            // Output
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(session.lines) { line in
                            lineView(line).id(line.id)
                        }
                    }
                    .padding(DS.Space.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: session.lines.count) { _, _ in
                    if let last = session.lines.last {
                        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            .background(Color.black.opacity(0.35))

            // Quick prompts
            if session.lines.count < 4 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Space.xs) {
                        ForEach(["help", "state", "add a title \"Hello\" at the start",
                                 "cut every clip in half and add cross dissolves"], id: \.self) { s in
                            Button(s) { run(s) }
                                .buttonStyle(DSButtonStyle())
                        }
                    }
                    .padding(.horizontal, DS.Space.s)
                    .padding(.vertical, DS.Space.xs)
                }
            }

            // Input
            HStack(spacing: DS.Space.s) {
                Text("›").font(.system(size: 15, weight: .bold, design: .monospaced)).foregroundColor(DS.Palette.accent)
                TextField(session.hasKey ? "Ask Claude, or type a command…" : "key sk-ant-…  (or `help`)", text: $input)
                    .focused(isTyping)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(DS.Palette.textPrimary)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { run(input) }
                    .submitLabel(.send)
                Button {
                    run(input)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(input.isEmpty ? DS.Palette.textTertiary : DS.Palette.accent)
                }
                .buttonStyle(PressableStyle())
                .disabled(input.isEmpty)
            }
            .padding(DS.Space.s)
            .background(DS.Palette.raised)
        }
    }

    private func run(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if !t.lowercased().hasPrefix("key ") { history.append(t) }
        input = ""
        session.submit(t)
    }

    @ViewBuilder
    private func lineView(_ line: TerminalLine) -> some View {
        switch line.kind {
        case .input:
            Text("› " + line.text)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(DS.Palette.accent)
                .textSelection(.enabled)
        case .claude:
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 10, weight: .bold)).foregroundColor(Color(hex: 0xD97757)).padding(.top, 2)
                Text(line.text)
                    .font(.system(size: 12))
                    .foregroundColor(DS.Palette.textPrimary)
                    .textSelection(.enabled)
            }
        case .tool:
            Text(line.text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(DS.Palette.textTertiary)
                .textSelection(.enabled)
        case .error:
            Text(line.text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(DS.Palette.danger)
                .textSelection(.enabled)
        case .info:
            Text(line.text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(DS.Palette.textSecondary)
                .textSelection(.enabled)
        case .output:
            Text(line.text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(DS.Palette.textPrimary.opacity(0.85))
                .textSelection(.enabled)
        }
    }
}
