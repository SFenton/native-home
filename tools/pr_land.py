#!/usr/bin/env python3
"""Gate and merge a pull request (``tools/pr_land.sh N``).

GitHub Free on a private repository enforces neither rulesets nor auto-merge, so this script is the gate. The
decision logic (:func:`checks_state`, :func:`review_state`) is pure so ``tools/tests/test_pr_land.py`` can test it.
"""

from __future__ import annotations

import argparse
import contextlib
import fcntl
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple
from urllib.parse import urlparse


MAX_ROUNDS = 2
#: Check names that must be present and green: the aggregate job of .github/workflows/pr-checks.yml (self-hosted runner);
#: a PR without that check counts as still pending.
REQUIRED_CHECKS: List[str] = ["pr-checks"]
GOOD_CONCLUSIONS = {"SUCCESS", "NEUTRAL", "SKIPPED"}
#: The triage config next to this file; ``merge_guard`` pins it (with this script) to the base branch's copy, so a pull request
#: cannot change what the gate asks for.
CONFIG_PATH = Path(__file__).resolve().parent / "triage" / "config.json"


def load_config(path: Optional[Path] = None) -> Dict[str, Any]:
    """The triage config, or ``{}`` when it cannot be read (the defaults then apply: checks required, denylist optional)."""
    try:
        data = json.loads((path or CONFIG_PATH).read_text())
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def required_checks(cfg: Optional[Dict[str, Any]] = None) -> List[str]:
    """Check names that must be green: :data:`REQUIRED_CHECKS`, or none when the config says ``"require_checks": false``
    (owner, 2026-11-07: review-only merges in the private repo; a repo with hosted CI sets it true or leaves it out)."""
    cfg = load_config() if cfg is None else cfg
    return [] if cfg.get("require_checks") is False else list(REQUIRED_CHECKS)


@contextlib.contextmanager
def checked_out(number: str, head: str, base: str):
    """Yield ``(head_repo, base_dir)``: the exact PR head as a clean checkout of a shared clone (so house_scan can tell git objects
    from secrets) and the base branch's tree extracted from ``git archive`` (the **trusted** copies of the tools and the config the head
    is judged by; ``None`` when no base is named or it cannot be read). ``head_repo`` is ``None`` when the head cannot be read."""
    tmp = tempfile.mkdtemp(prefix="pr-land-")
    try:
        run(["git", "fetch", "-q", "origin", f"refs/pull/{number}/head"], check=False)
        head_repo = Path(tmp) / "head"
        cloned = subprocess.run(["git", "clone", "-q", "--shared", "--no-checkout", "-c", "core.hooksPath=/dev/null", ".", str(head_repo)],
                                capture_output=True, text=True)
        checkout = (subprocess.run(["git", "-C", str(head_repo), "-c", "core.hooksPath=/dev/null", "checkout", "-q", "--detach", head],
                                   capture_output=True, text=True) if cloned.returncode == 0 else cloned)
        base_dir: Optional[Path] = None
        if base:
            tar = subprocess.run(["git", "archive", "--format=tar", f"origin/{base}"], capture_output=True)
            if tar.returncode == 0:
                base_dir = Path(tmp) / "base"
                base_dir.mkdir()
                subprocess.run(["tar", "-x", "-C", str(base_dir)], input=tar.stdout, check=True)
        yield (head_repo if checkout.returncode == 0 else None), base_dir
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def denylist_gate(number: str, head: str, required: bool, base: str = "") -> Optional[str]:
    """Scan the exact PR head for terms of the owner's local denylist. Returns a refusal reason, or ``None`` to go on.

    House_scan reads the list; this prints counts and ``path:line`` only. A list that is not loaded warns and continues, or refuses
    when ``required`` (the ``denylist_required`` config key). The head is fetched as ``refs/pull/N/head``; a head that cannot be read
    refuses once a list is loaded. The head is judged by the **base's** ``contracts/house_scan.json`` (``--config``), never its own
    (its ``skip_prefixes`` could hide its hits); with no readable base the defaults apply (nothing is skipped). Property lists and
    SVGs are read too.
    """
    import house_scan
    if not house_scan.load_denylist():
        if required:
            return "denylist not loaded and denylist_required is true"
        print("pr_land: warning: denylist not loaded, the head was not scanned for house terms", file=sys.stderr)
        return None
    with checked_out(number, head, base) as (head_repo, base_dir):
        if head_repo is None:
            return f"cannot read the head {head[:10]} to scan it for the denylist"
        config = (base_dir / "contracts" / "house_scan.json") if base_dir else Path(tempfile.gettempdir()) / "no-such-house-scan.json"
        command = [sys.executable, str(Path(__file__).resolve().parent / "house_scan.py"), "denylist", "--root", str(head_repo),
                   "--required", "true" if required else "false", "--config", str(config)]
        if base_dir:  # only the hits the PR adds against its base count; debt still being scrubbed must not block every PR
            command += ["--base-root", str(base_dir)]
        proc = subprocess.run(command, capture_output=True, text=True)
    if proc.returncode:
        return "denylist: " + " ".join((proc.stdout or proc.stderr).split())[:400]
    return None


