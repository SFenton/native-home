# Camera controls (component)
> **What:** Snapshot, Sound and Record circles with labels under the video, always dark. **Read when:** you change `CameraControlButton`.
- Mockup: [camera-controls.html](camera-controls.html) · status shipped · reviewed 2026-10-23
- Source: `HassUI/Features/Cameras/CameraViewer.swift` · Spec: `.agents/design/direction-g.md`, `.agents/design/motion-components.md` · Patterns: camera-streams
- States covered: idle, snapshot (saving, saved, not saved), sound, record, vertical, no-record, ax5
- Motion: saving pulse, record pulse (live pending states)
- Devices: size classes via the Device control
- Open notes: circles are sheet cells, not glass; shared helpers in `components/media/_media-lights-cameras.js` (promote to kit)
