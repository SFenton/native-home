# Batch brief (for mockup authors)

> **What:** the working instructions for an author who owns one batch of `catalog.json` items. **Read when:** you were handed a batch id. The contract for a mockup file is [AUTHORING.md](../design/mockups/_kit/AUTHORING.md); the component API is [README.md](../design/mockups/_kit/README.md).

> **Archived 2026-10-28.** The brief for the batch that mapped the atlas on 2026-10-23. The current contract is [_kit/AUTHORING.md](../design/mockups/_kit/AUTHORING.md).

Worktree: `/Users/dev/repos/<app-repo>-mockups` (branch `claude/mockup-atlas`). Fourteen other authors work in the same worktree at the same time on other folders.

## Your job

1. List your items: `python3 -c "import json;[print(i['id'],i['kind'],i['path'],i['weight']) for i in json.load(open('.agents/design/mockups/catalog.json'))['items'] if i['owner']=='<batch>']"`. Each item's `path` is the folder you create under `.agents/design/mockups/`; the file is `<id>.html`, plus `README.md`.
2. For every item, read what the app **draws today**: the SwiftUI sources in the item's `sources`, the tests that exercise them (`apple/Tests`, `apple/Apps/iOSUITests`), the page docs in `docs` and `patterns`, and [motion.md](../design/motion.md) / [patterns/motion.md](../patterns/motion.md) for every animation. Read [direction-g](../design/direction-g.md) for materials. Real copy, real section order, real states. Do not redesign; where docs and code disagree, draw the code and say so in `notes`.
3. Build the mockup with `Mock.mount` per AUTHORING.md: all devices the item appears on (the catalog's `devices` and `deviceNote`; iPhone, Duo folded / unfolded, iPad portrait / landscape as applicable), every state that exists in the code (default, loading, refreshing, empty, error, offline, reconnecting, long-text, ax5, plus the item's `statesHint`), every animation and transition with its token, duration and a working Play (`motionHint`; honour Reduce Motion), accessibility notes (reading order, labels, 44 pt targets, AX5 behaviour, rotor/focus where it matters), and the source map. For a modal show each detent it really has, light and dark if it follows the system appearance, and the iPad form vs page size. Pages show the tab/flyout/rail chrome for each device; components use `Mock.componentConfig` where the kit has the component and add real usages in context.
4. In-flight items (`inFlight` in the catalog) are drawn as the target with `status: 'in-flight:<branch>'` and a small "was" comparison. The uncommitted camera viewer work is readable in `/Users/dev/repos/<private-app-repo>` (the primary checkout), the reconnecting arc in its worktree `/Users/dev/repos/<private-app-repo>/.claude/worktrees/reconnecting-spinner`, and weather option D in `/Users/dev/repos/<private-app-repo>/.claude/worktrees/weather-card-header-d-5a3fe5`. Read-only: never edit those checkouts.
5. Reviews: put an honest author self-check in `reviews` (rules from the `apple-hig` skill and SwiftUI Pro's design/accessibility/motion rules that you verified while reading the code) with `by: 'author'`. Dedicated skill reviewers replace these later, so keep each finding `{rule, verdict, note}`; if `Mock.lint` insists on non-empty reviews, a single `{rule:'pending-skill-review', verdict:'pass', note:'author draft'}` is fine.
6. Write the folder `README.md` (template in AUTHORING.md, at most 40 lines) for every item.

## You must not

- Edit anything in `_kit/`, `catalog.json`, `README.md` at the mockups root, `apple/`, `tools/`, or another batch's folders. Need a shared helper? Put it in `<kind>/<area>/_<batch>.js` beside your mockups (loaded with a `<script src>` relative path) and list it under `notes` as "promote to kit: ..." Do not add to `Mock.COMPONENTS`.
- Commit, push, create worktrees or branches. The lead commits.
- Add rasters, screenshots or real data (devices.md: screenshots are never committed). Wallpaper and photos are the kit's stand-ins.

## Effort and quality

- A shipped, simple item (a one-line alert, a toolbar button) gets a compact mockup: its few states, devices where it differs, motion if any. A page or tabbed sheet gets the full treatment. Weights in the catalog say which. Cheap does not mean empty: every mockup lists source, spec, states, a11y and notes.
- Fidelity over polish: the structure, order, copy, colours, sizes and states must match the code. Stand-in glyphs and photos are fine.
- No clipped text at `ax5`; check it.

## Verify before you report

Pick your own port (`8100 + batch index`, any free one), serve `python3 -m http.server <port> --directory /Users/dev/repos/<app-repo>-mockups/.agents/design/mockups` in the background, open **your own browser tab** (`tabs_create`, always pass your `tabId`; other authors share the pane) at `http://localhost:<port>/<path>/<id>.html`, flip device, state, appearance, text size, Reduce Motion and each Play, read the console for errors, fix, then close your tab and stop your server. Run `python3 tools/mockups_check.py` for your folders (ignore catalog `mockup` fields: the lead fills them). Take a screenshot of at least each page and one modal per area to check.

## Report (under 150 words)

Items done and the ones skipped with the reason; kit gaps to promote; docs-versus-code discrepancies you found; anything in-flight you could not confirm. No code in the report.
