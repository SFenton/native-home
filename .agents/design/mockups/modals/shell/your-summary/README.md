# Your Summary (Account sheet, four tabs) (modal)

> **What:** the sheet behind the header Profile button: Profile, Overdue Chores, Upcoming Chores and Expired Food tabs, full height. **Read when:** you change `HassUI/Features/Settings/Profile` or `HassCore/Profile`.

- Mockup: [your-summary.html](your-summary.html) · shipped · reviewed 2026-10-23 (author self-check; skill reviewers replace it)
- Source: `apple/Sources/HassUI/Features/Settings/Profile/YourSummarySheet.swift`, `SummaryPanel.swift`, `ProfileTab.swift`, `SummaryChoresTab.swift`, `SummaryExpiredFoodTab.swift`
- Spec: `.agents/pages/settings/profile.md`, `.agents/design/direction-g.md`, `.agents/pages/settings/location.md`  · Patterns: modal-sheet, module-list, motion
- States covered: default (Overdue), profile, profile-location-off, upcoming, expired-food, loading, error, offline, three empty tabs, vacation, vacation-food, guest, sam, sign-out-alert, ax5. Detent: `.full` only (large).
- Motion: tab-crossfade (0.15 s, none under Reduce Motion), chore-complete (list animation). Transitions: present and dismiss, sign-out alert.
- Devices: iPhone, Duo folded, unfolded portrait and landscape, iPad portrait and landscape (full-height form sheet).
- Helpers: `pages/settings/_settings-account.js`, `pages/settings/_settings-page.js`, `modals/settings/_settings-account.js`, `modals/shell/_settings-account.js` (shared builders and local symbols; promote-to-kit list in the mockup's Notes).
- Open notes: motion.md 4.4 says sheet tabs are a cut; the code fades 0.15 s. Chore and food rows are simplified stand-ins.
