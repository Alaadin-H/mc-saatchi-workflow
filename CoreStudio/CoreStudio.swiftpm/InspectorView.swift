import SwiftUI

struct InspectorView: View {
    @EnvironmentObject var editorState: EditorState

    // The property being dragged right now, and its live value
    @State private var draggingProperty: AnimatableProperty?
    @State private var dragValue: Double = 0
    @State private var dragStartClip: Clip?

    @State private var draggingSpeed = false
    @State private var speedValue: Double = 1

    private var activeClip: Clip? {
        guard let id = editorState.selectedClipID else { return nil }
        return editorState.project.clip(id)
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text("Inspector").font(.subheadline).bold().padding([.top, .horizontal])

            if let clip = activeClip {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(clip.name).font(.caption).bold()
                        Text("◆ = keyframe at playhead").font(.caption2).foregroundColor(.gray)
                        Divider()

                        propertyRow(clip, .opacity, range: 0...1) { "\(Int($0 * 100))%" }
                        propertyRow(clip, .scale, range: 0.1...3) { String(format: "%.2f", $0) }
                        propertyRow(clip, .rotation, range: -180...180) { String(format: "%.0f°", $0) }
                        propertyRow(clip, .positionX, range: -1920...1920) { String(format: "%.0f", $0) }
                        propertyRow(clip, .positionY, range: -1080...1080) { String(format: "%.0f", $0) }

                        Divider()
                        speedRow(clip)

                        Divider()
                        Button(role: .destructive, action: {
                            editorState.execute(DeleteClipCommand(clipID: clip.id))
                            editorState.selectedClipID = nil
                        }) { Label("Delete Clip", systemImage: "trash").font(.caption) }
                    }
                    .padding()
                }
            } else {
                Spacer()
                Text("No Clip Selected").font(.caption).foregroundColor(.gray).frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .background(Color(UIColor.secondarySystemBackground))
    }

    // MARK: - Property row (slider + keyframe buttons)

    @ViewBuilder
    private func propertyRow(_ clip: Clip, _ property: AnimatableProperty, range: ClosedRange<Double>, format: @escaping (Double) -> String) -> some View {
        let animated = clip.isAnimated(property)
        let shown = draggingProperty == property ? dragValue : clip.value(of: property, atTimeline: editorState.currentTime)

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(property.title): \(format(shown))").font(.caption2)
                Spacer()
                Button {
                    editorState.addKeyframeAtPlayhead(clipID: clip.id, property: property)
                } label: {
                    Image(systemName: animated ? "diamond.fill" : "diamond")
                }
                .buttonStyle(.borderless)
                .foregroundColor(animated ? .yellow : .gray)

                if animated {
                    Button {
                        editorState.execute(ClearKeyframesCommand(clipID: clip.id, property: property))
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.gray)
                }
            }

            Slider(
                value: Binding(
                    get: { shown },
                    set: { newValue in
                        dragValue = newValue
                        // Live preview for static values. Animated values are committed as a keyframe on release.
                        if !animated {
                            editorState.transientUpdate(clipID: clip.id) { $0.setBaseValue(property, newValue) }
                        }
                    }
                ),
                in: range,
                onEditingChanged: { editing in
                    if editing {
                        draggingProperty = property
                        dragValue = shown
                        dragStartClip = clip
                    } else {
                        // Put the clip back as it was, then apply the change once, as one undo step
                        if let start = dragStartClip, !animated {
                            editorState.transientUpdate(clipID: clip.id) { $0 = start }
                        }
                        draggingProperty = nil
                        editorState.commitProperty(property, value: dragValue, clipID: clip.id)
                        editorState.commitTransientUpdate()
                    }
                }
            )
        }
    }

    // MARK: - Speed

    private func speedRow(_ clip: Clip) -> some View {
        let shown = draggingSpeed ? speedValue : clip.playbackRate

        return VStack(alignment: .leading, spacing: 6) {
            Text("Speed: \(String(format: "%.2fx", shown))  ·  \(String(format: "%.1fs", clip.sourceDuration / shown))")
                .font(.caption2)
            Slider(
                value: Binding(get: { shown }, set: { speedValue = $0 }),
                in: 0.25...4,
                onEditingChanged: { editing in
                    if editing {
                        draggingSpeed = true
                        speedValue = clip.playbackRate
                    } else {
                        draggingSpeed = false
                        editorState.execute(SetClipSpeedCommand(clipID: clip.id, speed: speedValue))
                    }
                }
            )
            HStack {
                ForEach([0.5, 1.0, 2.0], id: \.self) { s in
                    Button(String(format: "%.1fx", s)) {
                        editorState.execute(SetClipSpeedCommand(clipID: clip.id, speed: s))
                    }
                    .buttonStyle(.bordered)
                    .font(.caption2)
                }
            }
        }
    }
}