def local_gates(number: str, head: str, base: str) -> Optional[str]:
    """The checks ``require_checks: false`` would otherwise drop, run locally on the exact head with the **base's** copies of the tools
    and of ``contracts/house_scan.json`` (a PR cannot loosen its own gate): ``house_scan check`` (every rule, the debt ratchet) and
    ``pattern_guard``. The full tool and Swift suites stay dropped (they need CI). Returns a refusal reason, or ``None``. Fails closed:
    with no readable base or head, nothing is trusted to judge by."""
    with checked_out(number, head, base) as (head_repo, base_dir):
        if head_repo is None:
            return f"cannot read the head {head[:10]} to run the local checks"
        if base_dir is None:
            return f"cannot read origin/{base or '?'} to run the local checks with its tools"
        scan = subprocess.run([sys.executable, "-I", str(base_dir / "tools" / "house_scan.py"), "check", "--root", str(head_repo),
                               "--config", str(base_dir / "contracts" / "house_scan.json")], capture_output=True, text=True)
        if scan.returncode:
            shown = [line for line in (scan.stdout or scan.stderr).splitlines() if not line.lstrip().startswith(("note:", "debt "))]
            return "house_scan: " + " ".join(" ".join(shown).split())[:400]
        guard = base_dir / "tools" / "pattern_guard.py"
        if guard.is_file():
            patterns = subprocess.run([sys.executable, "-I", str(guard), "--root", str(head_repo), "check"], capture_output=True, text=True)
            if patterns.returncode:
                return "pattern_guard: " + " ".join((patterns.stdout or patterns.stderr).split())[:400]
    return None


#: Kill switches: the triage runner exports the first (its ``PAUSED`` file); the second is the owner's.
KILL_FILES = (("HASS_TRIAGE_PAUSED_FILE", None), (None, "~/.config/fenton-hass/NO_LAND"))


def review_file_name(branch: str) -> str:
    """``build/review/`` file name for a branch (``/`` becomes ``__``, which no branch name ambiguates)."""
    return branch.replace("/", "__") + ".json"


def kill_switch(environ: Optional[Dict[str, str]] = None) -> Optional[str]:
    """The path of a kill-switch file that exists, or ``None``."""
    env = os.environ if environ is None else environ
    for var, fixed in KILL_FILES:
        path = env.get(var, "") if var else os.path.expanduser(fixed or "")
        if path and Path(path).exists():
            return path
    return None


