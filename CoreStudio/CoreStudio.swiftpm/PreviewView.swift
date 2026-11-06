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
                PlayerSurface(player: editorState.playbackEngine.player)
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

/// Plain video surface (an AVPlayerLayer). Unlike AVPlayerViewController it never
/// takes keyboard focus, so Space / arrows / J K L reach our shortcuts.
final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

struct PlayerSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.backgroundColor = .black
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: PlayerLayerView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }
}
