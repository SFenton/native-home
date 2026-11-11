# Live Activity problem card: the failure notice

> **What:** where a problem card shows the one-update failure notice after a button press fails, and why. **Read when:** you touch `ProblemCardView`, the `notice` content key, or the problem card's mockup.

## Goal

The job card draws `notice` ("Couldn't resume. Try again." from Home Assistant, "Couldn't reach Home" from the app) in place of its value. The problem card drew nothing, so a failed Resume came back to the Resume and Done buttons with no reason (R-43). The words already existed; only the placement was open. "Not confirmed" was never missing: `ActivityButtons` draws it on every card.

## Options judged

Built as two switchable placements and captured on iPhone, iPhone Duo folded and iPad portrait, at the default and the largest text size (evidence pack `build/evidence/la-vacuum-resume/`, head `2cfc735`).

| | Placement | Default size | Largest size | Seen in the captures |
|---|---|---|---|---|
| **B, `replace`** | The notice takes the instruction's place | 129.7 and 132.3 pt | 780 to 801 pt | Three text lines and the buttons. Nothing cut that is not cut today |
| **C, `line`** | The notice on its own line; the instruction keeps one line | 148 and 151.7 pt | 1035 to 1093 pt | Four text lines. The amber card's instruction ends mid-sentence ("Refill the clean water tank on the dock, the…"). At the largest size the notice sits under the whole instruction |
| A | Beside the buttons, where "Not confirmed" sits | not built | not built | Ruled out on width before building: about 88 pt beside three buttons on a 393 pt iPhone, where "Couldn't resume." alone needs about 104 pt |

Decision: 2026-11-10, judged Option B (`replace`) and Option C (`line`) from the captures, with Option A ruled out before building; picked B, because after a failed press the reason is the one thing to read and B shows it whole in a card of three lines, it leaves 28 pt under the 160 pt Lock Screen limit where C leaves 8, at the largest text size it puts the notice directly under the problem line in a card a quarter shorter, and it is the rule the job card already follows.

Gate: app_wide=no (agent-initiated; `tools/jev_gate.py` on `build/decisions/R-43-notice-plan.md`: autonomous, local to one card).

Why C lost: it adds a fourth line of small text to a glanceable card and cuts the instruction mid-sentence on the amber card, so it keeps the instruction in name only there; it uses 148 to 152 of 160 pt; and at the largest text size the notice comes after the full instruction, about 290 pt further down a card that the real Lock Screen cuts at 160 pt.

What B costs: the instruction is not drawn while the notice stands. VoiceOver still speaks it. How long a notice stands on a stopped device is not measured (follow-up 1).

HIG, Live Activities: "Focus on important information people need at a glance."; "Ensure text is easy to read"; "Dynamically change height on the Lock Screen and in expanded to fit the available information."; Lock Screen 84 to 160 pt; "Focus on simple, direct actions." (no new control).

## Rules

1. **One rule for `notice` on every card:** it takes the place of the card's content line for as long as that content stands. The job card's value; the problem card's instruction. The device and problem lines and the buttons never move for it.
2. **Style on the problem card:** subheadline, semibold, white (`ActivityStyle.primaryText`). Never `ActivityStyle.noticeText`: that amber is the warning severity's problem-line colour. Two lines at ordinary sizes, no limit at accessibility sizes.
3. **Accessibility:** the notice is its own static text, `liveactivity.notice`, read after the problem phrase (`liveactivity.problem`) and before the buttons. The phrase keeps the instruction.
4. **No new words.** The notice is whatever the content carries; the app writes only "Couldn't reach Home".
5. **Presentations:** Lock Screen, banner and StandBy draw it (one fluid layout on iPhone, iPhone Duo and iPad). The Dynamic Island and the small family do not: the expanded island's problem block is unchanged in this change.

## Not captured, and what to check later

- **iPhone Duo unfolded portrait** was not run (the pose driver lacks a macOS permission). Accepted: the card is one fluid layout with no size-class or hinge branch, the gallery draws it at a fixed width, and the three captured families measure the same. When the pose can run, confirm `problem-notice` and `problem-notice-stuck` are at most 160 pt at the default size and the notice is whole.
- **Real Lock Screen widths.** The gallery draws 370 pt (350 pt on the folded Duo). On a device, look once at the card on an iPad (425 or 500 pt) and on the Duo.

## Follow-ups (not part of this change)

1. Measure how long a notice stands on a stopped vacuum. If it is more than about a minute, the engine should send a clearing update; the card does not change.
2. The amber card's problem line is cut today ("Needs attention · Clean water tank…"), with or without a notice. With the instruction gone it is the only line naming the problem, and B leaves room for a second line. A visible change of its own.
3. The expanded island's problem block has the same Resume button and no notice.
4. The job card's notice keeps two lines at accessibility sizes.

Mockups: current design [live-activity-problem-card](mockups/components/live-activity/live-activity-problem-card/live-activity-problem-card.html) (state `notice`); the options as proposed, [live-activity-problem-notice](mockups/proposals/live-activity-problem-notice/live-activity-problem-notice.html).
