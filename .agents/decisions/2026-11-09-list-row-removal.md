# List row removal

Decision: every diffable list applies its snapshot through one applier (`UKListUpdater`, policy in `ListUpdateTransition` and `ListUpdateLedger`), so a deleted row or section leaves with the system list animation, in every list, with remote removals animating too. Options judged for the swipe across the confirmation: hold (the swiped row stays open while "Delete X?" is up; confirm collapses it as the card leaves, cancel slides it back; anchoring the iPad popover on the open Delete action is not part of this change) and close (the swipe closes first, then the confirmation); picked hold. Options judged for the card corners when a first or last row leaves: B (the neighbour's corners are redrawn in the same list update) and C (redrawn after the delete plays); picked B. The owner made the picks.
Replaces: none
Rule home: `.agents/patterns/list-row-removal.md`
Gate: app_wide=yes; matches_request=yes
Owner's request: "when deleting a food item, and another one will be left, the deleted item does not smoothly disappear in a system/platform style for iOS that I would expect. I expect the result of this to be a reusable pattern that we can instrument throughout the app where we need to, so take care with implementation and architecture."

The gate record: the change touches every diffable list, and the owner asked for exactly that, so it is app-wide and it matches the request. The owner answered the scope on 2026-11-05 ("Pattern + all lists"; remote removals: "Animate those too") and the two open picks on 2026-11-09 ("Hold + B"). The app-UI gate had parked the plan as `matches_request=unsure` before those answers.

Why hold: the cause and the answer stay in one place, and cancelling needs no reopen. Why B: with the neighbour redrawn in the same update, the card never shows a square corner for a beat after the delete. The close and C branches, and the debug launch switch that carried both while they were judged, were removed.

Ported from the old repository's pull request 326 (built and reviewed there, never merged before the move to this repository).
