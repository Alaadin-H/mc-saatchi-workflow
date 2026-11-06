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

| A title is a clip whose content is its own data (no media) | `Title.swift`: `Clip.title`, drawn by `TitleRenderer`, presets |
| A transition belongs to the clip it leads into, centred on the cut | `Transition.swift`: `Clip.transitionIn`; neighbours alternate between two composition tracks (A/B) so both frames exist across the cut |

One command layer for UI, scripts and AI (Concat's API/MCP idea): the in-app **terminal**
(`AIAgentPanelView.swift`) runs any editor command directly, and sends plain-language requests
to Claude (`ClaudeAgent.swift`, Messages API over HTTPS) with every editor command as a tool.

Premiere Pro keyboard layout: `MainEditorView` (⌘/ shows the list), actions in `EditorActions.swift`.

## Next (roadmap)

1. **Clip kinds**: stills (photos), adjustment layers.
3. **Exact rational time** at the render boundary for 29.97/59.94 fps material.
4. **Auto-captions** with Apple's on-device Speech framework.
