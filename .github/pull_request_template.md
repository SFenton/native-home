## What changed for you
<!-- Two or three sentences for a person who never opens code. No file, class, flag or tool names. Say what looks or works differently, on which device. -->

> Your request: "[the owner's words, one line]"

**Check it in 30 seconds:** [open this on that device, tap here, you should see this]. (Invisible change: "Nothing to look at: [why].")

## Before and after
<!-- One hero pair: the device class the request is about, or the one with the biggest change. Motion only: one clip, alone in its paragraph, 5 to 15 s, under 8 MB. -->
<!-- Fill in once the pictures exist, then remove this comment:
| Before | After |
|---|---|
| ![Before](build/evidence/BRANCH/before/CLASS/POSE.jpg) | ![After](build/evidence/BRANCH/after/CLASS/POSE.jpg) |
-->

## Devices
<!-- sh-devices:start -->
| Device | Result |
|---|---|
| iPhone | Unchanged, checked by [tests] (or: See the iPhone pictures in the comment "iPhone, round N") |
| iPhone Duo | Unchanged, checked by [tests] (or: See the Duo pictures in the comment "iPhone Duo, round N") |
| iPad | Unchanged, checked by [tests] (or: See the iPad pictures in the comment "iPad, round N") |
<!-- sh-devices:end -->

<!-- sh-status:start -->
**Status:** Drafting · Level [L0, L1 or L2] · Waiting on: nobody
<!-- sh-status:end -->

<details><summary>Why and how (for engineers)</summary>

[What and why, rung-0 note link, patterns touched, design record link, follow-ups.]

</details>

<details><summary>Tests and coverage</summary>

<!-- Commands and results. -->

</details>

<details><summary>Review verdict</summary>

<!-- The reviewer's summary is written between these markers by tools/review/record.py --pr N. -->
<!-- review:start -->
<!-- review:end -->

</details>

<details><summary>Checklist (mirrors the pre-merge reviewer, .claude/agents/reviewer.md)</summary>

- [ ] `/swiftui-pro` run on the Swift diff
- [ ] UI diffs: Apple HIG checked, section cited
- [ ] Pattern reused or extended (`.agents/patterns`), no parallel implementation; `python3 tools/pattern_guard.py changed --base origin/main` reviewed and `python3 tools/pattern_guard.py` clean
- [ ] System API first: rung-0 note names the iOS 17/18/26 API, a precedent and why it is not enough
- [ ] Unit tests for logic; UX and accessibility tests on each affected device family (iPhone, Duo, iPad)
- [ ] Surface mockup and catalog updated; hub republished
- [ ] Visible change: proposal link and the owner's pick
- [ ] Layering respected (HassCore / HassDesign / HassUI; state through `EntityStore`)
- [ ] Performance invariants hold (no per-frame state, nothing on main that scales with the house, no reload on reopen)
- [ ] Invariants sweep: no secrets, `Release-Note:` trailers, native only, no new `#if os(macOS)`, devcap holds in new tooling, docs updated, DocC

</details>
