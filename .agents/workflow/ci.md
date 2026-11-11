# CI

> **What:** what each workflow guards, the rules every workflow follows, and how an agent waits for a check. **Read when:** a check fails or hangs, you touch a workflow, or a pull request waits on CI.

## Workflows

| Workflow | Runs on | Guards |
|---|---|---|
| `pr-checks.yml` | Every pull request and every push to `main`; hosted runners | Repository checks, tool tests, the house-data scan, the app build, Smoke on iPhone, Duo and iPad, the journeys and Swift suites the diff reaches, and the coverage floor on the changed files. Its aggregate job `pr-checks` is the required check. |
| `ios-release.yml` | Every push to `main`; hosted runners | Tags the next version, builds, signs and uploads it ([versioning](versioning.md)). It runs no tests and does not wait for `pr-checks`. |
| `nightly.yml` | Dispatch only; the self-hosted Macs | The full device journeys on all three families and the coverage floor. |
| `release-health.yml` | Daily | One issue per silent release failure class. |
| `runtimes.yml` | Weekly | Smoke on the older supported iOS runtimes; advisory. |

Job names, runner labels, repository variables and schedules live in the workflow files under `.github/workflows/`.

## Merge gate

- The ruleset on `main` requires a pull request, a squash merge, and two checks on the exact head: `pr-checks` from CI and `ai-review` from the Reviewer. Nobody bypasses it. `tools/ruleset_gate.py` reads the live ruleset and `tools/pr_land.sh` arms nothing when it is weaker.
- The Reviewer posts `ai-review` only for a head with a recorded pass, so a new push leaves the pull request blocked while its head is unreviewed ([landing](pr-lifecycle.md#landing)).
- `pr-checks` fails a pull request from a fork or from an author outside the configured logins.
- A skipped job passes the aggregate only when its scope allows the skip; `tools/ci_aggregate.py` decides.

## Rules for workflows

- Pull-request jobs run on hosted runners only. Self-hosted runners run only trusted events: dispatch, a tag, a push to `main`.
- A hosted job uses plain `pull_request`, never `pull_request_target`; actions are pinned by commit SHA; top-level permissions are read-only and a job widens them only when it must. `tools/tests/test_hosted_workflows.py` lints these rules.
- Every job on a hosted Mac image carries the one repository-variable switch the same test checks.
- A tool-test failure already present on the pull request's base does not fail the pull request; only a new failure does (`tools/ci_new_failures.py`).
- Red tool tests on `main` file or update one workflow issue (job `report-red-main`); the next green run on `main` closes it (job `close-red-main`).
- A pull request that touches the Core or Design packages runs every Swift suite; any other app pull request runs the suites its diff reaches.
- A run on `main` is never cancelled by a newer run; a pull request's newer run cancels its older one.
- Every self-hosted job starts with the disk preflight of `tools/ci_hygiene.py`, and every compile or simulator run there takes a capacity hold ([capacity](token-economy.md#capacity)).
- A change under `.github/` waits for the owner's approval ([landing](pr-lifecycle.md#landing)).

## Nightly failures

- `tools/nightly_report.py` keeps one issue per failing area and comments on it while it keeps failing.
- An infra result files and closes nothing: a machine problem is not a code fix.
- Only a passing full run closes a nightly issue. An agent that merges a fix leaves the issue open for the next run to close ([triage-agent](triage-agent.md)).

## Waiting on CI

- Never poll `gh pr checks`. Start `tools/ci_wait.py N` through `tools/bg_run.py` in the background and end the turn ([waiting](token-economy.md#waiting)); its last line and exit status say what happened.
- A failing check means fix, push to the same branch, and review the new head.
- A conflicting pull request runs no checks: merge the base into the branch, test the touched area, push.
- A pull request blocked only on the owner's approval is reported, not retried.
