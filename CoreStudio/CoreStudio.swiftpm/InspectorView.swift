import SwiftUI

struct InspectorView: View {
    @EnvironmentObject var editorState: EditorState

    @State private var dragStartTransform: ClipTransform?
    @State private var dragStartOpacity: Double?
    
    @State private var tempTransform: ClipTransform = ClipTransform()
    @State private var tempOpacity: Double = 1.0
    
    @State private var isDraggingScale = false
    @State private var isDraggingRotation = false
    @State private var isDraggingPosX = false
    @State private var isDraggingPosY = false
    @State private var isDraggingOpacity = false

    private var activeClip: Clip? {
        guard let id = editorState.selectedClipID, let seq = editorState.project.sequences.first(where: { $0.id == editorState.project.activeSequenceID }) else { return nil }
        for t in seq.tracks {
            if let c = t.clips.first(where: { $0.id == id }) { return c }
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text("Inspector").font(.subheadline).bold().padding([.top, .horizontal])

            if let clip = activeClip {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(clip.name).font(.caption).bold()
                        Divider()

                        // OPACITY
                        VStack(alignment: .leading) {
                            Text("Opacity: \(Int((isDraggingOpacity ? tempOpacity : clip.opacity) * 100))%").font(.caption2)
                            Slider(
                                value: Binding(
                                    get: { isDraggingOpacity ? tempOpacity : clip.opacity },
                                    set: { val in
                                        tempOpacity = val
                                        editorState.transientUpdate(clipID: clip.id) { $0.opacity = val }
                                    }
                                ),
                                in: 0...1,
                                onEditingChanged: { editing in
                                    if editing {
                                        isDraggingOpacity = true
                                        tempOpacity = clip.opacity
                                        dragStartOpacity = clip.opacity
                                    } else {
                                        isDraggingOpacity = false
                                        if let start = dragStartOpacity {
                                            editorState.transientUpdate(clipID: clip.id) { $0.opacity = start } // revert
                                        }
                                        editorState.execute(SetClipOpacityCommand(clipID: clip.id, opacity: tempOpacity))
                                        editorState.commitTransientUpdate()
                                    }
                                }
                            )
                        }
                        
                        Divider()

                        // SCALE
                        VStack(alignment: .leading) {
                            Text("Scale: \(String(format: "%.2f", isDraggingScale ? tempTransform.scaleX : clip.transform.scaleX))").font(.caption2)
                            Slider(
                                value: Binding(
                                    get: { isDraggingScale ? tempTransform.scaleX : clip.transform.scaleX },
                                    set: { val in
                                        tempTransform.scaleX = val; tempTransform.scaleY = val
                                        editorState.transientUpdate(clipID: clip.id) { $0.transform = tempTransform }
                                    }
                                ),
                                in: 0.1...3.0,
                                onEditingChanged: { handleTransformDrag($0, current: clip.transform, apply: { SetClipTransformCommand(clipID: clip.id, posX: nil, posY: nil, scale: tempTransform.scaleX, rotation: nil) }, clipID: clip.id) }
                            )
                        }
                        
                        // ROTATION
                        VStack(alignment: .leading) {
                            Text("Rotation: \(String(format: "%.0f°", isDraggingRotation ? tempTransform.rotationDegrees : clip.transform.rotationDegrees))").font(.caption2)
                            Slider(
                                value: Binding(
                                    get: { isDraggingRotation ? tempTransform.rotationDegrees : clip.transform.rotationDegrees },
                                    set: { val in
                                        tempTransform.rotationDegrees = val
                                        editorState.transientUpdate(clipID: clip.id) { $0.transform = tempTransform }
                                    }
                                ),
                                in: -180...180,
                                onEditingChanged: { handleTransformDrag($0, current: clip.transform, apply: { SetClipTransformCommand(clipID: clip.id, posX: nil, posY: nil, scale: nil, rotation: tempTransform.rotationDegrees) }, clipID: clip.id) }
                            )
                        }

                        // POSITION X
                        VStack(alignment: .leading) {
                            Text("Position X: \(String(format: "%.0f", isDraggingPosX ? tempTransform.positionX : clip.transform.positionX))").font(.caption2)
                            Slider(
                                value: Binding(
                                    get: { isDraggingPosX ? tempTransform.positionX : clip.transform.positionX },
                                    set: { val in
                                        tempTransform.positionX = val
                                        editorState.transientUpdate(clipID: clip.id) { $0.transform = tempTransform }
                                    }
                                ),
                                in: -1920...1920,
                                onEditingChanged: { handleTransformDrag($0, current: clip.transform, apply: { SetClipTransformCommand(clipID: clip.id, posX: tempTransform.positionX, posY: nil, scale: nil, rotation: nil) }, clipID: clip.id) }
                            )
                        }

                        // POSITION Y
                        VStack(alignment: .leading) {
                            Text("Position Y: \(String(format: "%.0f", isDraggingPosY ? tempTransform.positionY : clip.transform.positionY))").font(.caption2)
                            Slider(
                                value: Binding(
                                    get: { isDraggingPosY ? tempTransform.positionY : clip.transform.positionY },
                                    set: { val in
                                        tempTransform.positionY = val
                                        editorState.transientUpdate(clipID: clip.id) { $0.transform = tempTransform }
                                    }
                                ),
                                in: -1080...1080,
                                onEditingChanged: { handleTransformDrag($0, current: clip.transform, apply: { SetClipTransformCommand(clipID: clip.id, posX: nil, posY: tempTransform.positionY, scale: nil, rotation: nil) }, clipID: clip.id) }
                            )
                        }

                        Divider()
                        Button(role: .destructive, action: {
                            editorState.execute(DeleteClipCommand(clipID: clip.id))
                            editorState.selectedClipID = nil
                        }) { Label("Delete Clip", systemName: "trash").font(.caption) }
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
    
    private func handleTransformDrag(_ editing: Bool, current: ClipTransform, apply: @escaping () -> EditorCommand, clipID: UUID) {
        if editing {
            tempTransform = current
            dragStartTransform = current
            isDraggingScale = true // Generic toggle to allow active readout
            isDraggingRotation = true
            isDraggingPosX = true
            isDraggingPosY = true
        } else {
            isDraggingScale = false
            isDraggingRotation = false
            isDraggingPosX = false
            isDraggingPosY = false
            if let start = dragStartTransform {
                editorState.transientUpdate(clipID: clipID) { $0.transform = start } // revert
                editorState.execute(apply()) // apply via command
                editorState.commitTransientUpdate()
            }
        }
    }
}

