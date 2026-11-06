import SwiftUI

struct TimelineView: View {
    @EnvironmentObject var editorState: EditorState
    @GestureState private var pinchScale: CGFloat = 1.0

    private var activeSequence: EditSequence? {
        editorState.project.sequences.first(where: { $0.id == editorState.project.activeSequenceID })
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Timeline", icon: "timeline.selection") {
                HStack(spacing: DS.Space.xs) {
                    IconButton(systemName: "minus.magnifyingglass", tint: DS.Palette.textSecondary, size: 28) { editorState.zoomOut() }
                    Slider(value: $editorState.zoomScale, in: 5...100)
                        .frame(width: 110)
                        .tint(DS.Palette.accent)
                    IconButton(systemName: "plus.magnifyingglass", tint: DS.Palette.textSecondary, size: 28) { editorState.zoomIn() }
                }
            }

            if let sequence = activeSequence {
                GeometryReader { geo in
                    let scale = max(5, editorState.zoomScale * pinchScale)
                    let total = TimelineEngine.calculateSequenceDuration(sequence: sequence)
                    let width = max(geo.size.width, TimelineEngine.secondsToPoints(seconds: total + 10, pointsPerSecond: scale))

                    // Visual order: highest video track on top, then audio
                    let videoTracks = Array(sequence.tracks.filter { $0.type == .video }.reversed())
                    let audioTracks = sequence.tracks.filter { $0.type == .audio }
                    let tracks = videoTracks + audioTracks
                    let tracksHeight = CGFloat(tracks.count) * (DS.Size.trackHeight + DS.Size.trackGap)
                    let _ = rememberViewport(geo.size.width)

                    ScrollView([.horizontal, .vertical]) {
                        ZStack(alignment: .topLeading) {
                            VStack(spacing: 0) {
                                TimeRuler(width: width, pointsPerSecond: scale)
                                    .contentShape(Rectangle())
                                    .gesture(
                                        DragGesture(minimumDistance: 0).onChanged { val in
                                            let t = TimelineEngine.pointsToSeconds(offset: val.location.x, pointsPerSecond: scale)
                                            editorState.playbackEngine.seek(to: max(0, t))
                                        }
                                    )

                                VStack(spacing: DS.Size.trackGap) {
                                    ForEach(tracks) { track in
                                        TrackRowView(track: track, pointsPerSecond: scale)
                                            .frame(width: width, height: DS.Size.trackHeight)
                                    }
                                }
                                .padding(.top, DS.Size.trackGap)
                            }

                            // In / out marks
                            ForEach([editorState.inMark, editorState.outMark].compactMap { $0 }, id: \.self) { mark in
                                Rectangle()
                                    .fill(Color.cyan)
                                    .frame(width: 2, height: DS.Size.rulerHeight)
                                    .offset(x: TimelineEngine.secondsToPoints(seconds: mark, pointsPerSecond: scale))
                            }

                            Playhead(height: DS.Size.rulerHeight + tracksHeight + DS.Size.trackGap)
                                .offset(x: TimelineEngine.secondsToPoints(seconds: editorState.currentTime, pointsPerSecond: scale) - 6)
                                .allowsHitTesting(false)
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
    }
}

extension TimelineView {
    /// Remembers the visible width for "zoom to fit" (no UI update needed).
    func rememberViewport(_ width: CGFloat) -> Bool {
        if abs(editorState.timelineViewportWidth - width) > 1 { editorState.timelineViewportWidth = width }
        return true
    }
}

// MARK: - Ruler

struct TimeRuler: View {
    let width: CGFloat
    let pointsPerSecond: CGFloat

    /// Seconds between labelled ticks, chosen so labels stay ~80pt apart.
    private var labelStep: Double {
        let steps: [Double] = [0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300]
        return steps.first { Double(pointsPerSecond) * $0 >= 80 } ?? 600
    }

    var body: some View {
        let step = labelStep
        let count = Int(Double(width) / (Double(pointsPerSecond) * step)) + 1

        ZStack(alignment: .topLeading) {
            DS.Palette.ruler
            ForEach(0..<count, id: \.self) { i in
                let t = Double(i) * step
                let x = CGFloat(t) * pointsPerSecond
                VStack(alignment: .leading, spacing: 1) {
                    Text(rulerLabel(t))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(DS.Palette.textTertiary)
                    Rectangle().fill(DS.Palette.strokeStrong).frame(width: 1, height: 6)
                }
                .offset(x: x + 3, y: 4)
                Rectangle().fill(DS.Palette.strokeStrong).frame(width: 1, height: DS.Size.rulerHeight).offset(x: x)
            }
        }
        .frame(width: width, height: DS.Size.rulerHeight)
        .overlay(alignment: .bottom) { Rectangle().fill(DS.Palette.stroke).frame(height: 1) }
    }

    private func rulerLabel(_ t: Double) -> String {
        let s = Int(t)
        if hasHalfSecond(t) { return String(format: "%d:%02d.5", s / 60, s % 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func hasHalfSecond(_ t: Double) -> Bool { t - Double(Int(t)) > 0.01 }
}

// MARK: - Playhead

struct Playhead: View {
    let height: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 11))
                .foregroundColor(DS.Palette.playhead)
                .frame(width: 12, height: 10)
            Rectangle()
                .fill(DS.Palette.playhead)
                .frame(width: 2, height: max(0, height - 10))
        }
        .shadow(color: DS.Palette.playhead.opacity(0.5), radius: 4)
    }
}

// MARK: - Track

struct TrackRowView: View {
    let track: Track
    let pointsPerSecond: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                .fill(DS.Palette.trackLane)

            HStack(spacing: 4) {
                Image(systemName: track.type == .video ? "video" : "speaker.wave.2")
                Text(track.name)
            }
            .font(DS.Typo.caption)
            .foregroundColor(DS.Palette.textTertiary)
            .padding(.leading, DS.Space.s)
            .padding(.top, 4)

            ForEach(track.clips) { clip in
                ClipItemView(clip: clip, track: track, pointsPerSecond: pointsPerSecond)
            }
        }
    }
}