def _run_stamp(item: Dict[str, Any]) -> Tuple[str, int]:
    """Sort key of a check run: ``(startedAt, tiebreak)``; the larger is the newer.

    A run without ``startedAt`` (``gh`` prints the zero time ``0001-01-01T00:00:00Z``) that has not completed
    (queued) is the newest ("9999"); a COMPLETED one without it is
    the oldest (""). On an equal ``startedAt`` the less green run wins (tiebreak 0 for a clean SUCCESS, 1 otherwise),
    so a tie can only make the gate stricter.
    """
    started = str(item.get("startedAt") or "")
    if started.startswith("0001-"):  # gh reports a missing timestamp as the zero time, not as empty
        started = ""
    if not started:
        started = "" if str(item.get("status") or "").upper() == "COMPLETED" else "9999"
    clean = (str(item.get("status") or "").upper() == "COMPLETED"
             and str(item.get("conclusion") or "").upper() == "SUCCESS")
    return started, 0 if clean else 1


def _run_key(item: Dict[str, Any]) -> Tuple[str, str, str]:
    """``(workflowName, name, app)``; ``app`` is the ``detailsUrl`` host (the app slug if the item has one), only when
    there is no workflow. ``gh`` does not export ``app``, so the host is the key that works in practice."""
    workflow = str(item.get("workflowName") or "")
    app = ""
    if not workflow:
        host = urlparse(str(item.get("detailsUrl") or "")).netloc
        slug = (item.get("app") or {}).get("slug") if isinstance(item.get("app"), dict) else None
        app = str(host or slug or "")
    return workflow, str(item.get("name") or ""), app


def latest_runs(rollup: Optional[List[Dict[str, Any]]]) -> List[Dict[str, Any]]:
    """The rollup with only the newest check run per ``(workflowName, name)``; commit statuses pass through.

    Every run on the head SHA stays in ``statusCheckRollup``, so a PR re-run after a failure (close and reopen, or
    ``gh run rerun``) still lists the superseded failures. The newest run by ``startedAt`` wins, and one that has not
    started yet (queued, no ``startedAt``) counts as the newest, so a queued re-run reads as pending, not green; a
    COMPLETED run with no ``startedAt`` is the oldest. Without a ``workflowName`` (a non-Actions app) the ``detailsUrl``
    host (or app slug) joins the key, so two apps posting the same check name stay separate. See :func:`_run_stamp`
    for ties.
    """
    latest: Dict[Tuple[str, str, str], Dict[str, Any]] = {}
    order: List[Any] = []
    for item in rollup or []:
        if "status" not in item and "conclusion" not in item:  # commit status: GitHub already keeps the latest
            order.append(item)
            continue
        key = _run_key(item)
        if key not in latest:
            order.append(key)
        elif _run_stamp(item) < _run_stamp(latest[key]):
            continue
        latest[key] = item
    return [latest[entry] if isinstance(entry, tuple) else entry for entry in order]


def checks_state(rollup: Optional[List[Dict[str, Any]]], required: Sequence[str] = ()) -> Tuple[str, str]:
    """``(state, detail)`` for a ``statusCheckRollup``: ``none``, ``green``, ``pending`` or ``failed``.

    Only the newest run of each check counts (:func:`latest_runs`). A name in ``required`` must be a check run that
    concluded SUCCESS: absent, still running, or only a plain commit status of that name counts as pending, and a
    SKIPPED or NEUTRAL required check counts as failed (the aggregate job ``pr-checks`` is the gate; a skipped one
    means it did not vouch for the head).
    """
    rollup = latest_runs(rollup)
    runs = {item.get("name") for item in rollup if "status" in item or "conclusion" in item}
    missing = [name for name in required if name not in runs]
    weak = [item.get("name") for item in rollup
            if item.get("name") in required and str(item.get("status") or "").upper() == "COMPLETED"
            and str(item.get("conclusion") or "").upper() != "SUCCESS"]
    if not rollup and not missing:
        return "none", "no checks configured"
    pending: List[str] = list(missing)
    failed: List[str] = []
    for item in rollup:
        name = item.get("name") or item.get("context") or "check"
        if "state" in item and "conclusion" not in item and "status" not in item:  # commit status
            value = str(item.get("state") or "").upper()
            if value == "SUCCESS":
                continue
            (pending if value in ("PENDING", "EXPECTED", "") else failed).append(name)
            continue
        if str(item.get("status") or "").upper() != "COMPLETED":
            pending.append(name)
            continue
        if str(item.get("conclusion") or "").upper() not in GOOD_CONCLUSIONS:
            failed.append(name)
    failed += [name for name in weak if name not in failed]
    if failed:
        return "failed", "failing: " + ", ".join(failed)
    if pending:
        return "pending", "still running or missing: " + ", ".join(pending)
    return "green", "all checks green"


