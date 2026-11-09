# Wake alarm editor (modal)
> **What:** adds or edits one native wake alarm, pushed inside the Wake-Light sheet (type, name, days or date, time, ramp, enabled, beds, Save, Delete). **Read when:** you change `WakeLightEditor`, `ChoiceGrid` or the wake alarm save flow.
- Mockup: [wake-light-editor.html](wake-light-editor.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Bedroom/WakeLightEditor.swift` · Spec: .agents/patterns/bedroom-devices.md, schedule-date-fields.md · Patterns: bedroom-devices, schedule-date-fields, modal-sheet, option-picker
- States covered: default (add), edit, edit-changed, one-time, one-time-old, beds-on, problem, saving, stale, error, delete-confirm, unavailable, offline, large, ax5
- Motion: kind segment, day chip and ramp tile fills (state 0.6 s), enabled switch; push in, pop to root
- Devices: iPhone, Duo (folded, unfolded), iPad (portrait, landscape)
- Open notes: whole form dims while saving (review note)
