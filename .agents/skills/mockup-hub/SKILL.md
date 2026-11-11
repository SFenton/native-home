---
name: mockup-hub
description: Publishes the mockup atlas, proposals and kit gallery as the one hub Artifact the owner opens in the Claude app. Use when adding, changing or proposing a mockup, or when asked where to view one.
---
# Mockup hub

> **What:** how the mockup atlas, proposals and kit gallery are published as one multi-page Artifact. **Read when:** you add, change or propose a mockup, or the owner asks where to view one.

Any change under `.agents/design/mockups/` ends with steps 3 to 5, unasked, and the owner gets the hub link, never HTML or a file path. `tools/hooks/mockup_hub_guard.py` checks it at Stop. The hub link is kept outside the repo: read it from `SH_MOCKUP_HUB_URL`, or from the first line of the file `SH_MOCKUP_HUB_URL_FILE` names.

1. **Author** the mockup as the atlas [README](../../design/mockups/README.md) requires: a folder with `<id>.html`, its README and a `catalog.json` entry with its `status`. Proposals follow the same form. Delete what is not true any more; do not annotate it.
2. **Check:** `python3 tools/mockups_check.py` and `python3 tools/mockups_index.py --check`.
3. **Build:** `python3 tools/mockups_hub.py` writes `build/mockups-hub/` with `index.html` and a copy of every mockup and the files it loads. When a kit helper fails to load in the app, `--inline` builds every page self-contained.
4. **Publish** with the Artifact tool, always to the hub link as `url`; omit `icon` and `capabilities`.
   - `file_path` is `build/mockups-hub/index.html`; `root` is `build/mockups-hub`.
   - `files` is one list from `python3 tools/mockups_hub.py --batches`. Publish each batch in turn to the same `url`.
   - After a small change publish only the changed files; files left out are kept. After a kit change publish everything.
   - Remove a deleted mockup by publishing `files` as `{"a/<path>": null}`.
5. **Mark and tell:** `python3 tools/mockups_hub.py --mark-published`, then give the owner the hub link. Sharing the page is theirs to do.

A session without the Artifact tool does steps 1 to 3, says in the pull request that the republish is pending and names the hub link. Never publish a mockup as its own Artifact.
