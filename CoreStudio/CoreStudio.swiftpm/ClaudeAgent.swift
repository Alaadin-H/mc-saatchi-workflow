import Foundation
import Security

// MARK: - Claude inside CoreStudio
//
// The terminal talks to Claude through the Messages API (raw HTTPS, there is no
// official Swift SDK). Claude gets every editor command as a tool - the same
// CommandRegistry the UI uses - and runs a tool-use loop: it reads the project
// with getProjectState, then cuts, titles, adds effects... until the task is done.

// MARK: API key (stored in the iPad's Keychain, never in the project)

enum APIKeyStore {
    private static let service = "CoreStudio.AnthropicAPIKey"
    private static let account = "default"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func load() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }

    @discardableResult
    static func save(_ key: String) -> Bool {
        delete()
        var q = query
        q[kSecValueData as String] = Data(key.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: Running a tool against the editor

extension EditorState {
    /// Runs one editor command by name. Used by the terminal and by Claude.
    /// `gesture` folds several commands into one undo step.
    func runTool(name: String, input: [String: Any], gesture: String? = nil) -> (output: String, isError: Bool) {
        do {
            let command = try commandRegistry.makeCommand(name: name, arguments: input)
            switch commandHistory.execute(command, on: &project, gesture: gesture) {
            case .success(let summary):
                if command.isMutating {
                    project.updatedAt = Date()
                    rebuildComposition()
                    objectWillChange.send()
                }
                if name == "getProjectState" {
                    let selected = selectedClipID?.uuidString ?? "none"
                    return (summary + "\nplayhead: \(String(format: "%.3f", currentTime))s, selectedClipID: \(selected)", false)
                }
                return (summary, false)
            case .failure(let error):
                return (error.localizedDescription, true)
            }
        } catch {
            return (error.localizedDescription, true)
        }
    }

    /// The editor commands as Messages API tool definitions.
    func claudeTools() -> [[String: Any]] {
        commandRegistry.getAllDefinitions()
            .filter { $0.name != "importMedia" } // needs a file Claude can't provide
            .map { def in
                var properties: [String: Any] = [:]
                var required: [String] = []
                for p in def.parameters {
                    properties[p.name] = ["type": p.type, "description": p.description]
                    if p.isRequired { required.append(p.name) }
                }
                return [
                    "name": def.name,
                    "description": def.description,
                    "input_schema": ["type": "object", "properties": properties, "required": required] as [String: Any]
                ]
            }
    }
}

// MARK: Terminal session

struct TerminalLine: Identifiable {
    enum Kind { case input, output, error, tool, claude, info }
    let id = UUID()
    let kind: Kind
    let text: String
}

final class TerminalSession: ObservableObject {
    @Published var lines: [TerminalLine] = []
    @Published var isBusy = false
    @Published var hasKey = APIKeyStore.load() != nil

    weak var editor: EditorState?
    /// The conversation with Claude (kept exactly as the API returned it).
    private var messages: [[String: Any]] = []
    private var task: Task<Void, Never>?

    static let model = "claude-opus-5-5"
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let maxSteps = 30

    init(editor: EditorState?) {
        self.editor = editor
        print(.info, "CoreStudio terminal. Type `help` for commands, or just ask Claude in plain words.")
        if !hasKey { print(.info, "Set your Anthropic API key with:  key sk-ant-...") }
    }

    func print(_ kind: TerminalLine.Kind, _ text: String) {
        lines.append(TerminalLine(kind: kind, text: text))
        if lines.count > 600 { lines.removeFirst(lines.count - 600) }
    }

    // MARK: Input

    func submit(_ raw: String) {
        let input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        let isSecret = input.lowercased().hasPrefix("key ")
        print(.input, isSecret ? "key ••••••••" : input)

        let parts = input.split(separator: " ", maxSplits: 1).map(String.init)
        let word = parts[0]
        let rest = parts.count > 1 ? parts[1] : ""

        switch word.lowercased() {
        case "help": showHelp()
        case "clear": lines.removeAll()
        case "new": messages.removeAll(); print(.info, "Started a new conversation with Claude.")
        case "stop": cancel()
        case "undo": editor?.undo(); print(.output, "Undone.")
        case "redo": editor?.redo(); print(.output, "Redone.")
        case "commands": listCommands()
        case "state": runDirect("getProjectState", "")
        case "key": setKey(rest)
        default:
            if let editor, editor.commandRegistry.getAllDefinitions().contains(where: { $0.name == word }) {
                runDirect(word, rest)
            } else {
                ask(input)
            }
        }
    }

    private func showHelp() {
        print(.info, """
        Ask Claude anything in plain words, e.g.
          cut the clip at 5 seconds and add a cross dissolve
          add a title "Welcome" at the start for 3 seconds
          make the second clip black and white and twice as fast

        Terminal commands:
          state              project as JSON (what Claude sees)
          commands           list every editor command
          <command> {json}   run one, e.g.  setClipSpeed {"clipID":"…","speed":2}
          <command> k=v …    same, e.g.  addTitle text="Hi" startTime=0
          undo / redo        undo or redo the last step
          new                start a new conversation with Claude
          stop               stop Claude
          key sk-ant-…       save your Anthropic API key (Keychain)
          key clear          remove the saved key
          clear              clear the screen
        """)
    }

    private func listCommands() {
        guard let editor else { return }
        for def in editor.commandRegistry.getAllDefinitions() {
            let params = def.parameters.map { $0.isRequired ? $0.name : "[\($0.name)]" }.joined(separator: " ")
            print(.output, "\(def.name) \(params)\n   \(def.description)")
        }
    }

    private func setKey(_ value: String) {
        let key = value.trimmingCharacters(in: .whitespaces)
        if key.lowercased() == "clear" {
            APIKeyStore.delete()
            hasKey = false
            print(.output, "API key removed.")
            return
        }
        guard key.hasPrefix("sk-") else {
            print(.error, "That doesn't look like an Anthropic API key (it starts with sk-ant-).")
            return
        }
        hasKey = APIKeyStore.save(key)
        print(hasKey ? .output : .error, hasKey ? "API key saved in the Keychain." : "Could not save the key.")
    }

    // MARK: Direct commands

    private func runDirect(_ name: String, _ argText: String) {
        guard let editor else { return }
        let args: [String: Any]
        do {
            args = try Self.parseArguments(argText)
        } catch {
            print(.error, error.localizedDescription)
            return
        }
        let result = editor.runTool(name: name, input: args)
        print(result.isError ? .error : .output, result.output)
    }

    /// `{json}` or `key=value key2="text with spaces"`
    static func parseArguments(_ text: String) throws -> [String: Any] {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return [:] }
        if t.hasPrefix("{") {
            guard let data = t.data(using: .utf8),
                  let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw EditorError.general("Arguments must be a JSON object.")
            }
            return dict
        }
        var result: [String: Any] = [:]
        var i = t.startIndex
        while i < t.endIndex {
            while i < t.endIndex, t[i] == " " { i = t.index(after: i) }
            guard i < t.endIndex else { break }
            guard let eq = t[i...].firstIndex(of: "=") else { throw EditorError.general("Expected key=value near \"\(t[i...])\"") }
            let key = String(t[i..<eq])
            var j = t.index(after: eq)
            var value = ""
            if j < t.endIndex, t[j] == "\"" {
                j = t.index(after: j)
                guard let close = t[j...].firstIndex(of: "\"") else { throw EditorError.general("Missing closing quote for \(key)") }
                value = String(t[j..<close])
                i = t.index(after: close)
                result[key] = value
                continue
            }
            let end = t[j...].firstIndex(of: " ") ?? t.endIndex
            value = String(t[j..<end])
            i = end
            if let d = Double(value) { result[key] = d }
            else if value == "true" || value == "false" { result[key] = value == "true" }
            else { result[key] = value }
        }
        return result
    }

    // MARK: Claude

    func cancel() {
        task?.cancel()
        task = nil
        isBusy = false
        print(.info, "Stopped.")
    }

    private func ask(_ text: String) {
        guard let key = APIKeyStore.load() else {
            print(.error, "No API key yet. Get one at console.anthropic.com, then type:  key sk-ant-...")
            return
        }
        guard !isBusy else {
            print(.error, "Claude is still working. Type `stop` to stop it.")
            return
        }
        guard let editor else { return }

        let checkpoint = messages.count
        messages.append(["role": "user", "content": text])
        isBusy = true
        let tools = editor.claudeTools()
        let gesture = "claude-\(UUID().uuidString)" // the whole answer = one undo step

        task = Task { [weak self] in
            guard let self else { return }
            do {
                var steps = 0
                while steps < Self.maxSteps {
                    steps += 1
                    try Task.checkCancellation()
                    let response = try await self.send(key: key, tools: tools)
                    let content = response["content"] as? [[String: Any]] ?? []
                    let stop = response["stop_reason"] as? String ?? ""

                    // Keep the assistant turn exactly as returned (thinking blocks included)
                    await MainActor.run {
                        self.messages.append(["role": "assistant", "content": content])
                        for block in content where block["type"] as? String == "text" {
                            if let t = block["text"] as? String, !t.isEmpty { self.print(.claude, t) }
                        }
                    }

                    if stop == "refusal" {
                        await MainActor.run { self.print(.error, "Claude declined this request.") }
                        break
                    }
                    if stop == "max_tokens" {
                        await MainActor.run { self.print(.error, "The answer was cut off (too long).") }
                        break
                    }
                    guard stop == "tool_use" else { break }

                    // Run every tool call, then send all results back in one message
                    var results: [[String: Any]] = []
                    for block in content where block["type"] as? String == "tool_use" {
                        guard let id = block["id"] as? String, let name = block["name"] as? String else { continue }
                        let input = block["input"] as? [String: Any] ?? [:]
                        let result: (output: String, isError: Bool) = await MainActor.run {
                            let r = editor.runTool(name: name, input: input, gesture: gesture)
                            let shown = r.output.count > 160 ? String(r.output.prefix(160)) + "…" : r.output
                            self.print(r.isError ? .error : .tool, "⚙︎ \(name) → \(shown)")
                            return r
                        }
                        var item: [String: Any] = ["type": "tool_result", "tool_use_id": id, "content": result.output]
                        if result.isError { item["is_error"] = true }
                        results.append(item)
                    }
                    await MainActor.run { self.messages.append(["role": "user", "content": results]) }
                    if steps == Self.maxSteps {
                        await MainActor.run { self.print(.info, "Stopped after \(Self.maxSteps) steps. Say “continue” to go on.") }
                    }
                }
            } catch is CancellationError {
                await MainActor.run { self.rollBack(to: checkpoint) }
            } catch {
                await MainActor.run {
                    self.print(.error, error.localizedDescription)
                    self.rollBack(to: checkpoint)
                }
            }
            await MainActor.run {
                editor.commandHistory.endGesture()
                self.isBusy = false
                self.task = nil
            }
        }
    }

    /// After a failed request, drop this turn so the conversation stays valid
    /// (edits Claude already made stay; undo removes them).
    private func rollBack(to checkpoint: Int) {
        if messages.count > checkpoint { messages.removeSubrange(checkpoint...) }
    }

    private func send(key: String, tools: [[String: Any]]) async throws -> [String: Any] {
        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": 16000,
            "system": Self.systemPrompt,
            "tools": tools,
            "messages": messages,
            "output_config": ["effort": "medium"],
            // If a safety classifier declines, the API retries on a fallback model by itself
            "fallbacks": "default"
        ]
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let error = json["error"] as? [String: Any]
            let message = error?["message"] as? String ?? String(data: data, encoding: .utf8) ?? "Unknown error"
            switch status {
            case 401: throw EditorError.general("API key rejected (401). Check it with:  key sk-ant-...")
            case 429: throw EditorError.general("Rate limited (429). Wait a moment and try again.")
            case 529, 500...599: throw EditorError.general("Claude is busy right now (\(status)). Try again shortly.")
            default: throw EditorError.general("API error \(status): \(message)")
            }
        }
        return json
    }

    static let systemPrompt = """
    You are the editing assistant built into CoreStudio, a video editor for iPad. You edit the \
    user's timeline by calling the editor's tools; every tool call changes their real project.

    How the project works:
    - Times are seconds on the timeline. Positions are pixels from the frame's center (positive Y \
    is down), scale is a multiplier, rotation is degrees, opacity is 0 to 1.
    - Video tracks stack: higher tracks draw on top. Titles are clips on video tracks.
    - A transition belongs to the clip it leads INTO and blends from the clip right before it.
    - Effects are added by catalogue id (listEffects), then tuned with setEffectParameter.

    Before editing, call getProjectState to see the tracks, clips and their ids; call it again \
    after a series of edits if you need fresh ids or times. Prefer a few precise edits over many \
    speculative ones. If the request is ambiguous in a way that changes the result, ask one short \
    question instead of guessing. Everything you do in one answer can be undone with a single undo.

    When you're done, say in one or two sentences what you changed. Reply in the user's language \
    (Arabic or English), briefly - the terminal is small.
    """
}
