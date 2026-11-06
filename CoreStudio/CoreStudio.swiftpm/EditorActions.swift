import Foundation
import CoreGraphics

/// Editing actions used by the toolbar and the Premiere-style keyboard shortcuts.
extension EditorState {
    var activeSequence: EditSequence? {
        project.sequences.first(where: { $0.id == project.activeSequenceID })
    }

    var sequenceDuration: Double {
        activeSequence.map { TimelineEngine.calculateSequenceDuration(sequence: $0) } ?? 0
    }

    // MARK: Navigation

    func seek(_ time: Double) {
        let t = max(0, time)
        currentTime = t
        playbackEngine.seek(to: t)
    }

    func stepFrames(_ frames: Int) {
        playbackEngine.player.pause()
        seek(snapToFrame(currentTime + Double(frames) / frameRate))
    }

    func goToStart() { seek(0) }
    func goToEnd() { seek(sequenceDuration) }

    /// Up / Down arrow: previous / next cut on any track.
    func goToEditPoint(next: Bool) {
        guard let seq = activeSequence else { return }
        var points = Set<Double>([0])
        for track in seq.tracks { for c in track.clips { points.insert(c.startTime); points.insert(c.endTime) } }
        let sorted = points.sorted()
        let eps = 0.5 / frameRate
        if next {
            if let t = sorted.first(where: { $0 > currentTime + eps }) { seek(t) }
        } else {
            if let t = sorted.last(where: { $0 < currentTime - eps }) { seek(t) }
        }
    }

    func goToIn() { if let t = inMark { seek(t) } }
    func goToOut() { if let t = outMark { seek(t) } }
    func clearInOut() { inMark = nil; outMark = nil }

    // MARK: Finding clips

    /// Clips under the playhead, top video track first, then audio.
    func clipsUnderPlayhead() -> [Clip] {
        guard let seq = activeSequence else { return [] }
        let t = currentTime
        let video = seq.tracks.filter { $0.type == .video }.reversed()
        let audio = seq.tracks.filter { $0.type == .audio }
        return (Array(video) + audio).compactMap { track in
            track.clips.first { t > $0.startTime + 0.001 && t < $0.endTime - 0.001 }
        }
    }

    /// The selected clip if the playhead is on it, else the top clip under the playhead.
    func targetClip() -> Clip? {
        let under = clipsUnderPlayhead()
        if let id = selectedClipID, let c = under.first(where: { $0.id == id }) { return c }
        return under.first
    }

    private func trackID(of clipID: UUID) -> UUID? {
        activeSequence?.tracks.first(where: { $0.clips.contains { $0.id == clipID } })?.id
    }

    // MARK: Edits

    /// Cmd+K: add edit (split) at the playhead. allTracks = Shift+Cmd+K.
    func addEdit(allTracks: Bool) {
        let time = snapToFrame(currentTime)
        let targets = allTracks ? clipsUnderPlayhead() : targetClip().map { [$0] } ?? []
        guard !targets.isEmpty else { return }
        let gesture = "add-edit-\(UUID().uuidString)" // all splits = one undo step
        for clip in targets {
            execute(SplitClipAtTimeCommand(clipID: clip.id, splitTime: time), gesture: gesture)
        }
        commandHistory.endGesture()
    }

    /// Razor tool: split the clip where it was tapped.
    func razor(_ clip: Clip, at time: Double) {
        execute(SplitClipAtTimeCommand(clipID: clip.id, splitTime: snapToFrame(time)))
    }

    /// Shift+Delete
    func rippleDeleteSelected() {
        guard let id = selectedClipID else { return }
        execute(RippleDeleteCommand(clipID: id))
        selectedClipID = nil
    }

    /// Q (start) / W (end): ripple trim the clip under the playhead to the playhead.
    func rippleTrim(_ edge: RippleTrimCommand.Edge) {
        guard let clip = targetClip() else { return }
        execute(RippleTrimCommand(clipID: clip.id, edge: edge, time: snapToFrame(currentTime)))
        if edge == .start { seek(clip.startTime) }
    }

    /// Option + Left/Right: move the selected clip by frames.
    func nudgeSelected(frames: Int) {
        guard let id = selectedClipID, let clip = project.clip(id) else { return }
        let start = max(0, clip.startTime + Double(frames) / frameRate)
        execute(MoveClipCommand(clipID: id, newStartTime: snapToFrame(start), newTrackID: nil), gesture: "nudge-\(id)")
    }

    // MARK: Clipboard

    func copySelected() {
        guard let id = selectedClipID else { return }
        clipboard = project.clip(id)
    }

    func cutSelected() {
        copySelected()
        deleteSelected()
    }

    func pasteAtPlayhead() {
        guard let clip = clipboard else { return }
        let command = PasteClipCommand(clip: clip, startTime: snapToFrame(currentTime),
                                       preferredTrack: selectedTrackID ?? trackID(of: clip.id))
        execute(command)
        if let id = command.createdClipID { selectedClipID = id }
    }

    // MARK: Titles & transitions

    /// T: add a title at the playhead and select it.
    func addTitle(preset: String = "basic") {
        let command = AddTitleCommand(presetID: preset, startTime: snapToFrame(currentTime))
        execute(command)
        if let id = command.createdClipID {
            selectedClipID = id
            selectedTrackID = trackID(of: id)
        }
    }

    /// Cmd+D: default transition (Cross Dissolve) on the selected clip, or on the
    /// clip whose start is nearest the playhead.
    func applyDefaultTransition() {
        var target: Clip?
        if let id = selectedClipID { target = project.clip(id) }
        if target == nil, let seq = activeSequence {
            let all = seq.tracks.filter { $0.type == .video }.flatMap(\.clips)
            target = all.min(by: { abs($0.startTime - currentTime) < abs($1.startTime - currentTime) })
        }
        guard let clip = target else { return }
        execute(SetTransitionCommand(clipID: clip.id, transition: ClipTransition(type: "crossDissolve", duration: ClipTransition.defaultDuration)))
        selectedClipID = clip.id
    }

    // MARK: View

    /// Backslash: fit the whole sequence in the timeline.
    func zoomToFit() {
        let total = max(sequenceDuration, 1)
        zoomScale = min(max((timelineViewportWidth - 40) / CGFloat(total), 5), 100)
    }

    func saveNow() {
        projectStorage.saveProject(project)
    }
}
