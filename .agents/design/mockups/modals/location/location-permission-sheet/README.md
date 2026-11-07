# Location permission, stages (modal)
> **What:** the explainer that asks for location and shows its status, in all six stages; always dark, a full-height page sheet, phones only. **Read when:** you change `LocationPermissionView`, its copy or pre-alert rules.
- Mockup: [location-permission-sheet.html](location-permission-sheet.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Location/` (LocationPermissionSheet, LocationPermissionView, LocationPermissionCopy, LocationStatusRow, LocationPointRow, LocationPermissionColors), `App/Location/LocationPermissionPresenter.swift`
- Spec: `.agents/pages/settings/location.md`, `.agents/platforms/apple/location.md` · Patterns: modal-sheet
- States covered: not asked, While Using, While Using (Always alert already shown), Always, Off, Approximate, large (what ships), closed (Home behind), AX5; loading, error, offline, medium and fitted are explained in notes
- Motion: none inside; transitions present, dismiss, and the in-place swap when the permission changes
- Devices: iPhone, Duo folded, Duo unfolded (page sheet); never iPad (no LocationCoordinator)
- Open notes: asking stages drop Close and swipe-dismiss (HIG Privacy beats the modal pattern, a departure); status cell colour unverified; the 2026-10-14 gallery still shows a Report toggle the code removed
