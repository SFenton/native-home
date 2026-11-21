# Studio publication

> **What:** how an agent changes the owner's Studio draft and publishes it. **Read when:** a change must reach the phones through the Studio, or you touch `studio_guard.py`. Sibling of [ha-operations](ha-operations.md).

A publish from the owner's Studio reaches every phone at once, so it is a live change too. It goes only through the Studio's own CLI, `scripts/studio-publish.ts` in the Studio repository (`ha-native-home-app`), never by calling the Studio API, never by editing its data directory.
Its commands, change record, refusals and rollback are in that repository's `docs/agent-publish.md`; the change record lives under `~/hass-agents/studio-publish`.

The one form [`studio_guard.py`](../../../tools/hooks/studio_guard.py) lets through is `<checkout>/node_modules/.bin/tsx <checkout>/scripts/studio-publish.ts <command>`, where `<checkout>` is a git worktree of that repository and the path has no `.` or `..` segment; there is no npm form.
A tsx running another script, a look-alike `studio-publish.ts` outside a checkout, a heredoc and every other write to the draft, the data directory or port 4801 are refused.
Code may read the change record under `~/hass-agents/studio-publish/<id>/` and its log `studio-publish.jsonl`; no other word naming the tool passes.

- **Who.** Lanes build a change and its evidence. Only the orchestrator's dispatched publish step (the orchestrator or the menial) runs `apply`, `publish`, `rollback` and `resolve`. `status` and `check` are open to every agent.
- **Tool rules.** Scope guard, order (`check`, `apply`, `publish`), rollback from the saved prior copy, the log and the owner alert are the CLI's, in its `docs/agent-publish.md`. A rollback or a change marked `owner_action` is reported to the owner with the before and after screenshots, the revisions and the security flag.
