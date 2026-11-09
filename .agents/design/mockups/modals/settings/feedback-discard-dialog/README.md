# Discard feedback? (confirmation dialog) (modal)

> **What:** the confirmation raised by Cancel, Escape or a swipe when the form holds typed input or media. **Read when:** you change the feedback dismiss path.

- Mockup: [feedback-discard-dialog.html](feedback-discard-dialog.html) · shipped · reviewed 2026-10-23 (apple-hig and swiftui-pro skill review)
- Source: `apple/Sources/HassUI/Features/Settings/Feedback/FeedbackFormSheet.swift`, `SheetDismissAttemptObserver.swift`
- Spec: `.agents/pages/settings/feedback.md`  · Patterns: modal-sheet
- States covered: default (popover under Cancel), request, action-sheet, ax5 (dark and light). No detents.
- Motion: None custom.
- Devices: iPhone, Duo folded and unfolded landscape, iPad portrait and landscape.
- Helpers: `pages/settings/_settings-account.js`, `pages/settings/_settings-page.js`, `modals/settings/_settings-account.js` (shared builders and local symbols; promote-to-kit list in the mockup's Notes).
- Open notes: iOS 27 popover omits Cancel; Keep Editing remains for earlier systems.
