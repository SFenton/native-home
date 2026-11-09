# Air purifier sheet (modal)
> **What:** the Air Quality sheet: Fan Mode, then Auto sub-mode or Manual speed, subtitle AQI and PM2.5. **Read when:** you change `AirPurifierSheet` or the room device sheet chrome.
- Mockup: [air-purifier-sheet.html](air-purifier-sheet.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/RoomDevices/AirPurifierSheet.swift, RoomDeviceSheetChrome.swift, HassUI/Common/SegmentedChoice.swift` (paths under `apple/Sources/` unless full) · Spec: `.agents/patterns/room-device-sheets.md` · Patterns: room-device-sheets, modal-sheet, option-picker
- States covered: Auto, Auto Quiet, Manual (Medium, Off), Sleep, unavailable, offline, medium, large, fitted, closed, ax5 (menus); loading noted as none
- Motion: none of its own (system segmented selection); transitions: present, dismiss, Auto to Manual section swap
- Devices: iPhone, Duo folded, Duo unfolded landscape, iPad portrait and landscape (form sheet)
- Open notes: no loading state; the room overview Air Quality chip opens the same sheet (room-overview batch)
