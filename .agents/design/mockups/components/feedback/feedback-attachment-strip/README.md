# Feedback attachment strip and tile (component)

> **What:** the horizontal strip of 76 pt thumbnails with open and remove buttons in the feedback form. **Read when:** you change `FeedbackAttachmentStrip` or `FeedbackAttachmentTile`.

- Mockup: [feedback-attachment-strip.html](feedback-attachment-strip.html) · shipped · reviewed 2026-10-23 (apple-hig and swiftui-pro skill review)
- Source: `apple/Sources/HassUI/Features/Settings/Feedback/FeedbackAttachmentStrip.swift`, `FeedbackAttachmentTile.swift`
- Spec: `.agents/pages/settings/feedback.md`  · Patterns: none
- States covered: empty, photos, video, max, sending, targets (the 44 pt hit regions), ax5. Sheet surface only.
- Motion: None.
- Devices: Size classes: iPhone and iPad portrait.
- Helpers: `pages/settings/_settings-account.js`, `pages/settings/_settings-page.js`, `modals/settings/_settings-account.js` (shared builders and local symbols; promote-to-kit list in the mockup's Notes).
- Open notes: No doc records the tile geometry. Thumbnails are stand-in scenes.
