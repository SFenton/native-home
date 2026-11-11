---
name: triage-session
description: Runs one request or nightly failure unattended, from triage to a merged pull request and the runner's status file. Use as the orchestrator of a headless triage or nightly session.
---
# Triage session

> **What:** the order of work for one unattended request or nightly failure. **Read when:** the triage runner started you. Rules: [triage-agent](../../workflow/triage-agent.md), [autonomy](../../workflow/autonomy.md#levels). The prompt gives the issue, the branch, the comment command and the status file.

1. **Triage.** Write one sentence for what the owner sees when the work is done; the owner's words win over any summary. Decide bug or feature.
   - When the base already does what is asked, change nothing and finish `no_changes` with what you checked.
   - Several independent requests go in one pull request when small; otherwise file each as its own issue with the same labels and a link back, and finish `split`.
2. **Say what you found early.** Post the cause or the approach with the prompt's comment command: `comment <issue> --kind root-cause|approach --body-file F`, and `--media <png>::<caption>` for a screenshot.
3. **Decide by level.** Take the recommended option, say which in a `--kind decision` comment and keep working. A trade-off with nothing visible gets a decision note you judge yourself. A visible choice goes through [propose-first](../../workflow/propose-first.md): options built, the `designer` judges, the pick lands; post the options and the pick with screenshots.
4. **Reproduce** on the reported device family through a `coder` or `verifier`, following [fix-reported-issue](../fix-reported-issue/SKILL.md).
   - A nightly area `journeys-<family>` means UI tests failed on that family; `coverage` means a unit test failed or coverage fell under the gate.
   - A failure that does not reproduce in two runs is flaky: find the race and fix the test or the code; never loosen an assertion or add a skip.
5. **Simulators.** Subagents use only simulators whose names end in `(Triage)`, created when missing and passed as `FENTON_SIM_IPHONE`, `FENTON_SIM_DUO` and `FENTON_SIM_IPAD`. Anything the test scripts do not hold runs inside `python3 tools/devcap.py run --sim <UDID> --purpose "<intake> <issue>" -- <cmd>`. Shut down the simulators the session booted; touch nobody else's.
6. **Verify** the per-change tier only ([testing](../../testing/apple/README.md#test-tiers)). Run `xcodegen generate` in `apple/` after adding files. Unfolded Duo journeys follow [devices](../../testing/apple/devices.md).
7. **Ship.** Small commits whose messages end with `Refs <request repo>#<issue>`, never `Fixes`: the runner or the nightly run closes the issue. When the base moved, merge it in and test again.
   - Push, then open the pull request with `gh pr create --base <base>`: a "Before:" and an "After:" paragraph, how, the tests run, the issue link.
   - Review and arm it with the [land-pr](../land-pr/SKILL.md) skill. When `pr_land.sh` prints `blocked`, leave the pull request open and say why in the status file.
8. **Report.** Post a `--kind resolution` comment with what changed and a screenshot of each changed screen per device family; the prompt's `upload` command prints the screenshot objects. Never commit screenshots.
9. **Server side.** A cause on the Home Assistant server is fixed there with `tools/ha_change.py` ([ha-operations](../../platforms/apple/ha-operations.md)). When it exits with `rollback_failed`, say so in the resolution and file nothing: the runner alerts the owner.
10. **Status file,** written last. `tests_passed` is true only when every test you ran passed. `needs_decision` carries `decision.owner_only` and, when a pull request is open, `pr`. `blocked` carries `blocked_reason` and a note in `build/handoff/<topic>.md`.
11. **Never** print or commit a token or password, change signing, CI secrets or other repositories, touch checkouts outside the session's worktree, force-push, or push a branch other than the session's own and `agents/` lanes. Stop every server, watcher and simulator the session started.