// MARK: - Clip

struct ClipItemView: View {
    @EnvironmentObject var editorState: EditorState
    let clip: Clip
    let track: Track
    let pointsPerSecond: CGFloat

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        let width = max(TimelineEngine.secondsToPoints(seconds: clip.duration, pointsPerSecond: pointsPerSecond), 10)
        let baseOffset = TimelineEngine.secondsToPoints(seconds: clip.startTime, pointsPerSecond: pointsPerSecond)
        let isSelected = editorState.selectedClipID == clip.id
        let isVideo = track.type == .video
        let fill = clip.isTitle
            ? (isSelected ? DS.Palette.titleClipSelected : DS.Palette.titleClip)
            : isVideo
                ? (isSelected ? DS.Palette.videoClipSelected : DS.Palette.videoClip)
                : (isSelected ? DS.Palette.audioClipSelected : DS.Palette.audioClip)
        let transitionWidth = clip.transitionIn.map { min(width, CGFloat($0.duration / 2) * pointsPerSecond) } ?? 0

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                .fill(LinearGradient(colors: [fill, fill.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                        .stroke(isSelected ? Color.white : Color.white.opacity(0.12), lineWidth: isSelected ? 2 : 1)
                )

            if transitionWidth > 0 {
                // Transition marker at the clip's head
                Path { p in
                    p.move(to: .zero)
                    p.addLine(to: CGPoint(x: transitionWidth, y: 0))
                    p.addLine(to: CGPoint(x: 0, y: DS.Size.trackHeight))
                    p.closeSubpath()
                }
                .fill(DS.Palette.transition)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous))
            }

            HStack(spacing: 4) {
                if clip.isTitle {
                    Image(systemName: "textformat").font(.system(size: 9, weight: .bold))
                }
                if !(clip.effects ?? []).isEmpty {
                    Image(systemName: "wand.and.stars").font(.system(size: 8, weight: .bold))
                }
                Text(clip.name).font(DS.Typo.clip).lineLimit(1)
                Spacer(minLength: 0)
                if clip.playbackRate != 1 {
                    Text(String(format: "%.2gx", clip.playbackRate))
                        .font(.system(size: 9, weight: .heavy))
                        .padding(.horizontal, 4)
                        .background(Capsule().fill(Color.black.opacity(0.35)))
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.top, 5)
            .frame(width: width, alignment: .leading)

            if let anim = clip.animation {
                // Keyframe markers along the bottom of the clip
                let positions = Set(AnimatableProperty.allCases.flatMap { anim.keys(for: $0).map(\.at) }).sorted()
                ForEach(positions, id: \.self) { at in
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 7))
                        .foregroundColor(DS.Palette.keyframe)
                        .position(x: CGFloat(at) * width, y: DS.Size.trackHeight - 9)
                }
            }
        }
        .frame(width: width, height: DS.Size.trackHeight)
        .offset(x: baseOffset + dragOffset)
        .shadow(color: isSelected ? fill.opacity(0.5) : .clear, radius: 6)
        .onTapGesture { location in
            if editorState.activeTool == .blade {
                // Razor: cut where tapped
                let t = clip.startTime + Double(location.x / pointsPerSecond)
                editorState.razor(clip, at: t)
            } else {
                editorState.selectedClipID = clip.id
                editorState.selectedTrackID = track.id
            }
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
