# Studio publication

> **What:** how an agent changes the owner's Studio draft and publishes it. **Read when:** a change must reach the phones through the Studio, or you touch `tools/studio_publish.py`. Sibling of [ha-operations](ha-operations.md).

A publish from the owner's Studio reaches every phone at once, so it is a live change too. It goes only through [`tools/studio_publish.py`](../../../tools/studio_publish.py) (stdlib, tested against a stub Studio), never by calling the Studio API, never by editing its data directory; [`studio_guard.py`](../../../tools/hooks/studio_guard.py) refuses both. 

Commands: `status`, `check`, `apply [--publish]`, `publish`, `rollback`, each with `CHANGE_DIR` under `build/studio-publish/`; `apply`, `publish` and `rollback` need `--reason`.

- **Who.** Lanes build a change and its evidence. Only the orchestrator's dispatched publish step (the orchestrator or the menial) runs `apply`, `publish` and `rollback`. `status` and `check` are open to every agent.
- **Scope guard.** A publish ships the whole draft. The tool refuses unless `open-check` and `draftIsLive` say the draft equals what the app serves, so the owner's unpublished edits are never shipped; while they exist, publishes wait.
- **Order.** `check` (read only: identity, revision, base document, scope, validation, evidence bound to the candidate's hash), then `apply` (record the prior document and live revision, then `PUT draft` with `expectedRevision`), then `publish` (re-read, `ha/publish` with `expectedRevision`, confirm). A 409 means rebuild: never retried.
- **Rollback.** The Studio keeps no draft history and `ha/rollback` leaves the draft alone, so `rollback` restores both sides from the saved prior copy (`build/studio-publish/<id>/prior.json`, mode 600, git-ignored). The draft is restored only while it still sits at the revision the tool left; an aged-out live entry is republished from the prior document.
- **Log.** One line per attempt in `~/hass-agents/studio-publish.jsonl` (revisions, hashes, result, security flag; no document, no secret). The same security flag as `apply` applies.
- **Auth.** The Studio at 4801 runs without a token; the tool sends `STUDIO_AUTH_TOKEN` only when that variable is set and the Studio answers 401. It never reads a credential file.
