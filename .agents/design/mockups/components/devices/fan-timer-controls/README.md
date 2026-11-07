# Fan timer controls (segments, length, progress) (component)
> **What:** the fan sheet timer parts: length row, start button, running countdown, progress bar, Clear Timer. **Read when:** you change the `FanTimer*` views or `TintedCapsuleButtonStyle`.
- Mockup: [fan-timer-controls.html](fan-timer-controls.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/RoomDevices/FanTimerPicker.swift, FanTimerSegment.swift, FanTimerLengthRow.swift, FanTimerProgressBar.swift, FanTimerRunning.swift` (paths under `apple/Sources/` unless full) · Spec: `.agents/patterns/room-device-sheets.md` · Patterns: room-device-sheets
- States covered: picker (30m, 1h, 5m, disabled), length row, running (full, 84%, last seconds, over an hour, unavailable), parts, ax5
- Motion: countdown tick (no animation)
- Devices: compact and regular width (sheet surface, light and dark)
- Open notes: the length row is a custom six-segment control (departure); no kit component yet
