# Remote controls (component)
> **What:** The pad of grey circles with power, the volume card and slider, and the transport keys. **Read when:** you change `MediaRemoteControls`.
- Mockup: [media-remote-controls.html](media-remote-controls.html) · status shipped · reviewed 2026-10-23
- Source: `HassUI/Features/MediaRemote/MediaRemoteControls.swift`, `HassCore/Config/MediaRemotes.swift` · Spec: `.agents/patterns/media-remote.md`, `.agents/design/direction-g.md` · Patterns: media-remote
- States covered: default, power on/off, pressed, disabled, keyboard, apple-tv + studio, ax5
- Motion: key press (quick), power colour (state)
- Devices: size classes via the Device control
- Open notes: Select and Home dots are footnote circle glyphs; shared helpers in `components/media/_media-lights-cameras.js` (promote to kit)