def reviewer_identity_problem(review: Dict[str, Any]) -> Optional[str]:
    """Why a verdict does not carry the reviewer's identity (``reviewer.agent_type == "reviewer"`` and a session id, which only
    ``tools/review/record.py`` run by the reviewer writes; ``tools/hooks/review_guard.py`` keeps every other writer out), or ``None``."""
    who = review.get("reviewer")
    if not isinstance(who, dict) or who.get("agent_type") != "reviewer" or not str(who.get("session_id") or "").strip():
        return "the review has no reviewer identity (only the reviewer's tools/review/record.py writes one): run the reviewer again"
    return None


def review_state(review: Optional[Dict[str, Any]], head: str) -> Tuple[bool, str]:
    """``(ok, detail)``: does the recorded review let the PR land? The review must be for exactly ``head`` and carry the reviewer's identity."""
    if not review:
        return False, "no review recorded (run the reviewer, then tools/review/record.py)"
    missing = reviewer_identity_problem(review)
    if missing:
        return False, missing
    recorded = str(review.get("head") or "")
    if not recorded or not head or recorded != head:
        return False, f"review is for {recorded[:8] or 'no commit'} but the PR head is {head[:8] or 'unknown'}; review again"
    verdict = review.get("verdict")
    findings = review.get("findings") or []
    blockers = [f for f in findings if f.get("severity") == "blocker"]
    if verdict == "pass" and not blockers:
        return True, "review passed"
    if verdict == "blocker" or blockers:
        return False, f"review has {len(blockers) or 1} blocker(s): " + "; ".join(
            str(f.get("detail", ""))[:80] for f in blockers[:3])
    if verdict == "changes":
        rnd = int(review.get("round") or 1)
        if rnd >= MAX_ROUNDS:
            return True, f"review asked for changes in round {rnd} with no blocker; landing"
        return False, f"review asked for changes (round {rnd} of {MAX_ROUNDS}); fix the findings and review again"
    return False, f"unknown review verdict {verdict!r}"


def run(args: List[str], check: bool = True) -> subprocess.CompletedProcess:
    proc = subprocess.run(args, capture_output=True, text=True)
    if check and proc.returncode:
        raise RuntimeError(f"{' '.join(args[:4])}: {(proc.stderr or proc.stdout).strip()[:300]}")
    return proc


def worktrees() -> List[Dict[str, str]]:
    out = run(["git", "worktree", "list", "--porcelain"]).stdout
    return [dict(line.split(" ", 1) for line in block.splitlines() if " " in line) for block in out.split("\n\n")
            if block.strip()]


def find_review(branch: str, explicit: Optional[str]) -> Optional[Dict[str, Any]]:
    """The review file: ``explicit``, else this checkout, the PR branch's own worktree, then the main checkout."""
    name = review_file_name(branch)
    trees = worktrees()
    candidates = [Path(explicit)] if explicit else [Path(run(["git", "rev-parse", "--show-toplevel"]).stdout.strip())]
    if not explicit:
        candidates += [Path(t["worktree"]) for t in trees if t.get("branch") == f"refs/heads/{branch}"]
        candidates.append(Path(trees[0]["worktree"]))
        candidates = [c / "build" / "review" / name for c in candidates]
    for path in candidates:
        if path.is_file():
            try:
                return json.loads(path.read_text())
            except ValueError:
                return None
    return None


