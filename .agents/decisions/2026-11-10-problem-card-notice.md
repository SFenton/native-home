# Problem card failure notice

Decision: the Live Activity problem card shows the one-update failure notice in place of the instruction; options A, B and C judged (A beside the buttons, B in place of the instruction, C on its own line under a one-line instruction); picked B. Gate: app_wide=no, local to one card.
Replaces: a problem card that drew no notice, so a failed Resume came back to Resume and Done with no reason.
Rule home: `.agents/design/live-activity-problem-notice.md`.

A was ruled out on width before it was built: about 88 pt beside three buttons on a 393 pt iPhone, where "Couldn't resume." alone needs about 104 pt. B and C were built as two switchable placements and captured on iPhone, iPhone Duo folded and iPad portrait, at the default and the largest text size.

| | Default size | Largest size | Seen in the captures |
|---|---|---|---|
| B | 129.7 and 132.3 pt | 780 to 801 pt | Three text lines and the buttons; nothing cut that is not cut already |
| C | 148 and 151.7 pt | 1035 to 1093 pt | Four text lines; the amber card's instruction ends mid-sentence; at the largest size the notice sits under the whole instruction |

B won because after a failed press the reason is the one thing to read and B shows it whole in a card of three lines. It leaves 28 pt under the 160 pt Lock Screen limit where C leaves 8. At the largest text size it puts the notice directly under the problem line in a card a quarter shorter. It is the rule the job card already follows.

C lost because it adds a fourth line of small text to a glanceable card and cuts the instruction mid-sentence on the amber card. It uses 148 to 152 of 160 pt, and at the largest size the notice follows the full instruction, about 290 pt further down.

B costs the instruction, which is not drawn while the notice stands; VoiceOver still speaks it. How long a notice stands on a stopped device is not measured. Follow-ups: measure it, and if it exceeds about a minute have the engine send a clearing update; the amber card's problem line is cut with or without a notice; the expanded island's problem block has the same Resume button and no notice; the job card's notice keeps two lines at accessibility sizes. Not captured: iPhone Duo unfolded portrait.
