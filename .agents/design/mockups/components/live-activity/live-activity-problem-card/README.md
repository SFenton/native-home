# Live Activity problem card, critical red and warning amber (component)

> **What:** the card a device problem turns the activity into: severity circle, problem, instruction, up to three buttons. **Read when:** you change a problem row, its glyph or wording, or the severity colours.

- Mockup: [live-activity-problem-card.html](live-activity-problem-card.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/FentonActivityViews/ProblemCardView.swift`, `SeverityCircle.swift`, `ActivityStyle.swift`, `FentonActivityModel/ActivityProblem.swift`, `HomeActivityFixtures.swift` · Spec: `.agents/platforms/apple/live-activities-per-job.md` (section 5 table, section 8), `live-activities.md` · Patterns: none
- States covered: default (critical), warning, banner, critical (all rows), warnings (all rows), flipped (Done), chips, pending, standby, table, ax5
- Motion: Done to Completing (system content update)
- Devices: iPhone, iPhone Duo folded; one design for every device
- Open notes:
  - All 19 section 5 rows drawn from the fixtures; corner mark is 40 pt here (24 pt on job cards).
  - Duo and StandBy scale unverified.
  - Glyphs are stand-ins for the SF Symbols in ActivityGlyphImage.swift.
- Helper: `components/live-activity/_widgets-liveactivity.js` (Live Activity, island, small family, notification and Watch stand-ins; promote to kit).
