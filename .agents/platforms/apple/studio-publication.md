# Studio publication

> **What:** how an agent changes the owner's Studio draft and publishes it. **Read when:** a change must reach the phones through the Studio, or you touch `studio_guard.py`.
A publish from the owner's Studio reaches every phone at once, so it is a live change. It goes only through the Studio's own CLI, `scripts/studio-publish.ts` in the Studio repository (`ha-native-home-app`), never through its API or data directory.
Its contract is that repository's `docs/agent-publish.md`; change records live under `~/hass-agents/studio-publish`.

The one form [`studio_guard.py`](../../../tools/hooks/studio_guard.py) lets through is `<checkout>/node_modules/.bin/tsx <checkout>/scripts/studio-publish.ts <command>`, where `<checkout>` is a git worktree of that repository and the path has no `.` or `..` segment; there is no npm form.
A tsx running another script, a look-alike `studio-publish.ts` outside a checkout, a heredoc and every other write to the draft, the data directory or port 4801 are refused.

- **Who.** A Coder lane builds the record, with before and after shots (a hosted fixture render of `base.document` and `document`), outside every repository, to the Studio repo's "The change record" contract. Then the dispatched step (orchestrator or menial) runs `check`, `apply`, `publish`; only it runs `rollback` and `resolve`. `status` and `check` are open to all.
- **Tool rules.** The scope guard, rollback from the saved prior copy, the log and the owner alert are the CLI's. A rollback or a change marked `owner_action` is reported to the owner with the before and after screenshots, the revisions and the security flag.
