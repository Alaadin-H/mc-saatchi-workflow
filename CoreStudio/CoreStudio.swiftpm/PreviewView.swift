import SwiftUI
import AVKit

struct PreviewView: View {
    @EnvironmentObject var editorState: EditorState

    var body: some View {
        VStack {
            AVPlayerControllerRepresentable(player: editorState.playbackEngine.player)
                .background(Color.black)
                .cornerRadius(8)
                .padding()

            HStack(spacing: 20) {
                Button(action: {
                    editorState.playbackEngine.seek(to: 0)
                }) {
                    Image(systemName: "backward.end.fill")
                }

                Button(action: {
                    editorState.playbackEngine.togglePlayPause()
                }) {
                    Image(systemName: editorState.playbackEngine.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                }

                Text(String(format: "%.2f s", editorState.currentTime))
                    .font(.caption.monospacedDigit())
            }
            .padding(.bottom)
        }
    }
}

struct AVPlayerControllerRepresentable: UIViewControllerRepresentable {
    let player: AVPlayer
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        return controller
    }
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
    }
}

