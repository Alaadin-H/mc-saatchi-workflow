import SwiftUI

struct InspectorView: View {
    @EnvironmentObject var editorState: EditorState

    // The property being dragged right now, and its live value
    @State private var draggingProperty: AnimatableProperty?
    @State private var dragValue: Double = 0
    @State private var dragStartClip: Clip?

    @State private var draggingSpeed = false
    @State private var speedValue: Double = 1

    // Effect parameter being dragged: "<instance id>/<key>"
    @State private var draggingEffectParam: String?
    @State private var effectDragValue: Double = 0
    @State private var effectDragStart: Double = 0

    private var activeClip: Clip? {
        guard let id = editorState.selectedClipID else { return nil }
        return editorState.project.clip(id)
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Inspector", icon: "slider.horizontal.3")

            if let clip = activeClip {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.l) {
                        clipHeader(clip)

                        SectionCard(title: "Transform", icon: "move.3d") {
                            propertyRow(clip, .scale, range: 0.1...3) { String(format: "%.2f", $0) }
                            propertyRow(clip, .rotation, range: -180...180) { String(format: "%.0f°", $0) }
                            propertyRow(clip, .positionX, range: -1920...1920) { String(format: "%.0f", $0) }
                            propertyRow(clip, .positionY, range: -1080...1080) { String(format: "%.0f", $0) }
                        }

                        SectionCard(title: "Opacity", icon: "circle.lefthalf.filled") {
                            propertyRow(clip, .opacity, range: 0...1) { "\(Int($0 * 100))%" }
                        }

                        SectionCard(title: "Speed", icon: "speedometer") {
                            speedRow(clip)
                        }

                        effectsSection(clip)

                        Button(role: .destructive) {
                            editorState.execute(DeleteClipCommand(clipID: clip.id))
                            editorState.selectedClipID = nil
                        } label: {
                            Label("Delete Clip", systemImage: "trash").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(DSButtonStyle(kind: .danger))
                    }
                    .padding(DS.Space.m)
                }
            } else {
                EmptyState(icon: "cursorarrow.click", title: "No clip selected", message: "Tap a clip on the timeline to edit it")
            }
        }
    }

    // MARK: - Header

    private func clipHeader(_ clip: Clip) -> some View {
        HStack(spacing: DS.Space.s) {
            RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                .fill(DS.Palette.videoClip)
                .frame(width: 6, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(clip.name).font(DS.Typo.label).foregroundColor(DS.Palette.textPrimary).lineLimit(1)
                Text(String(format: "%.2fs  ·  starts %.2fs", clip.duration, clip.startTime))
                    .font(DS.Typo.caption).foregroundColor(DS.Palette.textTertiary)
            }
            Spacer(minLength: 0)
            if clip.playbackRate != 1 {
                Chip(text: String(format: "%.2gx", clip.playbackRate), color: .orange)
            }
        }
    }

    // MARK: - Property row (slider + keyframe buttons)

    @ViewBuilder
    private func propertyRow(_ clip: Clip, _ property: AnimatableProperty, range: ClosedRange<Double>, format: @escaping (Double) -> String) -> some View {
        let animated = clip.isAnimated(property)
        let shown = draggingProperty == property ? dragValue : clip.value(of: property, atTimeline: editorState.currentTime)

        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(spacing: DS.Space.xs) {
                Text(property.title).font(DS.Typo.label).foregroundColor(DS.Palette.textSecondary)
                Spacer()
                Text(format(shown)).font(DS.Typo.value).foregroundColor(DS.Palette.textPrimary)

                Button {
                    editorState.addKeyframeAtPlayhead(clipID: clip.id, property: property)
                } label: {
                    Image(systemName: animated ? "diamond.fill" : "diamond")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(PressableStyle())
                .foregroundColor(animated ? DS.Palette.keyframe : DS.Palette.textTertiary)

                if animated {
                    Button {
                        editorState.execute(ClearKeyframesCommand(clipID: clip.id, property: property))
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 18, height: 22)
                    }
                    .buttonStyle(PressableStyle())
                    .foregroundColor(DS.Palette.textTertiary)
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
            .tint(animated ? DS.Palette.keyframe : DS.Palette.accent)
        }
    }

    // MARK: - Speed

    private func speedRow(_ clip: Clip) -> some View {
        let shown = draggingSpeed ? speedValue : clip.playbackRate

        return VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack {
                Text("Speed").font(DS.Typo.label).foregroundColor(DS.Palette.textSecondary)
                Spacer()
                Text(String(format: "%.2fx  ·  %.1fs", shown, clip.sourceDuration / shown))
                    .font(DS.Typo.value).foregroundColor(DS.Palette.textPrimary)
            }
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
            .tint(DS.Palette.accent)
            HStack(spacing: DS.Space.xs) {
                ForEach([0.5, 1.0, 1.5, 2.0], id: \.self) { s in
                    Button(String(format: "%gx", s)) {
                        editorState.execute(SetClipSpeedCommand(clipID: clip.id, speed: s))
                    }
                    .buttonStyle(DSButtonStyle(kind: abs(clip.playbackRate - s) < 0.001 ? .primary : .secondary))
                }
            }
        }
    }

    // MARK: - Effects

    @ViewBuilder
    private func effectsSection(_ clip: Clip) -> some View {
        SectionCard(title: "Effects", icon: "wand.and.stars") {
            let applied = clip.effects ?? []
            if applied.isEmpty {
                Text("No effects on this clip").font(DS.Typo.caption).foregroundColor(DS.Palette.textTertiary)
            }
            ForEach(applied) { effect in
                effectCard(clip, effect)
            }

            Menu {
                ForEach(EffectCatalogue.categories, id: \.self) { category in
                    Section(category) {
                        ForEach(EffectCatalogue.all.filter { $0.category == category }) { def in
                            Button {
                                editorState.execute(AddEffectCommand(clipID: clip.id, effectID: def.id))
                            } label: {
                                Label(def.name, systemImage: def.icon)
                            }
                        }
                    }
                }
            } label: {
                Label("Add Effect", systemImage: "plus")
                    .font(DS.Typo.label)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Space.s - 1)
                    .foregroundColor(DS.Palette.accent)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous).fill(DS.Palette.accentSoft))
            }
        }
    }

    private func effectCard(_ clip: Clip, _ effect: AppliedEffect) -> some View {
        let def = EffectCatalogue.definition(effect.effectID)

        return VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack(spacing: DS.Space.s) {
                Image(systemName: def?.icon ?? "questionmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(effect.enabled ? DS.Palette.accent : DS.Palette.textTertiary)
                Text(def?.name ?? effect.effectID)
                    .font(DS.Typo.label)
                    .foregroundColor(effect.enabled ? DS.Palette.textPrimary : DS.Palette.textTertiary)
                Spacer()
                IconButton(systemName: effect.enabled ? "eye" : "eye.slash", tint: DS.Palette.textSecondary, size: 24) {
                    editorState.execute(UpdateEffectCommand(clipID: clip.id, instanceID: effect.id, enabled: !effect.enabled))
                }
                IconButton(systemName: "trash", tint: DS.Palette.textTertiary, size: 24) {
                    editorState.execute(RemoveEffectCommand(clipID: clip.id, instanceID: effect.id))
                }
            }

            if let def {
                ForEach(def.parameters) { param in
                    effectSlider(clip, effect, param)
                }
            }
        }
        .padding(DS.Space.s)
        .background(RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous).fill(DS.Palette.panel))
    }

    private func effectSlider(_ clip: Clip, _ effect: AppliedEffect, _ param: EffectParameter) -> some View {
        let key = "\(effect.id.uuidString)/\(param.key)"
        let stored = effect.params[param.key] ?? param.defaultValue
        let shown = draggingEffectParam == key ? effectDragValue : stored

        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(param.name).font(DS.Typo.caption).foregroundColor(DS.Palette.textSecondary)
                Spacer()
                Text(String(format: abs(param.max - param.min) > 20 ? "%.0f" : "%.2f", shown))
                    .font(DS.Typo.value).foregroundColor(DS.Palette.textPrimary)
            }
            Slider(
                value: Binding(
                    get: { shown },
                    set: { newValue in
                        effectDragValue = newValue
                        // Live preview while dragging
                        editorState.transientUpdate(clipID: clip.id) { c in
                            if let i = c.effects?.firstIndex(where: { $0.id == effect.id }) {
                                c.effects?[i].params[param.key] = newValue
                            }
                        }
                    }
                ),
                in: param.min...param.max,
                onEditingChanged: { editing in
                    if editing {
                        draggingEffectParam = key
                        effectDragValue = stored
                        effectDragStart = stored
                    } else {
                        // Restore, then commit once as a single undo step
                        editorState.transientUpdate(clipID: clip.id) { c in
                            if let i = c.effects?.firstIndex(where: { $0.id == effect.id }) {
                                c.effects?[i].params[param.key] = effectDragStart
                            }
                        }
                        draggingEffectParam = nil
                        editorState.execute(UpdateEffectCommand(clipID: clip.id, instanceID: effect.id,
                                                                parameter: param.key, value: effectDragValue))
                        editorState.commitTransientUpdate()
                    }
                }
            )
            .tint(DS.Palette.accent)
        }
    }
}
