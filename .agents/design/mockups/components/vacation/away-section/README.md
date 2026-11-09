# Away section, section grid, action button, notice box (component)

> **What:** the building blocks of the Vacation Mode and Solo Trip pages. **Read when:** you change AwaySection, its grid, its buttons or notices.

- Mockup: [away-section.html](away-section.html) · shipped · reviewed 2026-10-23 (author self-check; skill reviewers replace it)
- Source: `apple/Sources/HassUI/Features/Vacation/VacationComponents.swift`, `AwayActionButton.swift`, `SoloTripNoticeBox.swift`
- Spec: `.agents/pages/vacation/ios.md` · Patterns: settings-section, info-box, dynamic-grid
- States covered: section (title and description), description only, three buttons plus disabled, two notices, error alert, grid one and two columns; page and sheet surface.
- Motion: none.
- Devices: iPhone and iPad size classes.
- Open note: Sheet-surface style is legacy; Settings is a tab now.
- Open note: Bundled as the local AwayParts registration.
