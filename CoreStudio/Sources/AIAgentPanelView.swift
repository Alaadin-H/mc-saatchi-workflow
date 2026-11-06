import SwiftUI

struct AIAgentPanelView: View {
    @EnvironmentObject var editorState: EditorState
    var isTyping: FocusState<Bool>.Binding
    
    @State private var testCommandName: String = "moveClip"
    @State private var testCommandJSON: String = "{\n  \"clipID\": \"UUID-HERE\",\n  \"newStartTime\": 5.0\n}"
    @State private var executionResult: String = ""

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Image(systemName: "cpu").foregroundColor(.green)
                Text("AI Agent Tester").font(.subheadline).bold()
            }.padding([.top, .horizontal])
            
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Execute Command JSON").font(.caption).bold()
                        TextField("Command Name", text: $testCommandName)
                            .focused(isTyping)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        TextEditor(text: $testCommandJSON)
                            .focused(isTyping)
                            .frame(height: 100)
                            .font(.caption.monospacedDigit())
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray, lineWidth: 1))
                        
                        Button("Run Command") {
                            let res = editorState.executeFromJSON(name: testCommandName, argumentsJSON: testCommandJSON)
                            switch res {
                            case .success(let msg): executionResult = "✅ \(msg)"
                            case .failure(let err): executionResult = "❌ \(err.localizedDescription)"
                            }
                        }.buttonStyle(.borderedProminent)
                        
                        if !executionResult.isEmpty {
                            Text(executionResult).font(.caption).foregroundColor(.secondary).textSelection(.enabled)
                        }
                    }
                    .padding(.horizontal)
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Project State (getProjectState)").font(.caption).bold()
                        Button("Fetch Current State") {
                            let cmd = GetProjectStateCommand()
                            let res = cmd.execute(on: &editorState.project)
                            if case .success(let json) = res {
                                executionResult = json
                            }
                        }.buttonStyle(.bordered)
                    }
                    .padding(.horizontal)
                    
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Available Tool Schema").font(.caption).bold()
                        Text(editorState.commandRegistry.exportToolSchemas())
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.gray)
                            .textSelection(.enabled)
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
        }
        .background(Color(UIColor.tertiarySystemBackground))
    }
}

