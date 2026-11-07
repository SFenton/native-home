# Allow Photos Access (alert)
> **What:** The system alert when Snapshot meets denied Photos access: Open Settings or Cancel. **Read when:** you change `CameraControls` or its alert copy.
- Mockup: [camera-photos-denied-alert.html](camera-photos-denied-alert.html) · status shipped · reviewed 2026-10-23
- Source: `HassUI/Features/Cameras/CameraViewer.swift` · Spec: `.agents/design/direction-g.md` · Patterns: modal-sheet
- States covered: default, ax5 over the dark viewer
- Motion: none of its own (system alert fade); transitions: present, Open Settings
- Devices: iPhone, Duo folded, Duo unfolded landscape, iPad portrait and landscape
- Open notes: the message says "Allow Home"; the app is S+H (fix the copy); medium, large and fitted do not apply; shared helpers in `components/media/_media-lights-cameras.js` (promote to kit)
