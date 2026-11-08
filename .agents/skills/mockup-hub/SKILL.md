---
name: mockup-hub
description: Publishes the mockup atlas, proposals and kit gallery as the one hub Artifact the owner opens in the Claude app. Use when adding, changing or proposing a mockup, or when asked where to view one.
---
# Mockup hub

> **What:** how the mockup atlas, proposals and kit gallery are published as one multi-page Artifact the owner opens in the Claude app. **Read when:** you add, change or propose a mockup, or the owner asks where to view one.

Hub (private, owner's claude.ai): the owner's private mockup gallery (link kept outside the repo)

**Always republish (owner, 2026-10-28).** Any change under `.agents/design/mockups/` ends with steps 3 to 5 below, without being asked, and you give the owner the hub link, never HTML or a file path. The Stop hook `tools/hooks/mockup_hub_guard.py` blocks ending a session that changed mockups until the hub has been rebuilt and marked published. It only counts files changed since this session started (a SessionStart stamp), so another session's dirty files never block you; subagents are not covered.

1. **Author** the mockup in `.agents/design/mockups/` as the atlas requires ([README](../../design/mockups/README.md), [propose-first](../../workflow/propose-first.md)): a folder with `<id>.html`, its README and a `catalog.json` entry, proposals included (set `status`: `proposed`, then `decided` with a `decision` link, or `superseded` with `supersededBy`). It needs `<body>`; a missing doctype is added in the built copy. Remove what is no longer true (a "was" state for something that shipped, a stale `inFlight`) instead of annotating it.
2. **Check** with `python3 tools/mockups_check.py` and `python3 tools/mockups_index.py --check`.
3. **Build** with `python3 tools/mockups_hub.py`. It writes `build/mockups-hub/` (git-ignored): `index.html` (current cards by Pages, Modals, Components, Flows, Proposals awaiting the owner, Kit, then a collapsed "Why" section of decided and superseded proposals) and `a/<same path>` for every mockup and every file it loads. Each copy gets a back-to-hub pill; repo files are untouched. It also stamps `build/mockups-hub.built`. If a kit helper loader ever fails in the app, `--inline` builds every page self-contained instead.
4. **Publish** with the Artifact tool, always to `url` = the hub link (read it first in a fresh session; omit `icon`, `capabilities`). `file_path` = `build/mockups-hub/index.html`, `root` = `build/mockups-hub`, `files` = one list from `python3 tools/mockups_hub.py --batches`. The tool takes at most 255 files per publish, so publish each batch in turn to the same `url`. After a small change, publish only the changed files (files you leave out are kept); after a kit change, publish everything. Remove a deleted mockup by publishing `files` as `{"a/<path>": null}`.
5. **Mark and tell.** Run `python3 tools/mockups_hub.py --mark-published` (the hook reads it), then give the owner the hub link. It is private; sharing is theirs to do from the page's Share menu.

Sessions without the Artifact tool still do 1 to 3, say in the PR that the hub republish is pending, and name the hub link so the owner or the next session can finish it. The hook lets a second stop attempt through, so it never traps a session that cannot publish.
