import SwiftUI

struct ContentView: View {
    @EnvironmentObject var editorState: EditorState

    var body: some View {
        MainEditorView()
            .onAppear {
                CrashReporter.log("editor appeared")
                if let loaded = editorState.projectStorage.loadLatestProject() {
                    CrashReporter.log("loaded saved project")
                    editorState.project = loaded
                }
                editorState.rebuildComposition()
                CrashReporter.log("startup finished")
            }
    }
}
