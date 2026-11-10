#!/usr/bin/env python3
"""Arm auto-merge on a pull request (``tools/pr_land.sh N``) after the gates GitHub cannot run.

On SFenton/native-home GitHub is the merge gate: ruleset ``main-checks`` requires a pull request and the checks on the exact head
(``pr-checks`` and ``ai-review``, both required), and merges when they pass. This script runs only what GitHub cannot, then arms
``gh pr merge N --auto --squash --match-head-commit <head>``: the kill switch, ``Needs Decision``, conflicts, the app-UI gate (which holds the
owner-kept set), the house denylist, the author and fork check, an independent reviewer pass for that head
(:func:`review_verdict.has_pass`), the live ruleset (:mod:`ruleset_gate`) and the ``main`` base. ``tools/ship.sh`` calls it after the PR opens.

A PR that touches a CODEOWNERS path needs the owner's approval (the ruleset sets ``require_code_owner_review``); :func:`owner_recipe`
prints the three ``gh`` commands that land it, for the owner only.
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
from typing import Any, Dict, List, Optional, Tuple

import agent_login
import pr_blockers
import review_verdict
import ruleset_gate


#: The triage config next to this file; ``merge_guard`` pins it (with this script) to the base branch's copy, so a pull request
#: cannot change what the gate asks for.
CONFIG_PATH = Path(__file__).resolve().parent / "triage" / "config.json"


def load_config(path: Optional[Path] = None) -> Dict[str, Any]:
    """The triage config, or ``{}`` when it cannot be read (the defaults then apply: denylist optional)."""
    try:
        data = json.loads((path or CONFIG_PATH).read_text())
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


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


def run(args: List[str], check: bool = True) -> subprocess.CompletedProcess:
    proc = subprocess.run(args, capture_output=True, text=True)
    if check and proc.returncode:
        raise RuntimeError(f"{' '.join(args[:4])}: {(proc.stderr or proc.stdout).strip()[:300]}")
    return proc



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
PRODUCT_REPO = "SFenton/native-home"
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


#: Who may have a pull request armed: the owner's own or, once ``agent_login`` is configured (``tools/agent_login.py``), the agent
#: account's, from this repository (a fork or a foreign author is refused). With none configured only ``AUTHOR`` counts, as before.
AUTHOR = agent_login.OWNER
#: The pinned config the agent login is read from (never the process settings: see ``tools/agent_login.py``).
CONFIG = Path(__file__).resolve().parent / "triage" / "config.json"


def author_ok(login: object) -> bool:
    """Whether ``login`` may have its pull request armed: ``AUTHOR`` or the configured agent login."""
    return agent_login.is_own(login, agent_login.configured(CONFIG))


def arm_command(number: str, head: str, auto: bool = True) -> List[str]:
    """``gh pr merge`` pinned to ``head``: GitHub merges that exact commit once its required checks pass (``--auto``), or at once when
    the checks already finished (``auto=False``, the retry after ``clean status``)."""
    return ["gh", "pr", "merge", number, "-R", PRODUCT_REPO, *(["--auto"] if auto else []), "--squash", "--match-head-commit", head]


def arm(number: str, head: str) -> Tuple[int, str]:
    """Arm auto-merge pinned to ``head``. GitHub refuses ``--auto`` with ``clean status`` when every check already passed; then merge
    directly, still pinned. Reads the pull request afterwards so the line says what happened: ``merged``, ``armed`` or ``failed``
    (an exit-0 gh that left neither is a failure)."""
    short = head[:8]
    proc = run(arm_command(number, head), check=False)
    if proc.returncode and "clean status" in ((proc.stderr or "") + (proc.stdout or "")).lower():
        proc = run(arm_command(number, head, auto=False), check=False)
    if proc.returncode:
        return 2, f"failed #{number}: GitHub refused: {((proc.stderr or proc.stdout or '').strip() or 'no message')[:300]}"
    after = json.loads(run(["gh", "pr", "view", number, "-R", PRODUCT_REPO, "--json", "state,autoMergeRequest"]).stdout or "{}")
    if after.get("state") == "MERGED":
        return 0, f"merged #{number} at {short}"
    if after.get("autoMergeRequest"):
        return 0, f"armed #{number} at {short}: GitHub merges when pr-checks and ai-review pass on this head"
    return 2, f"failed #{number}: gh pr merge returned but the pull request is neither merged nor armed"


def owner_recipe(number: str, info: Dict[str, Any]) -> List[str]:
    """The owner-only landing recipe for a PR that touches a CODEOWNERS path, else ``[]``.

    The ruleset requires code-owner review, so GitHub will not merge such a PR on an agent's say-so: the owner marks it ready, approves
    it as code owner and squash-merges it pinned to the head. The three exact ``gh`` commands are printed for the owner; no agent runs them.
    ``info`` is the ``gh pr view`` JSON (``files``, ``headRefOid``); :func:`pr_blockers.blockers` is the shared reading of the PR."""
    if not pr_blockers.owned_files(info):
        return []
    head = str(info.get("headRefOid") or "")
    why = "; ".join(pr_blockers.blockers(info))
    return [f"owner-only: #{number} touches CODEOWNERS paths ({why}); the owner lands it from their own terminal (agents never run these):",
            f"  gh pr ready {number} -R {PRODUCT_REPO}",
            f"  gh pr review {number} -R {PRODUCT_REPO} --approve",
            f"  gh pr merge {number} -R {PRODUCT_REPO} --squash --match-head-commit {head}"]


#: The phrase ``lane_land`` puts in a refusal of the owner-kept set; such a block is the owner's to clear.
OWNER_KEPT = "owner-only set"


def print_owner_recipe(number: str, info: Dict[str, Any]) -> None:
    """Print :func:`owner_recipe` (nothing for a PR that touches no CODEOWNERS path). Called only once a gate of ours has run and what
    remains is owner-only (code-owner review, a draft, or the owner-kept set); never before a refusal of another kind."""
    for line in owner_recipe(number, info):
        print(line)


def land(number: str, dry_run: bool, review_path: Optional[str] = None, keep_worktree: bool = False,
         owner_ack: bool = False) -> Tuple[int, str]:
    """Run the gates GitHub cannot, then arm auto-merge on the exact head. Returns ``(exit code, one line)``: 0 for ``armed``, ``merged``
    and ``would arm``, 1 for ``blocked``, 2 for ``failed``. ``review_path`` and ``keep_worktree`` are accepted and ignored (old callers)."""
    if owner_ack and not owner_session():
        return 2, f"failed #{number}: --owner-ack is owner-only: run it from your own terminal, never from an agent or runner session"
    paused = kill_switch()
    if paused:
        return 1, f"blocked #{number}: landing paused ({paused})"
    info = json.loads(run(["gh", "pr", "view", number, "-R", PRODUCT_REPO, "--json",
                           "state,isDraft,headRefName,headRefOid,mergeable,reviewDecision,baseRefName,labels,files,body,title,author,isCrossRepository"]).stdout)
    if info["state"] != "OPEN":
        return 1, f"blocked #{number}: pull request is {info['state'].lower()}"
    if any((label.get("name") if isinstance(label, dict) else label) == "Needs Decision"
           for label in info.get("labels") or []):
        return 1, f"blocked #{number}: labelled Needs Decision; an owner-only item (fixed set, or an app-UI gate park), so the owner decides first (reply on the issue, or merge the PR to accept)"
    if info.get("mergeable") == "CONFLICTING":
        return 1, f"blocked #{number}: merge conflicts with {info.get('baseRefName', 'main')}"
    login = info["author"].get("login") if isinstance(info.get("author"), dict) else None
    if not author_ok(login) or info.get("isCrossRepository") is not False:
        return 1, f"blocked #{number}: not a pull request by {AUTHOR} from {PRODUCT_REPO} (author {login!r}, fork {info.get('isCrossRepository')!r})"
    base_name = str(info.get("baseRefName") or "")
    if base_name not in ALLOWED_BASES:
        return 1, f"blocked #{number}: the base is {base_name or '?'}, not {', '.join(ALLOWED_BASES)}"
    head = str(info.get("headRefOid") or "")
    if not review_verdict.has_pass(head):
        return 1, f"blocked #{number}: no independent pass for {head[:12]} (record.py --lane {info.get('headRefName')} before the push)"
    ruleset = ruleset_gate.check(PRODUCT_REPO, base_name)
    if ruleset:
        return 1, f"blocked #{number}: {ruleset[0]}"
    if owner_ack:
        if not confirm_head_on_tty(number, head):
            return 1, f"blocked #{number}: --owner-ack needs the PR head SHA ({head}) typed at the terminal"
        gate = "app-UI gate skipped by --owner-ack (head SHA confirmed at the terminal)"
    else:
        try:
            gate = ui_gate(number, info)
        except GateRefused as exc:
            if OWNER_KEPT in str(exc):
                print_owner_recipe(number, info)
            return 1, f"blocked #{number}: app-UI gate ({exc.kind}): {exc}"
        except (RuntimeError, ValueError, KeyError, OSError, subprocess.SubprocessError) as exc:
            return 1, f"blocked #{number}: app-UI gate failed closed: {exc}"
    refused = denylist_gate(number, head, load_config().get("denylist_required") is True, base_name)
    if refused:
        return 1, f"blocked #{number}: {refused}"
    if pr_blockers.owner_only(info):  # every gate of ours passed; what is left is the owner's alone
        print_owner_recipe(number, info)
    if dry_run:
        return 0, f"would arm #{number} at {head[:8]} ({gate})"
    if info.get("isDraft"):
        run(["gh", "pr", "ready", number, "-R", PRODUCT_REPO])
    return arm(number, head)


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(allow_abbrev=False, description="Arm auto-merge on a pull request after the local gates.")
    parser.add_argument("number")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--review", help="accepted and ignored (the reviewer's pass is read from the trusted store)")
    parser.add_argument("--owner-ack", action="store_true",
                        help="owner only (interactive terminal): skip the app-UI gate for this pull request")
    parser.add_argument("--keep-worktree", action="store_true", help="accepted and ignored (worktrees are reaped by ci_hygiene.py)")
    args = parser.parse_args(argv)
    try:
        code, line = land(args.number.lstrip("#"), args.dry_run, args.review, args.keep_worktree, args.owner_ack)
    except (RuntimeError, ValueError, KeyError, OSError) as exc:
        code, line = 2, f"failed #{args.number}: {exc}"
    print(line)
    return code


if __name__ == "__main__":
    sys.exit(main())
