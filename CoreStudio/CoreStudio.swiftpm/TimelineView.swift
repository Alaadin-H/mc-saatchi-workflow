import SwiftUI

struct TimelineView: View {
    @EnvironmentObject var editorState: EditorState
    @GestureState private var pinchScale: CGFloat = 1.0

    private var activeSequence: EditSequence? {
        editorState.project.sequences.first(where: { $0.id == editorState.project.activeSequenceID })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Timeline").font(.caption).bold()
                Spacer()
                Slider(value: $editorState.zoomScale, in: 5...100).frame(width: 120)
            }
            .padding(.horizontal)
            .frame(height: 30)
            .background(Color(UIColor.tertiarySystemBackground))
            
            Divider()

            if let sequence = activeSequence {
                GeometryReader { geo in
                    let effectiveScale = max(5, editorState.zoomScale * pinchScale)
                    let totalDuration = TimelineEngine.calculateSequenceDuration(sequence: sequence)
                    let timelineWidth = max(geo.size.width, TimelineEngine.secondsToPoints(seconds: totalDuration + 10, pointsPerSecond: effectiveScale))

                    ScrollView([.horizontal, .vertical]) {
                        ZStack(alignment: .topLeading) {
                            // Ruler
                            Rectangle()
                                .fill(Color(UIColor.separator))
                                .frame(width: timelineWidth, height: 20)
                                .gesture(
                                    DragGesture(minimumDistance: 0).onChanged { val in
                                        let t = TimelineEngine.pointsToSeconds(offset: val.location.x, pointsPerSecond: effectiveScale)
                                        editorState.playbackEngine.seek(to: max(0, t))
                                    }
                                )
                                
                            // In & Out Marks
                            if let inMark = editorState.inMark {
                                Rectangle()
                                    .fill(Color.cyan)
                                    .frame(width: 2, height: 16)
                                    .offset(x: TimelineEngine.secondsToPoints(seconds: inMark, pointsPerSecond: effectiveScale), y: 2)
                            }
                            if let outMark = editorState.outMark {
                                Rectangle()
                                    .fill(Color.cyan)
                                    .frame(width: 2, height: 16)
                                    .offset(x: TimelineEngine.secondsToPoints(seconds: outMark, pointsPerSecond: effectiveScale), y: 2)
                            }
                            
                            // Visual track ordering: High video tracks on top (Video 2 > Video 1), then audio.
                            let videoTracks = sequence.tracks.filter({ $0.type == .video }).reversed()
                            let audioTracks = sequence.tracks.filter({ $0.type == .audio })
                            let sortedTracks = Array(videoTracks) + Array(audioTracks)
                            
                            VStack(spacing: 8) {
                                ForEach(sortedTracks) { track in
                                    TrackRowView(track: track, pointsPerSecond: effectiveScale)
                                        .frame(width: timelineWidth, height: 60)
                                }
                            }
                            .padding(.top, 20)

                            // Playhead
                            Rectangle()
                                .fill(Color.red)
                                .frame(width: 2, height: CGFloat(sequence.tracks.count * 68) + 20)
                                .offset(x: TimelineEngine.secondsToPoints(seconds: editorState.currentTime, pointsPerSecond: effectiveScale))
                        }
                        .gesture(
                            MagnifyGesture().updating($pinchScale) { value, state, _ in
                                state = value.magnification
                            }.onEnded { value in
                                editorState.zoomScale = max(5, min(editorState.zoomScale * value.magnification, 100))
                            }
                        )
                    }
                }
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
    }
}

struct TrackRowView: View {
    let track: Track
    let pointsPerSecond: CGFloat

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4).fill(Color(UIColor.secondarySystemGroupedBackground))
            
            Text(track.name)
                .font(.caption2)
                .bold()
                .foregroundColor(.gray)
                .padding(.leading, 4)
                .offset(y: -20)
            
            ForEach(track.clips) { clip in
                ClipItemView(clip: clip, trackID: track.id, pointsPerSecond: pointsPerSecond)
            }
        }
    }
}

struct ClipItemView: View {
    @EnvironmentObject var editorState: EditorState
    let clip: Clip
    let trackID: UUID
    let pointsPerSecond: CGFloat
    
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        let width = TimelineEngine.secondsToPoints(seconds: clip.duration, pointsPerSecond: pointsPerSecond)
        let baseOffset = TimelineEngine.secondsToPoints(seconds: clip.startTime, pointsPerSecond: pointsPerSecond)
        let isSelected = editorState.selectedClipID == clip.id

        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.blue.opacity(0.8) : Color.purple.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(isSelected ? Color.yellow : Color.clear, lineWidth: 2))

            Text(clip.name).font(.caption2).foregroundColor(.white).lineLimit(1).padding(.horizontal, 4)

            if let anim = clip.animation {
                // Keyframe markers along the bottom of the clip
                let positions = Set(AnimatableProperty.allCases.flatMap { anim.keys(for: $0).map(\.at) }).sorted()
                ForEach(positions, id: \.self) { at in
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 7))
                        .foregroundColor(.yellow)
                        .position(x: CGFloat(at) * max(width, 10), y: 46)
                }
            }
            if clip.playbackRate != 1 {
                Text(String(format: "%.2gx", clip.playbackRate))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.orange)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(3)
            }
        }
        .frame(width: max(width, 10), height: 52)
        .offset(x: baseOffset + dragOffset)
        .onTapGesture {
            editorState.selectedClipID = clip.id
            editorState.selectedTrackID = trackID
        }
        .gesture(
            DragGesture()
                .onChanged { val in dragOffset = val.translation.width }
                .onEnded { val in
                    let deltaSeconds = Double(val.translation.width / pointsPerSecond)
                    let cmd = MoveClipCommand(clipID: clip.id, newStartTime: editorState.snapToFrame(clip.startTime + deltaSeconds), newTrackID: nil)
                    editorState.execute(cmd)
                    dragOffset = 0
                }
        )
    }
}

