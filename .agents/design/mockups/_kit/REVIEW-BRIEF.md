# Review brief (skill reviewers)

> **What:** how a reviewer replaces a mockup's author self-check with a review done through the `apple-hig` and `swiftui-pro` skills. **Read when:** you were handed a review group (`_review-groups.json`, keys R1 to R8).

Worktree: `/Users/dev/repos/<app-repo>-mockups` (branch `claude/mockup-atlas`). Seven other reviewers work at the same time on other groups. One more agent is fixing `_kit/`; do not edit `_kit/`.

## Method

1. **Load both skills with the Skill tool** before reviewing: `apple-hig` (use its `/duo` guidance for the Duo surfaces) and `swiftui-pro` (its design, accessibility, motion, navigation and materials rules; this atlas shows SwiftUI, so apply it to what the *app* does, which the mockup depicts). Cite the rule or HIG section by name in each finding.
2. For each mockup path in your group: read the mockup's config, its README, and the SwiftUI source it lists. Open it in headless Edge (`/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge --headless=new --screenshot=<scratch>/x.png --window-size=1400,1000 --virtual-time-budget=4000 http://localhost:<port>/<path>`; serve the mockups folder on port `8200 + group number` from `python3 -m http.server`) for at least the main states, or use the browser pane only if a tab is free (always pass your own tabId). Judge the **app as depicted**: touch targets, Dynamic Type and AX5 behaviour, contrast, hierarchy, navigation and sheet conventions, materials and Liquid Glass use, motion and Reduce Motion, haptics and feedback where the source shows them, Duo hinge and iPad size-class behaviour, VoiceOver order and labels.
3. Replace the mockup's `reviews` block with `{ date: '2026-10-23', hig: [...], swiftui: [...] }` where each entry is `{ rule, verdict, note }` and `verdict` is `pass` (verified in the source or render), `fix` (the app today falls short; one sentence on what and where, file and line when you have it), or `departure` (the app departs from the HIG on purpose: cite the owner decision or doc paragraph). Add `by: 'apple-hig skill'` / `by: 'swiftui-pro skill'`. Six to twelve entries per mockup, specific to it; no boilerplate repeated across a group unless it is genuinely identical. Compact items (one-line alerts, small components) need three or four.
4. **The atlas maps the app as it is.** A `fix` finding is a recorded finding, not an instruction to change the app and not a reason to alter the drawing. Never edit `apple/`. Change a mockup's drawing only when you find the mockup disagrees with the code (then fix the mockup and note it in `notes`).
5. After each mockup, make sure the page still loads without a console error or lint banner.
6. Write `_review/<group>.md` beside this file's folder (`.agents/design/mockups/_review/<group>.md`, create the folder if needed): a table of every `fix` finding (mockup id, rule, finding, severity high/medium/low) and the five most important cross-cutting observations for the group. At most 70 lines.

## Don't

Commit, push, create worktrees, edit `apple/`, `_kit/`, `catalog.json`, or another group's mockups. Add screenshots to the repo (devices.md rule).

## Report (under 120 words)

Counts of pass / fix / departure by group; the three highest-severity `fix` findings; mockups you corrected because they disagreed with the code. No code.