def inside(path: Path, other: Path) -> bool:
    """Is ``other`` the same as or below ``path``?"""
    try:
        Path(os.path.realpath(other)).relative_to(os.path.realpath(path))
        return True
    except ValueError:
        return False


def reap_blocker(main: Path, path: Path, head: str, cwd: Optional[Path]) -> str:
    """Why the merged lane's worktree must stay (``ci_hygiene.reap_blocker``: locked, dirty or untracked files, a devcap hold or
    live process with its cwd inside, a hand-off note), '' when it can go. Anything unreadable keeps it."""
    try:
        import ci_hygiene
        tree = next((t for t in ci_hygiene.list_worktrees(main) if os.path.realpath(t["path"]) == os.path.realpath(path)), None)
        if tree is None:
            return "not listed by git"
        return ci_hygiene.reap_blocker(tree, head, main, ci_hygiene.devcap_cwds(), ci_hygiene.live_process_cwds(), cwd)
    except Exception as exc:  # noqa: BLE001 - best effort, never fail the merge
        return f"could not check it: {type(exc).__name__}"


def safe_cleanup(branch: str, head: str, keep: bool) -> str:
    """:func:`cleanup` that can never fail or change the result of a merge that already happened."""
    try:
        return cleanup(branch, head, keep)
    except Exception as exc:  # noqa: BLE001
        return f"; worktree cleanup skipped ({type(exc).__name__}: {str(exc)[:80]})"


def cleanup(branch: str, head: str, keep: bool, cwd: Optional[Path] = None) -> str:
    """Remove the lane worktree and local branch for a merged ``branch``, or say how to.

    Only removed when the local tip is exactly the merged ``head`` (nothing unpushed is lost), the worktree does not
    hold the caller's working directory and ``keep`` is off. Otherwise it is kept and the command is printed.
    """
    trees = worktrees()
    main = Path(trees[0]["worktree"])
    for tree in trees[1:]:
        if tree.get("branch") != f"refs/heads/{branch}":
            continue
        path = Path(tree["worktree"])
        manual = f"git -C {main} worktree remove {path} && git -C {main} branch -D {branch}"
        tip = run(["git", "-C", str(main), "rev-parse", f"refs/heads/{branch}"], check=False).stdout.strip()
        if keep:
            return f"; worktree {path.name} kept (--keep-worktree); remove with: {manual}"
        if tip != head:
            return f"; worktree {path.name} kept (local tip {tip[:8]} is not the merged {head[:8]}); remove with: {manual}"
        if inside(path, cwd or Path.cwd()):
            return f"; worktree {path.name} kept (you are inside it); remove with: {manual}"
        why = reap_blocker(main, path, head, cwd)
        if why:
            return f"; worktree {path.name} kept ({why}); remove with: {manual}"
        removed = run(["git", "-C", str(main), "worktree", "remove", str(path)], check=False)
        if removed.returncode:
            return f"; worktree {path.name} kept ({(removed.stderr or '').strip()[:80]}); remove with: {manual}"
        run(["git", "-C", str(main), "branch", "-D", branch], check=False)
        # Xcode leaves the worktree's DerivedData behind (tens of GB over a week): drop what no project owns any more.
        run([sys.executable, str(Path(__file__).resolve().parent / "ci_hygiene.py"), "derived-orphans"], check=False)
        return f"; removed worktree {path.name}"
    return ""


def owner_session(environ: Optional[Dict[str, str]] = None, tty: Optional[bool] = None) -> bool:
    """Is this the owner at an interactive terminal (what ``ack-base`` demands)? Never a runner or agent session."""
    env = os.environ if environ is None else environ
    if env.get("FENTON_HEADLESS") == "1" or env.get("HASS_TRIAGE_ISSUE"):
        return False
    return sys.stdin.isatty() if tty is None else tty


