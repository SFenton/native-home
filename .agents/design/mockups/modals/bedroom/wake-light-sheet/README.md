# Wake light sheet (modal)
> **What:** the Bedroom 1's Wake-Light Alarms sheet: Wake Alarms (schedule, mirrored bed alarms, Stop Wake-Light Episode) and Defaults (ramp, hold). **Read when:** you change `WakeLightSheet`, the wake-light contract copy or the Open Linked-Device Alarm Editor hand-off.
- Mockup: [wake-light-sheet.html](wake-light-sheet.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Bedroom/WakeLightSheet.swift`, `apple/Sources/HassUI/Features/Bedroom/WakeLightDefaultsTab.swift`, `apple/Sources/HassUI/Features/Bedroom/BedroomComponents.swift` · Spec: .agents/patterns/bedroom-devices.md, modal-sheet.md · Patterns: bedroom-devices, modal-sheet, entity-tile, motion
- States covered: default, waking, stopping, defaults (+ old integration), read-only, blocked, vacation, none-enabled, empty, unavailable, incompatible, error, offline, large, ax5; dark and light
- Motion: tab cut, ramp tile fill (state 0.6 s), alarm switch, brightness text; present, dismiss, push editor, hand-off to the bed sheet
- Devices: iPhone, Duo (folded, unfolded), iPad (portrait, landscape)
- Open notes: nativeRow uses onTapGesture (review: fix)
