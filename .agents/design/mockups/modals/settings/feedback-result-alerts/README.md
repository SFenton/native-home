# Feedback result alerts (filed, couldn't send) (modal)

> **What:** the two alerts that end a Submit: Report or Request Sent, and Couldn't Send. **Read when:** you change the filing result copy or `FeedbackFilingError`.

- Mockup: [feedback-result-alerts.html](feedback-result-alerts.html) · shipped · reviewed 2026-10-23 (apple-hig and swiftui-pro skill review)
- Source: `apple/Sources/HassUI/Features/Settings/Feedback/FeedbackFormSheet.swift`, `apple/Sources/HassCore/Feedback/FeedbackFilingError.swift`
- Spec: `.agents/pages/settings/feedback.md`  · Patterns: modal-sheet
- States covered: default (Report Sent), request-sent, github, network, rate-limited, attachment, signed-out, ax5.
- Motion: None custom.
- Devices: iPhone, Duo folded and unfolded landscape, iPad portrait and landscape.
- Helpers: `pages/settings/_settings-account.js`, `pages/settings/_settings-page.js`, `modals/settings/_settings-account.js` (shared builders and local symbols; promote-to-kit list in the mockup's Notes).
- Open notes: The catalog says "filed"; the titles are "Report Sent" and "Request Sent". Issue numbers are fixtures.
