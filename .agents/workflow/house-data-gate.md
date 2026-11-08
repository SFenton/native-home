# House-data gate: the private denylist

The entity-id rules in [`tools/house_scan.py`](../../tools/house_scan.py) cannot see free text: a person's name, a room nickname, a device model, a street. The **denylist** is a private set of terms that identify the house. It catches that text before it reaches a public repo. The list is never committed and never printed.

## Where it lives

- `~/hass-agents/house_denylist.txt`, mode 600, outside every repo. One term per line; `#` starts a comment. Matching is whole-word and case-insensitive.
- Lookup order in `house_scan`: the file `HOUSE_SCAN_DENYLIST` names, then the file in the owner's private config folder, then the file in the agents' working folder in your home directory (both paths are in `tools/house_scan.py`). The first existing file wins; with none, the rule is skipped. Agents cannot write to the config folder (hooks protect it), which is why the third path exists.

## Who edits it

The owner, or agents under the owner's approval of 2026-11-07 (built from the values the scrub removed and a read-only pass over the live registries). Agents report **counts and `path:line` only**, never a term: not in chat, logs, PR bodies, status blocks or evidence.

## The three layers (target; the wiring lands in the autonomy-unlock PR and #380)

1. **Local:** `tools/ship.sh` and `tools/pr_land.sh` run `house_scan` and block on any denylist hit; `denylist_required` in [`tools/triage/config.json`](../../tools/triage/config.json) makes a missing list a block too.
2. **CI:** a job reads the list from the `HOUSE_SCAN_DENYLIST_B64` secret and reports a **count only**. It runs on same-repo events and is skipped for forks (they get no secrets).
3. **Going public:** [`tools/go_public_gate.py`](../../tools/go_public_gate.py) requires the list to be loaded and **0 hits**.

## The request repository name

The private request repository's name is a house value (`house_scan` rule `reponame`). Tooling reads it at runtime from local configuration
(`FENTON_REQUEST_REPO`, or the `request_repo` file in the owner's `fenton-hass` config folder, one `owner/name` line), never from the repo; see
[triage-agent](triage-agent.md#the-request-repository-local-setting). Docs say "the private request repo" and name nothing.

## Pre-push hook (owner, 2026-11-07)

In the public repo a push is visible before any Action runs, so the check runs on the Mac. `.githooks/pre-push` (a `sh` wrapper around [`tools/prepush_denylist.py`](../../tools/prepush_denylist.py)) scans the commits a push adds: those reachable from the pushed sha but not from the remote sha git gives the hook nor from anything the destination advertises at push time (below). It covers file contents, file paths, commit messages and author and committer names and emails; deletes are skipped. It prints counts and `path:line` (`path:path`, `sha:message`, `sha:author` for the rest), never a term, and exits 1 on any hit.

- The list comes from the same sources as `house_scan`. A hit, or a missing list or one under 20 terms, **refuses** a push to a public target (`PUBLIC_REPOS` in `tools/prepush_denylist.py`: `SFenton/native-home`, any URL form, any case). For any other remote it scans and only warns, so the private origin is not blocked by recorded debt.
- Already-public commits are skipped only if the destination advertises them right now: the hook runs `git ls-remote` on the push URL once per push (20 s bound, own process group, prompts off) and excludes the advertised shas that exist locally, for an updated branch and a new one alike. Local `refs/remotes/*` are never trusted (stale after a rewrite, or fetched from another URL). If `ls-remote` fails, times out, or the URL is rewritten by `insteadOf`/`pushInsteadOf`, nothing is excluded and the whole history is scanned. A locally made merge commit is new and is scanned. Tags (message, tagger, nested) and refs that point at a tree or blob are scanned. Blobs are scanned as bytes (UTF-8 and UTF-16, no size cap, no binary skip). Any git error refuses the push. A path that matches prints with the matching segments as `…`.
- `tools/go_public.sh` pushes the snapshot with the hook off; `go_public_gate.py` scans that snapshot first, so the gate, not the hook, covers it. API writes (`gh api` ref updates) never run a local hook.
- Install once per checkout with `tools/setup.sh` (sets `core.hooksPath` to `.githooks`, checks the hook is executable and `python3` exists, reports the list's term count). It is idempotent.
- The agent guard (`tools/hooks/commit_guard.py`) refuses `git push --no-verify`, `git config ... core.hooksPath` (set or unset, any scope), `-c` / `--config-env` naming `core.hooksPath` and `GIT_CONFIG*` assignments on a git command.
- Tests: `tools/tests/test_prepush_denylist.py`. A push of a few commits takes about a second.

## Keep the CI copy in sync

After every edit, and once on a new repo:

```
base64 -i ~/hass-agents/house_denylist.txt | tr -d '\n' | gh secret set HOUSE_SCAN_DENYLIST_B64 -R <owner>/<repo>
```

## When a hit is a product or brand name

Prune the term from the list. Never hide text from the scan with prefixes, split strings or interpolation: that defeats the gate and leaves the house data in place.

## Run it locally

```
python3 tools/house_scan.py report
```

`report` lists every denylist hit as `path:line denylist` and shows the count; `check` exits 0 for debt paths, so it is not a gate for denylist hits. `go_public_gate.py` counts every denylist hit, including in debt paths (landing with the autonomy-unlock PR). A list file looser than mode 600 prints a one-line warning to stderr (path and mode only).

Each denylist line reads `path:line denylist`: open that line and either scrub the house data (use a demo value from the house config) or, for a false positive, prune the term. The count at the top is what to report.
