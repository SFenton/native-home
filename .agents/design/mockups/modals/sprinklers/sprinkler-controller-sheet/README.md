# Sprinkler controller sheet (modal)

> **What:** the controller sheet over Sprinklers: status pills, zones, Stop Watering, switches and programs. **Read when:** you change the sheet or its pushes.

- Mockup: [sprinkler-controller-sheet.html](sprinkler-controller-sheet.html) · shipped · reviewed 2026-10-23 (author self-check; skill reviewers replace it)
- Source: `apple/Sources/HassUI/Features/Sprinklers/SprinklersScreen.swift`, `SprinklerControllerSheet.swift`, `apple/Sources/HassCore/Sprinklers/SprinklerFormat.swift`
- Spec: `.agents/pages/sprinklers/spec.md`, `ios.md` · Patterns: modal-sheet, status-pill, optimistic-actions
- States covered: default, watering, battery low, rain delay, mode off, fault, error, unavailable, loading (= unavailable), offline, large, both pushed pages, closed, AX5; dark and light.
- Motion: zone watering colour, switch, Stop Watering colour; sheet present and dismiss, push to Water Now and the schedule editor.
- Devices: iPhone, Duo folded, Duo unfolded portrait and landscape, iPad portrait and landscape (page sheet 704 pt on iPad).
- Open note: Only the large detent ships (hassSheet(.page, height: .full)); medium and fitted do not exist.
- Open note: Programs always exist per zone in code, unlike the source comment; the program rows' lack of a chevron is not confirmed on a device.