GATE_TIMEOUT = 1800.0  # Jev may take a while; the gate itself fails closed on its own errors


def confirm_head_on_tty(number: str, head: str, tty_path: str = "/dev/tty") -> bool:
    """``--owner-ack`` asks the owner to type the PR head SHA at the terminal (``/dev/tty``, not stdin or an environment
    variable), so a script cannot answer it by accident. True only when the typed text is the full head SHA."""
    try:
        with open(tty_path, "a") as out:
            out.write(f"--owner-ack skips the app-UI gate for #{number}. Type the head SHA ({head}) to confirm: ")
            out.flush()
        with open(tty_path) as tty:
            return tty.readline().strip().lower() == head.lower() != ""
    except OSError:
        return False


class GateRefused(Exception):
    """The app-UI gate said no, or could not run (always a block)."""

    def __init__(self, message: str, kind: str = "gate"):
        super().__init__(message)
        self.kind = kind


def _git(repo: Path, *args: str) -> subprocess.CompletedProcess:
    """git with hooks, fsmonitor and the ssh command overridden, as the lander does (the clone is never trusted)."""
    return subprocess.run(["git", "-C", str(repo), "-c", "core.hooksPath=/dev/null", "-c", "core.fsmonitor=false",
                           "-c", "core.sshCommand=ssh", "-c", "protocol.ext.allow=never", *args],
                          capture_output=True, text=True, env={**os.environ, "GIT_TERMINAL_PROMPT": "0", "GIT_NO_REPLACE_OBJECTS": "1"})


@contextlib.contextmanager
def gate_lock(root: Path):
    """``<root>/gate.lock`` (``fcntl.flock``), the lock ``lane_land.gate_lock`` takes: one gate at a time per agent root."""
    root.mkdir(parents=True, exist_ok=True)
    with open(root / "gate.lock", "w") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(handle, fcntl.LOCK_UN)


#: The trusted origin and the bases the app-UI gate will judge, hard-coded so editing ``tools/triage/config.json`` cannot point the
#: trusted clone at a fork. Change them here, in a reviewed PR, when the product moves.
PRODUCT_REPO = "SFenton/Fenton-HASS-Native"
ALLOWED_BASES = ("main",)


def expected_origin(cfg: Dict[str, Any]) -> str:
    """``https://github.com/<PRODUCT_REPO>.git``, never this checkout's ``origin`` remote (the PR can change that) and never a repo
    the config names: a config ``product_repo`` that differs from :data:`PRODUCT_REPO` is refused."""
    repo = str(cfg.get("product_repo") or "")
    if repo != PRODUCT_REPO:
        raise GateRefused(f"the triage config's product_repo is {repo!r}, not {PRODUCT_REPO}: the app-UI gate will not clone it")
    return f"https://github.com/{PRODUCT_REPO}.git"


