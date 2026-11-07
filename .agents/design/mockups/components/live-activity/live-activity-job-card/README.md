# Live Activity job card, Lock Screen, banner and StandBy (component)

> **What:** the card a running household job draws on the Lock Screen, in a banner and in StandBy, in every job family and state. **Read when:** you change a job card, its figure, bar or buttons, or the engine content-state it draws.

- Mockup: [live-activity-job-card.html](live-activity-job-card.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/FentonActivityViews/JobCardView.swift`, `HomeActivityLockScreenView.swift`, `ActivityStyle.swift`, `ActivityValueLine.swift`, `ActivityFigure.swift`, `ActivityBar.swift`, `FentonActivityModel/ActivityCard.swift`, `HomeActivityFixtures.swift` · Spec: `.agents/platforms/apple/live-activities-per-job.md`, `live-activities.md` · Patterns: telemetry (catalog)
- States covered: default (Lock Screen), stack2, stack4, banner, standby, jobs, laundry, vacuums, hotflash, pending (pending, stale, notice), ax5
- Motion: timers count and the bar fills (system), press to Stopping, complete (system content updates, no app animation)
- Devices: iPhone, iPhone Duo folded (card width unmeasured on Duo); no iPad presentation is designed
- Open notes:
  - Doc vs code: spec section 8 (64 pt ring, 28 pt value) is superseded by 8a (L4: no ring, 32 pt value, buttons beside it); the code is drawn.
  - Duo Live Activity not run on a simulator; StandBy scale is illustrative.
  - Glyphs and the clock are kit stand-ins; promote to kit: components/live-activity/_widgets-liveactivity.js.
- Helper: `components/live-activity/_widgets-liveactivity.js` (Live Activity, island, small family, notification and Watch stand-ins; promote to kit).
