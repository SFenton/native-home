# Settings version row

> **What:** Settings → About → Version: where the build identity shows and what tapping it does, chosen 2026-10-26. **Read when:** touching `AboutSettingsSection`, `AppBuildInfo` or the Settings list's last section.

Proposal: [settings-version-row.html](mockups/proposals/settings-version-row/settings-version-row.html) (A footer line, B About row, C inside Report an issue). **B is the decision (owner, 2026-10-26).**

## The decision

- A last Settings section, **About**, with one row, **Version**. The value is `AppBuildInfo.versionText`: `2610.26.01 (57) · 42edc57` on a release build, `0.1.0 (1)` on a local or simulator build (kept, so the UI tests exercise it).
- Tapping the row copies the shown text, not the spoken form. The footer under it reads **Tap to copy.** and says **Copied.** for two seconds after a copy.
- The value sits on the trailing edge; when it no longer fits beside the title (large text sizes) it wraps under it and the glyph is dropped, like `SettingsLinkRow` at accessibility sizes. It wraps, never truncates.
- VoiceOver: label "Version", value "2610.26.01, build 57, commit 42edc57" (`AppBuildInfo.spokenVersionText`), hint "Copies the version to the clipboard.", a button. Copying announces "Copied.".
- Haptic: `TapFeedback.confirmation` (success). The proposal named a success haptic; [tap-feedback](../patterns/tap-feedback.md) lists the confirmation pattern for "input is read", so copying is added to its table. It plays on the tap (the copy is immediate and local), never late.
- The row is a Button and draws no chevron: it presents nothing and pushes nothing ([settings-section](../patterns/settings-section.md)).

## Open questions from the proposal, answered by default

1. Report an issue does not attach the build yet; that is a separate, non-visual change (`TODO(orchestrator)`: attach `AppBuildInfo.versionText` to the feedback diagnostics).
2. Local and simulator builds keep showing `0.1.0 (1)`.

## Where

`apple/Sources/HassUI/Features/Settings/AboutSettingsSection.swift` (`AboutSettingsModel`, `AboutSettingsSection`, `VersionRow`), added to `SettingsScreen` after the Feedback section. Atlas: [pages/settings/settings](mockups/pages/settings/settings/README.md) (About section, `version-copied` state). Tests: `HassUITests/AboutSettingsTests.swift` (text, copy, announcement, haptic trigger, footer timing, AX5 reflow), `iOSUITests/SettingsTabJourneyTests` (`settings.version` is a named 44 pt control, copy confirms, accessibility audit at default and AX5 on iPhone, Duo and iPad).
