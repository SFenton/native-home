# Feedback form (Report an Issue, Request a Feature) (modal)

> **What:** the form sheet with Cancel and Submit: prefixed title, description, steps, expected behaviour, media, reasons and sending phases. **Read when:** you change `HassUI/Features/Settings/Feedback` or `HassCore/Feedback`.

- Mockup: [feedback-form-sheet.html](feedback-form-sheet.html) · shipped · reviewed 2026-10-23 (apple-hig and swiftui-pro skill review)
- Source: `apple/Sources/HassUI/Features/Settings/Feedback/FeedbackFormSheet.swift`, `FeedbackFormModel.swift`, `FeedbackSettingsSection.swift`, `FeedbackFieldHeader.swift`
- Spec: `.agents/pages/settings/feedback.md`, `.agents/workflow/triage-agent.md`  · Patterns: modal-sheet, info-box
- States covered: default, feature-empty, no-description, typed, feature-typed, loading, setup-needed, with-attachments, max-attachments, importing, sending-media, sending-filing, error, offline, discard, filed, medium, large, fitted, ax5.
- Motion: submit-progress (system linear bar). Transitions: present, discard, result alert.
- Devices: iPhone, Duo folded and unfolded landscape, iPad portrait and landscape (form sheet).
- Helpers: `pages/settings/_settings-account.js`, `pages/settings/_settings-page.js`, `modals/settings/_settings-account.js` (shared builders and local symbols; promote-to-kit list in the mockup's Notes).
- Open notes: Cancel and Submit are text buttons, not the kit's circle x and check (docs vs code). The catalog's "Submit shows ArcSpinner" is not in the code.
