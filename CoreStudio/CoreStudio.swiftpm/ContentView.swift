import SwiftUI

struct ContentView: View {
    @EnvironmentObject var editorState: EditorState

    var body: some View {
        MainEditorView()
            .onAppear {
                if let loaded = editorState.projectStorage.loadLatestProject() {
                    editorState.project = loaded
                }
                editorState.rebuildComposition()
            }
    }
}

