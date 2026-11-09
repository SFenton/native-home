# Eval gate

The check every change to agents, skills, hooks, Jev questions or the triage runner passes before the runner lands it
(`tools/agent_eval.py`; plan section 6). Run it yourself with `python3 tools/agent_eval.py` before you push a lane.

## Tiers

| Tier | When | What | Cost |
|---|---|---|---|
| 0 routing replay | every lane | `evals/agents/routing-replay/cases/*.json`: recorded incidents of deterministic code paths (routing, the Jev gate, the retro digest, the Stop hook, the merge guard, the lander's checks, the review round cap) replayed against the lane's code. Jev answers are recorded, so no key and no network | seconds |
| 1 Jev re-measurement | a lane that changes `contracts/jev/questions/*.json` (`FENTON_EVAL_BASE` or `--base`) | the **lane's question** (`instructions`, `criteria`, `type`, read with `git show <lane sha>:<path>` and parsed as data) is asked about the **base's** held-out `test` items by **trusted** code: `tools/agent_eval_measure.py` in a `python3 -I` child whose `sys.path` is the trusted `tools/` plus the standard library, using the trusted `jev_ask`. No lane `measure.py` and no lane `tools/` file runs (a lane `tools/hashlib.py` has no effect), and results go to a temp dir, never a tracked results file. Precision at the lane's `accept.yes_above` must reach the lane's `target.precision` (the lander's threshold check already forbids loosening either), and AUC may not fall more than 0.02 below the base's recorded one. Jev unavailable fails. An *active* question that cannot be measured (no probe, no held-out set, not a single yes/no) fails too, unless the lane sets it to `shadow` or only tightens its bands | Jev calls |
| 2 behaviour replay | weekly, in the Steward's job (`--tier 2`); `lane_land` never runs it | enabled cases of the **trusted** `evals/agents/agent-behaviour/cases` through `claude -p` (no tools, temp cwd), capped by that folder's `config.json` (cases, dollars, model, timeout). A case a lane added is reported ("lane case not run: tier 2 runs trusted cases only") and never run | nothing while every case is disabled |

## What `lane_land` runs

1. **Eval first, in a fresh checkout.** The land clone is reset to the lane SHA (forced detach, `clean -ffdx`, empty
   `status --porcelain`) before any of the lane's own tests have run.
2. **From the trusted base.** `python3 <trusted>/tools/agent_eval.py --root <trusted> --target <lane clone>`. The harness and the
   cases are the base's. Each case executes the lane's code in its own `python3 -I` process (`tools/agent_eval_case.py`), which
   is handed only the case's `kind` and `input`; the comparison with `expect` happens in the trusted parent. A lane that patches
   `compare`, edits the Stop hook to reach the harness, or exits early changes only its own child: the case fails. Every case
   file (trusted and lane) is read into memory before the first child starts; a child gets its case on stdin (never a path to a
   case file), runs in a temp cwd, and so cannot rewrite a later case.
   **Ordering rule:** every trusted read (scripts, cases, probes, held-out items, recorded rows, question contents) happens
   before the first lane-code child, and tier 1 (the Jev re-measurement, which runs no lane code) runs before tier 0, so the
   trusted measure script, `jev_ask.py` and the question files are read before lane code has run. The measuring process gets
   a fresh, empty `JEV_HOME` in a new temp dir (no cache reuse, so a planted cache answer cannot be read). Lane code runs as
   the owner's macOS user, so it can modify files the runner trusts; the owner accepted this residual on 2026-11-02 (detection
   over prevention). The gate reduces exposure by doing every trusted read before lane code runs; a deliberately malicious lane
   that slips past the independent review could still tamper with the runner's state.
3. **The trusted base runs the same thing first** (plain `python3 tools/agent_eval.py`, cached per base SHA). The lane passes
   when its failing ids are a subset of the base's and it ran at least as many cases (retired ones count). Then the lane's own
   test command runs the same way.
4. **The reviewed SHA is the only thing that merges.** `lane_land.land(..., expected_sha=)` takes the lane tip the runner saw
   (every lane's `ls-remote` tip; for an automatic revert, the recorded `revert_sha`). It refuses when the tip fetched at the
   start differs, fetches again and re-checks immediately before the merge, and merges that SHA object, not the branch name,
   so a push after the check cannot change what lands.

## Cases

* A case is `cases/<id>.json` with `source` (what happened, the date), `kind`, `input` and `expect`; kinds are in the
  routing-replay README. Add one after each incident, for the behaviour *as it should now be*; check it fails without the fix.
* Cases are **append-only**. A lane may add a case (it runs from the lane's folder, compared in the parent) but never edit or
  delete one; the base's copy of a name always wins.
* **Retire** by moving the file to `retired/` with `<id>.json.reason.json` (`target_removed`, `duplicate`, `owner_rule` or
  `mislabel`, each with checked evidence). Retired cases still run, report only, and still count in the total. A lane that
  retires a case may not change the questions or runners that use it.
* A lane changes agent behaviour *or* evals, never both. The runner, `agent_eval.py`, its shim, graders, schemas, READMEs and
  every `config.json` under `evals/` left the fixed set (owner, 2026-11-07, end-to-end autonomy): agents may change them, an
  independent reviewer passes the exact head first, and the append-only case trees stay append-only. `ImportClosureProtectedTests`
  (which kept the fixed set closed over what the runner imports) was retired with that unlock. What stays closed is the owner-kept set: a test
  (`ImportClosureOfTheKeptSetTests`, `ReleaseClosureTests` in `tools/tests/test_autonomy_kept_set.py`) derives everything the recorder, the review
  guard, the release tools and the `ios-release*` workflow steps import or run, and fails when any of it is not protected.

App-UI gate (owner, 2026-11-03): for a lane that changes app UI, `tools/lane_land.py` asks Jev itself, before any lane code runs, from the trusted base's `jev_ask` in a `python3 -I` child with a fresh `JEV_HOME` (`design.matches_request` with the `Owner-Request:` text, landing only on p>=0.8; otherwise `design.app_wide`, landing only on p<0.3); the lane's own `Gate:` line is documentation and must agree, and an unavailable Jev or a disagreement refuses with kind `gate`. A `Design:` citation only names a record that already exists on the base and does not skip Jev. Today the runner lands lanes only for `Workflow` sessions, whose request snapshot is refused, so every runner-landed lane is asked `design.app_wide`; `design.matches_request` runs only for a lander given a vouched request.

Fail-closed: an unreadable base, a case that leaves no result, an unreachable Jev, an unmeasurable active question and a
missing summary line all refuse the lane.
