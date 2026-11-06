import SwiftUI
import AVKit

struct PreviewView: View {
    @EnvironmentObject var editorState: EditorState

    private var sequence: EditSequence? {
        editorState.project.sequences.first(where: { $0.id == editorState.project.activeSequenceID })
    }

    var body: some View {
        let seq = sequence
        let aspect = CGFloat(seq?.width ?? 16) / CGFloat(max(seq?.height ?? 9, 1))
        let fps = seq?.frameRate ?? 30
        let total = seq.map { TimelineEngine.calculateSequenceDuration(sequence: $0) } ?? 0

        VStack(spacing: 0) {
            PanelHeader(title: "Program", icon: "play.rectangle") {
                if let seq {
                    Chip(text: "\(seq.width)×\(seq.height)")
                }
            }

            // The frame, letterboxed to the sequence's aspect ratio
            ZStack {
                DS.Palette.canvas
                AVPlayerControllerRepresentable(player: editorState.playbackEngine.player)
                    .aspectRatio(aspect, contentMode: .fit)
                    .background(Color.black)
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(DS.Palette.stroke, lineWidth: 1))
            }
            .padding(DS.Space.s)

            // Transport
            HStack(spacing: DS.Space.s) {
                Text(formatTimecode(editorState.currentTime, fps: fps))
                    .font(DS.Typo.timecode)
                    .foregroundColor(DS.Palette.accent)
                    .frame(minWidth: 110, alignment: .leading)

                Spacer()

                IconButton(systemName: "backward.end.fill", tint: DS.Palette.textSecondary) {
                    editorState.playbackEngine.seek(to: 0)
                }
                IconButton(systemName: "backward.frame.fill", tint: DS.Palette.textSecondary) {
                    editorState.stepBackward()
                }
                Button {
                    editorState.togglePlayPause()
                } label: {
                    Image(systemName: editorState.playbackEngine.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(DS.Palette.accent))
                }
                .buttonStyle(PressableStyle())
                IconButton(systemName: "forward.frame.fill", tint: DS.Palette.textSecondary) {
                    editorState.stepForward()
                }
                IconButton(systemName: "forward.end.fill", tint: DS.Palette.textSecondary) {
                    editorState.playbackEngine.seek(to: total)
                }

                Spacer()

                Text(formatTimecode(total, fps: fps))
                    .font(DS.Typo.timecode)
                    .foregroundColor(DS.Palette.textTertiary)
                    .frame(minWidth: 110, alignment: .trailing)
            }
            .padding(.horizontal, DS.Space.m)
            .padding(.bottom, DS.Space.s)
        }
    }
}

struct AVPlayerControllerRepresentable: UIViewControllerRepresentable {
    let player: AVPlayer
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.view.backgroundColor = .black
        return controller
    }
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        // Only set the player when it changed (re-assigning every update can loop forever)
        if uiViewController.player !== player {
            uiViewController.player = player
        }
    }
}