def trusted_gate_clone(root: Path, origin: str, base: str) -> Path:
    """``<root>/gate-trusted/<repo>`` as a clean detached checkout of ``origin/<base>`` (the PR's base branch). The gate's code, its
    Jev questions and ``agent_eval_measure.py`` all come from here. This checkout's ``lane_land.py`` is never imported or run:
    a PR that edits it must still be judged by the base copy. ``origin`` is forced back to the expected URL, the caller holds
    :func:`gate_lock` (the same ``<root>/gate.lock`` as the gate), and one failed fetch re-clones once before failing closed."""
    import shutil

    name = os.path.basename(origin.rstrip("/")).removesuffix(".git") or "repo"
    clone = root / "gate-trusted" / name
    root.mkdir(parents=True, exist_ok=True)
    for attempt in (1, 2):
        if not (clone / ".git").exists():
            clone.parent.mkdir(parents=True, exist_ok=True)
            cloned = subprocess.run(["git", "clone", "-q", origin, str(clone)], capture_output=True, text=True)
            if cloned.returncode != 0:
                raise GateRefused(f"could not clone {origin} for the gate: {cloned.stderr.strip()[:200]}")
        _git(clone, "remote", "set-url", "origin", origin)
        _git(clone, "merge", "--abort")
        _git(clone, "checkout", "-q", "-f", "--detach")
        _git(clone, "reset", "-q", "--hard")
        _git(clone, "clean", "-ffdxq")
        fetched = _git(clone, "fetch", "-q", "--prune", "origin", "+refs/heads/*:refs/remotes/origin/*")
        sha = _git(clone, "rev-parse", "--verify", "-q", f"refs/remotes/origin/{base}").stdout.strip() if fetched.returncode == 0 else ""
        if sha and _git(clone, "checkout", "-q", "-f", "--detach", sha).returncode == 0:
            _git(clone, "clean", "-ffdxq")
            return clone
        if attempt == 2:
            raise GateRefused(f"could not fetch {base} for the gate: {fetched.stderr.strip()[:200] or 'branch missing'}")
        shutil.rmtree(clone, ignore_errors=True)
    raise GateRefused("unreachable")


def ui_gate(number: str, info: Dict[str, Any]) -> str:
    """The app-UI gate for this pull request, run as ``python3 -I <gate-trusted clone>/tools/lane_land.py gate --pr N``: the code,
    the Jev questions and ``agent_eval_measure.py`` all come from a clean checkout of the PR's base branch, never from this
    checkout. Needs a design decision record plus Jev's verdict (``design.matches_request`` or ``design.app_wide``, the lander's
    thresholds). Raises :class:`GateRefused`; any other failure also stops the merge. Returns a note."""
    base, head = str(info.get("baseRefName") or ""), str(info.get("headRefOid") or "")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._/-]*", base) or ".." in base:
        raise GateRefused("the pull request has no readable base branch")
    if base not in ALLOWED_BASES:
        raise GateRefused(f"the pull request base {base} is not one of {', '.join(ALLOWED_BASES)}: the app-UI gate will not judge it")
    root = Path(os.path.expanduser("~/hass-agents"))
    try:
        cfg = json.loads((Path(__file__).resolve().parent / "triage" / "config.json").read_text())
    except (OSError, ValueError) as exc:
        raise GateRefused(f"cannot read the triage config for the app-UI gate: {exc}")
    origin = expected_origin(cfg)
    env = {k: v for k, v in os.environ.items() if not k.startswith("PYTHON")}
    with gate_lock(root):  # held until the gate process exits: nobody re-preps the clone under it
        trusted = trusted_gate_clone(root, origin, base)
        script = trusted / "tools" / "lane_land.py"
        if not script.is_file():
            raise GateRefused(f"{base} has no tools/lane_land.py: the app-UI gate cannot run, so it fails closed")
        proc = subprocess.run([sys.executable, "-I", str(script), "gate", "--pr", number, "--head", head, "--root", str(root), "--lock-held"],
                              capture_output=True, text=True, timeout=GATE_TIMEOUT, env=env, cwd=os.getcwd())
    if proc.returncode != 0:
        raise GateRefused((proc.stderr or proc.stdout).strip().replace("lane_land gate: ", "")[:600] or f"gate exit {proc.returncode}")
    return (proc.stdout.strip().splitlines() or ["app-UI gate passed"])[-1]


