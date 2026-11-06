import SwiftUI

struct InspectorView: View {
    @EnvironmentObject var editorState: EditorState
    /// True while typing, so single-key shortcuts (J, K, L...) don't fire
    var isTyping: FocusState<Bool>.Binding

    @State private var titleSizeDrag: Double?
    @State private var transitionDurationDrag: Double?

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

                        if let style = clip.title {
                            titleSection(clip, style)
                        }

                        transitionSection(clip)

                        SectionCard(title: "Transform", icon: "move.3d") {
                            propertyRow(clip, .scale, range: 0.1...3) { String(format: "%.2f", $0) }
                            propertyRow(clip, .rotation, range: -180...180) { String(format: "%.0f°", $0) }
                            propertyRow(clip, .positionX, range: -1920...1920) { String(format: "%.0f", $0) }
                            propertyRow(clip, .positionY, range: -1080...1080) { String(format: "%.0f", $0) }
                        }

                        SectionCard(title: "Opacity", icon: "circle.lefthalf.filled") {
                            propertyRow(clip, .opacity, range: 0...1) { "\(Int($0 * 100))%" }
                        }

                        if !clip.isTitle {
                            SectionCard(title: "Speed", icon: "speedometer") {
                                speedRow(clip)
                            }
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
                .fill(clip.isTitle ? DS.Palette.titleClip : DS.Palette.videoClip)
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

    // MARK: - Title

    private func updateTitle(_ clip: Clip, gesture: String? = nil, _ change: (inout TitleStyle) -> Void) {
        guard var style = clip.title else { return }
        change(&style)
        editorState.execute(UpdateTitleCommand(clipID: clip.id, style: style), gesture: gesture)
    }

    private func titleSection(_ clip: Clip, _ style: TitleStyle) -> some View {
        SectionCard(title: "Text", icon: "textformat") {
            TextField("Title text", text: Binding(
                get: { style.text },
                set: { newText in updateTitle(clip, gesture: "title-text-\(clip.id)") { $0.text = newText } }
            ), axis: .vertical)
            .focused(isTyping)
            .lineLimit(1...4)
            .font(DS.Typo.label)
            .foregroundColor(DS.Palette.textPrimary)
            .padding(DS.Space.s)
            .background(RoundedRectangle(cornerRadius: DS.Radius.s).fill(DS.Palette.panel))

            HStack {
                Picker("Font", selection: Binding(get: { style.font }, set: { v in updateTitle(clip) { $0.font = v } })) {
                    ForEach(TitleStyle.fonts, id: \.self) { Text($0.capitalized).tag($0) }
                }
                .pickerStyle(.menu)
                Spacer()
                Picker("Weight", selection: Binding(get: { style.weight }, set: { v in updateTitle(clip) { $0.weight = v } })) {
                    ForEach(TitleStyle.weights, id: \.self) { Text($0.capitalized).tag($0) }
                }
                .pickerStyle(.menu)
            }
            .tint(DS.Palette.textPrimary)

            Picker("Align", selection: Binding(get: { style.alignment }, set: { v in updateTitle(clip) { $0.alignment = v } })) {
                Image(systemName: "text.alignleft").tag("left")
                Image(systemName: "text.aligncenter").tag("center")
                Image(systemName: "text.alignright").tag("right")
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: DS.Space.xs) {
                HStack {
                    Text("Size").font(DS.Typo.label).foregroundColor(DS.Palette.textSecondary)
                    Spacer()
                    Text(String(format: "%.0f", titleSizeDrag ?? style.size)).font(DS.Typo.value).foregroundColor(DS.Palette.textPrimary)
                }
                Slider(value: Binding(get: { titleSizeDrag ?? style.size }, set: { titleSizeDrag = $0 }),
                       in: 20...300,
                       onEditingChanged: { editing in
                           if !editing, let v = titleSizeDrag {
                               updateTitle(clip) { $0.size = v }
                               titleSizeDrag = nil
                           }
                       })
                .tint(DS.Palette.accent)
            }

            colorRow("Color", hex: style.color) { hex in updateTitle(clip, gesture: "title-color-\(clip.id)") { $0.color = hex } }

            Toggle(isOn: Binding(get: { style.shadow }, set: { v in updateTitle(clip) { $0.shadow = v } })) {
                Text("Shadow").font(DS.Typo.label).foregroundColor(DS.Palette.textSecondary)
            }
            .tint(DS.Palette.accent)

            Toggle(isOn: Binding(get: { style.background }, set: { v in updateTitle(clip) { $0.background = v } })) {
                Text("Background").font(DS.Typo.label).foregroundColor(DS.Palette.textSecondary)
            }
            .tint(DS.Palette.accent)
            if style.background {
                colorRow("Background color", hex: style.backgroundColor) { hex in
                    updateTitle(clip, gesture: "title-bg-\(clip.id)") { $0.backgroundColor = hex }
                }
            }

            HStack {
                Text("Outline").font(DS.Typo.label).foregroundColor(DS.Palette.textSecondary)
                Spacer()
                Stepper(value: Binding(get: { style.stroke }, set: { v in updateTitle(clip, gesture: "title-stroke-\(clip.id)") { $0.stroke = v } }),
                        in: 0...20, step: 2) {
                    Text(style.stroke == 0 ? "Off" : String(format: "%.0f px", style.stroke))
                        .font(DS.Typo.value).foregroundColor(DS.Palette.textPrimary)
                }
                .fixedSize()
            }
            if style.stroke > 0 {
                colorRow("Outline color", hex: style.strokeColor) { hex in
                    updateTitle(clip, gesture: "title-strokecolor-\(clip.id)") { $0.strokeColor = hex }
                }
            }
        }
    }

    private func colorRow(_ title: String, hex: String, onChange: @escaping (String) -> Void) -> some View {
        ColorPicker(selection: Binding(
            get: { Color(UIColor(hexString: hex)) },
            set: { onChange(UIColor($0).hexString) }
        ), supportsOpacity: false) {
            Text(title).font(DS.Typo.label).foregroundColor(DS.Palette.textSecondary)
        }
    }

    // MARK: - Transition

    private func transitionSection(_ clip: Clip) -> some View {
        SectionCard(title: "Transition In", icon: "square.on.square.dashed") {
            Menu {
                Button("None") { editorState.execute(SetTransitionCommand(clipID: clip.id, transition: nil)) }
                ForEach(TransitionKind.all) { kind in
                    Button {
                        let duration = clip.transitionIn?.duration ?? ClipTransition.defaultDuration
                        editorState.execute(SetTransitionCommand(clipID: clip.id, transition: ClipTransition(type: kind.id, duration: duration)))
                    } label: {
                        Label(kind.name, systemImage: kind.icon)
                    }
                }
            } label: {
                HStack {
                    Image(systemName: clip.transitionIn.flatMap { TransitionKind.named($0.type)?.icon } ?? "minus")
                    Text(clip.transitionIn.flatMap { TransitionKind.named($0.type)?.name } ?? "None")
                        .font(DS.Typo.label)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold))
                }
                .foregroundColor(DS.Palette.textPrimary)
                .padding(DS.Space.s)
                .background(RoundedRectangle(cornerRadius: DS.Radius.s).fill(DS.Palette.panel))
            }

            if let transition = clip.transitionIn {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    HStack {
                        Text("Duration").font(DS.Typo.label).foregroundColor(DS.Palette.textSecondary)
                        Spacer()
                        Text(String(format: "%.2fs", transitionDurationDrag ?? transition.duration))
                            .font(DS.Typo.value).foregroundColor(DS.Palette.textPrimary)
                    }
                    Slider(value: Binding(get: { transitionDurationDrag ?? transition.duration }, set: { transitionDurationDrag = $0 }),
                           in: 0.1...3,
                           onEditingChanged: { editing in
                               if !editing, let v = transitionDurationDrag {
                                   editorState.execute(SetTransitionCommand(clipID: clip.id, transition: ClipTransition(type: transition.type, duration: v)))
                                   transitionDurationDrag = nil
                               }
                           })
                    .tint(DS.Palette.accent)
                }
                Text("Blends from the clip right before this one; with nothing before, it fades in.")
                    .font(DS.Typo.caption).foregroundColor(DS.Palette.textTertiary)
            }
        }
    }
}
