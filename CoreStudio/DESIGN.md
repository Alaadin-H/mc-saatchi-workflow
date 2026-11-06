# CoreStudio design notes

Ideas taken from studying [Concat](https://github.com/jub0t/Concat) (an open-source
Rust video editor). Concat is AGPL-3.0, so **no code was copied or translated**:
only the architecture ideas, re-implemented from scratch in Swift.

## Adopted (done)

| Concat idea | In CoreStudio |
|---|---|
| Undo = whole-project snapshots, not hand-written inverse operations | `CommandHistory.swift`. Commands only implement `execute`. |
| "Gesture" = many edits folded into one undo step | `execute(_:gesture:)` / `endGesture()` |
| Speed is ONE number on the clip; everything derives from it | `Clip.speed`, `duration` = source length / speed, split and render use it |
| Keyframes at *fractions* of the clip, eased by a cubic-bezier (CSS timing function) | `Animation.swift`, `SetKeyframeCommand`, Inspector ◆ buttons |
| Edits land on whole frames | `EditorState.snapToFrame` (split, timeline drag) |
| One command layer that the UI and AI agents both drive | `CommandRegistry` (+ `setClipSpeed`, `setKeyframe`, `clearKeyframes`) |

| Rendering split into a *plan* (what's on screen, no pixels) and a *compositor* (draws it) | `PlaybackEngine` builds `CompositionInstruction`s, `CoreStudioCompositor` draws each frame with Core Image (`FrameRenderer.swift`) |
| Effects are data, not code | `Effects.swift`: JSON catalogue of Core Image effects; clips store `{effectID, params, enabled}` |

Also: export (`ExportService.swift`) through the same compositor, and a design
system (`DesignSystem.swift`) that every screen uses.

## Next (roadmap)

1. **Clip kinds**: titles (text), stills, adjustment layers.
2. **Transitions** (cross dissolve, slide) in the compositor.
3. **Exact rational time** at the render boundary for 29.97/59.94 fps material.
4. **Auto-captions** with Apple's on-device Speech framework.