def land(number: str, dry_run: bool, review_path: Optional[str], keep_worktree: bool = False,
         owner_ack: bool = False) -> Tuple[int, str]:
    if review_path and not dry_run:
        return 2, f"failed #{number}: --review FILE is only for --dry-run"
    if owner_ack and not owner_session():
        return 2, f"failed #{number}: --owner-ack is owner-only: run it from your own terminal, never from an agent or runner session"
    paused = kill_switch()
    if paused:
        return 1, f"blocked #{number}: landing paused ({paused})"
    info = json.loads(run(["gh", "pr", "view", number, "--json",
                           "state,isDraft,headRefName,headRefOid,statusCheckRollup,mergeable,baseRefName,labels,files,body,title,author"]).stdout)
    if info["state"] != "OPEN":
        return 1, f"blocked #{number}: pull request is {info['state'].lower()}"
    if any((label.get("name") if isinstance(label, dict) else label) == "Needs Decision"
           for label in info.get("labels") or []):
        return 1, f"blocked #{number}: labelled Needs Decision; an owner-only item (fixed set, or an app-UI gate park), so the owner decides first (reply on the issue, or merge the PR to accept)"
    if info.get("mergeable") == "CONFLICTING":
        return 1, f"blocked #{number}: merge conflicts with {info.get('baseRefName', 'main')}"
    cfg = load_config()
    if cfg.get("require_checks") is False:
        detail = "checks not required (review-only)"
    else:
        state, detail = checks_state(info.get("statusCheckRollup"), required_checks(cfg))
        if state in ("pending", "failed"):
            return 1, f"blocked #{number}: {detail}"
    ok, why = review_state(find_review(info["headRefName"], review_path), info["headRefOid"])
    if not ok:
        return 1, f"blocked #{number}: {why}"
    if owner_ack:
        if not confirm_head_on_tty(number, info["headRefOid"]):
            return 1, f"blocked #{number}: --owner-ack needs the PR head SHA ({info['headRefOid']}) typed at the terminal"
        gate = "app-UI gate skipped by --owner-ack (head SHA confirmed at the terminal)"
    else:
        try:
            gate = ui_gate(number, info)
        except GateRefused as exc:
            return 1, f"blocked #{number}: app-UI gate ({exc.kind}): {exc}"
        except (RuntimeError, ValueError, KeyError, OSError, subprocess.SubprocessError) as exc:
            return 1, f"blocked #{number}: app-UI gate failed closed: {exc}"
    why = f"{why}; {gate}"
    base_name = str(info.get("baseRefName") or "")
    if cfg.get("require_checks") is False:  # no CI to run them: run the cheap ones here, on the exact head, with the base's tools
        refused = local_gates(number, info["headRefOid"], base_name)
        if refused:
            return 1, f"blocked #{number}: {refused}"
        detail += "; house_scan and pattern_guard run locally"
    refused = denylist_gate(number, info["headRefOid"], cfg.get("denylist_required") is True, base_name)
    if refused:
        return 1, f"blocked #{number}: {refused}"
    if dry_run:
        return 0, f"would merge #{number} ({detail}; {why})"
    if info.get("isDraft"):
        run(["gh", "pr", "ready", number])
    run(["gh", "pr", "merge", number, "--squash", "--match-head-commit", info["headRefOid"]])
    branch = info["headRefName"]
    run(["git", "push", "origin", "--delete", branch], check=False)
    return 0, f"merged #{number} ({detail}; {why}){safe_cleanup(branch, info['headRefOid'], keep_worktree)}"


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(allow_abbrev=False, description="Land a pull request through the gate.")
    parser.add_argument("number")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--review", help="review file to use (dry run only)")
    parser.add_argument("--owner-ack", action="store_true",
                        help="owner only (interactive terminal): skip the app-UI gate for this pull request")
    parser.add_argument("--keep-worktree", action="store_true", help="leave the lane worktree and local branch")
    args = parser.parse_args(argv)
    try:
        code, line = land(args.number.lstrip("#"), args.dry_run, args.review, args.keep_worktree, args.owner_ack)
    except (RuntimeError, ValueError, KeyError, OSError) as exc:
        code, line = 2, f"failed #{args.number}: {exc}"
    print(line)
    return code


if __name__ == "__main__":
    sys.exit(main())
