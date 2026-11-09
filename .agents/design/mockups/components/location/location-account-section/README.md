# Profile tab Location section (component)
> **What:** the Share Location row, its warnings and the footer on the Your Summary sheet's Profile tab; phones only. **Read when:** you change `LocationAccountSection` or the presence-link notices.
- Mockup: [location-account-section.html](location-account-section.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Location/LocationAccountSection.swift`, `LocationStatusRow.swift`, `LocationPermissionCopy.swift`, `apple/Sources/HassUI/Features/Settings/Profile/ProfileTab.swift`
- Spec: `.agents/pages/settings/location.md`, `.agents/platforms/apple/location.md` · Patterns: settings-section, modal-sheet
- States covered: not asked, Off and Approximate warnings; While Using and Always (none); needs administrator, no person, tracker missing, failed notices; AX5; light and dark
- Motion: none
- Devices: size classes only; hidden on iPad
- Open notes: no Report switch since 2026-10-20; cells are the kit's sheet card as a stand-in for the inset-grouped list
