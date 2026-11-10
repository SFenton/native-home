#!/usr/bin/env python3
"""Lane checks that run before a push, so one session's work cannot silently collide with another's.

Born of the T-gh-native-gate post-mortem (build/retro/T-gh-native-gate-postmortem.md, Action 1): a lane started without an overlap
check ran against an open PR; a ``git reset --soft origin/main`` squash reverted a merged PR after another session's fetch moved the
shared ``origin/main``; ``house_scan`` ran only at push time; ``core.hooksPath`` flipped between ``.githooks`` and an absolute path.

    python3 tools/lane_check.py start --task T --branch B --paths P...   # run with the lane worktree as the current directory (after lane_new.sh, before the Coder works)
    python3 tools/lane_check.py check [--base main] [--only hooks|scan|revert|shape]...   # no push; exit 1 on a failure
    python3 tools/lane_check.py squash [--dry-run]                       # soft-reset onto the recorded lane base, never origin/main

``start`` fetches, records the base (the ``origin/main`` sha) in ``<git-dir>/lane-base`` (worktree-local, so another session's fetch
cannot move it) and appends it to ``<common-git-dir>/lane-bases.log`` (the previous lane's base is the last line of another lane). It
then lists open PRs whose files match a declared path, and commits on ``origin/main`` since the previous lane's base (skipped when no other lane
has started in this repository) that touch one; any hit exits 1 unless ``--ack-overlap "<reason>"`` (the reason is printed and recorded).
``--paths`` entries are exact files, directory prefixes or ``fnmatch`` globs. Ledger: ``start`` also runs ``tasks.py add-branch
TASK BRANCH`` (a missing entry only prints a note); the base itself is not written to the ledger (its schema takes no such field), the
lane-base file carries the task id.

``check`` runs: ``hooks`` (``core.hooksPath`` resolves to this worktree's ``<toplevel>/.githooks``; nothing else passes), ``scan`` (``house_scan.py denylist``, the
exit mapping ship.sh always had), ``revert`` (files the parent has changed since the lane base that HEAD puts back, the shape of a
squash over a moved base) and ``shape`` (advisory: one commit, parent equal to ``origin/<base>``, else the safe squash is printed).

Hooks-path environment: ``core.hooksPath`` lives in the repository's shared config, so every worktree sees one value. Only the relative
``.githooks`` that ``tools/setup.sh`` writes resolves to each worktree's own hooks; an absolute path points every worktree at one checkout,
whose ``pre-push`` runs that checkout's ``tools/`` scripts (a stale primary checkout skips the review step). ``check`` refuses any other value.

Standard library only. Exit codes: 0 ok, 1 a check failed or overlap found, 2 usage or git/gh error.
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import List, Optional, Sequence

TOOLS = Path(__file__).resolve().parent
CHECKS = ("hooks", "scan", "revert", "shape")


class LaneError(Exception):
    """A usage or environment problem (not a finding): reported on stderr, exit 2."""


def run(args: Sequence[str], check: bool = True) -> subprocess.CompletedProcess:
    """Run a command, capturing text output; with ``check`` a non-zero exit raises :class:`LaneError`."""
    try:
        done = subprocess.run(list(args), capture_output=True, text=True)
    except FileNotFoundError as exc:
        raise LaneError(f"{args[0]} not found") from exc
    if check and done.returncode != 0:
        tail = (done.stderr or done.stdout).strip().splitlines()
        raise LaneError(f"{' '.join(args[:3])} failed: {tail[-1] if tail else done.returncode}")
    return done


def git(*args: str, check: bool = True) -> str:
    """Stdout of a git command in the current directory, stripped."""
    return run(["git", *args], check=check).stdout.strip()


def toplevel() -> Path:
    """The working tree root of the current directory."""
    return Path(git("rev-parse", "--show-toplevel"))


def lane_base_file() -> Path:
    """The worktree-local file holding this lane's base."""
    return Path(git("rev-parse", "--absolute-git-dir")) / "lane-base"


def read_lane_base() -> Optional[dict]:
    """The recorded lane base (``base``, ``branch``, ``task``, ``paths``) or None when ``start`` never ran here."""
    try:
        data = json.loads(lane_base_file().read_text())
    except (OSError, ValueError):
        return None
    return data if isinstance(data, dict) and data.get("base") else None


def matches(path: str, patterns: Sequence[str]) -> bool:
    """True when ``path`` equals a pattern, sits under a directory pattern, or matches it as a glob."""
    for pat in patterns:
        pat = pat.rstrip("/")
        if path == pat or path.startswith(pat + "/") or fnmatch.fnmatch(path, pat):
            return True
    return False


def open_pr_overlaps(paths: Sequence[str], branch: str) -> List[str]:
    """Open PRs (other than ``branch``) with a file matching ``paths``, one line each."""
    done = run(["gh", "pr", "list", "--state", "open", "--limit", "100", "--json", "number,headRefName,files"], check=False)
    if done.returncode != 0:
        raise LaneError("gh pr list failed; cannot check open PRs: " + (done.stderr.strip().splitlines() or ["?"])[-1])
    try:
        prs = json.loads(done.stdout or "[]")
    except ValueError as exc:
        raise LaneError("gh pr list returned unreadable JSON") from exc
    found = []
    for pr in prs:
        if pr.get("headRefName") == branch:
            continue
        hit = sorted(f.get("path", "") for f in pr.get("files", []) if matches(f.get("path", ""), paths))
        if hit:
            found.append(f"open PR #{pr.get('number')} ({pr.get('headRefName')}) touches {', '.join(hit[:5])}" + (" ..." if len(hit) > 5 else ""))
    return found


def commit_overlaps(paths: Sequence[str], since_base: Optional[str]) -> List[str]:
    """Commits on ``origin/main`` after ``since_base`` touching ``paths``; none when no earlier lane is known to compare with."""
    if not since_base:
        return []
    out = git("log", "--name-only", "--format=%x00%h %s", f"{since_base}..origin/main", check=False)
    found = []
    for block in out.split("\0")[1:]:
        head, _, files = block.partition("\n")
        if any(matches(f, paths) for f in files.split("\n") if f):
            found.append(f"origin/main commit {head}")
    return found


def cmd_start(args: argparse.Namespace) -> int:
    """Fetch, record the base, print and gate on overlap."""
    run(["git", "fetch", "-q", "origin", "main"])
    base = git("rev-parse", "origin/main")
    log = Path(git("rev-parse", "--path-format=absolute", "--git-common-dir")) / "lane-bases.log"
    previous = None
    try:
        for line in log.read_text().splitlines():
            row = json.loads(line)
            if row.get("branch") != args.branch:
                previous = row.get("base")
    except (OSError, ValueError):
        pass
    if previous and run(["git", "cat-file", "-e", previous], check=False).returncode != 0:
        previous = None
    record = {"task": args.task, "branch": args.branch, "base": base, "paths": args.paths, "at": int(time.time())}
    lane_base_file().write_text(json.dumps(record) + "\n")
    with log.open("a") as fh:
        fh.write(json.dumps(record) + "\n")
    print(f"lane base {base[:12]} recorded for {args.task} on {args.branch}")
    added = run([sys.executable, str(TOOLS / "tasks.py"), "add-branch", args.task, args.branch], check=False)
    if added.returncode == 0:
        print(added.stdout.strip())
    else:
        print(f"lane_check: note: the branch was not added to the ledger entry {args.task}: "
              f"{(added.stderr.strip().splitlines() or ['?'])[-1]}", file=sys.stderr)
    hits = open_pr_overlaps(args.paths, args.branch) + commit_overlaps(args.paths, previous)
    if not hits:
        print("overlap: none")
        return 0
    for hit in hits:
        print(f"overlap: {hit}")
    if args.ack_overlap:
        print(f"overlap acknowledged: {args.ack_overlap}")
        record["ack_overlap"] = args.ack_overlap
        lane_base_file().write_text(json.dumps(record) + "\n")
        return 0
    print('lane_check: overlap found; resolve it or rerun with --ack-overlap "<reason>".', file=sys.stderr)
    return 1


def check_hooks() -> Optional[str]:
    """None only when ``core.hooksPath`` resolves to this worktree's own ``<toplevel>/.githooks``, else the reason.

    The relative ``.githooks`` that ``tools/setup.sh`` writes does this per worktree. Another checkout's hooks folder is refused
    even when its ``pre-push`` is byte-identical, because that hook runs the other checkout's ``tools/`` scripts (``prepush_denylist.py``),
    which nothing here checks and which may be stale or missing.
    """
    top = toplevel()
    raw = git("config", "core.hooksPath", check=False)
    if not raw:
        return f"core.hooksPath is not set, so git's pre-push hook would not run. Run tools/setup.sh from this worktree ({top})."
    resolved = (Path(raw) if os.path.isabs(raw) else top / raw).resolve()
    if resolved == (top / ".githooks").resolve():
        return None
    return (f"core.hooksPath ({raw}) is not this worktree's {top}/.githooks, so git's pre-push hook would run another checkout's "
            f"scripts, or none. Run tools/setup.sh from this worktree ({top}).")


def check_scan(base: str) -> Optional[str]:
    """None when the house denylist scan is clean (the exit mapping ship.sh has always used), else the reason."""
    scan = TOOLS / "house_scan.py"
    if not scan.is_file():
        return None
    cmd = [sys.executable, str(scan), "denylist", "--root", str(toplevel()), "--base-ref", f"origin/{base}"]
    cfg = TOOLS / "triage" / "config.json"
    if cfg.is_file():
        cmd += ["--required-from", str(cfg)]
    done = subprocess.run(cmd, capture_output=True, text=True)
    sys.stdout.write(done.stdout)
    sys.stderr.write(done.stderr)
    if done.returncode == 0:
        return None
    if done.returncode == 1:
        return "denylist hit(s) above. Remove the house data."
    if done.returncode == 3:
        return "the denylist is required but not loaded (HOUSE_SCAN_DENYLIST, the config folder's house_denylist.txt or ~/hass-agents/house_denylist.txt)."
    return f"the denylist scan failed (exit {done.returncode})."


def changed(a: str, b: str) -> set:
    """Paths that differ between two commits."""
    return set(git("diff", "--name-only", f"{a}..{b}").splitlines())


def effective_base(rec: dict, target: str = "main") -> str:
    """The recorded base, or the fork point with ``origin/<target>`` once a rebase has moved the recorded base out of HEAD's history."""
    if run(["git", "merge-base", "--is-ancestor", rec["base"], "HEAD"], check=False).returncode == 0:
        return rec["base"]
    return git("merge-base", "HEAD", f"origin/{target}")


def blob(ref: str, path: str) -> str:
    """The blob id of ``path`` at ``ref`` ('' when absent)."""
    return git("rev-parse", "-q", "--verify", f"{ref}:{path}", check=False)


def check_revert(target: str = "main") -> Optional[str]:
    """None unless some commit since the lane base puts back files its parent carried from ``origin/<target>`` (the soft-reset-over-a-moved-base shape).

    Every commit from the base to HEAD is examined, not only the last. If a rebase moved the recorded base out of HEAD's history the
    fork point with ``origin/<target>`` stands in for it.
    """
    rec = read_lane_base()
    if not rec:
        print("lane_check: no lane base recorded (run `lane_check.py start`); revert check skipped", file=sys.stderr)
        return None
    if rec.get("branch") != git("rev-parse", "--abbrev-ref", "HEAD"):
        print("lane_check: the recorded lane base is for another branch; revert check skipped", file=sys.stderr)
        return None
    base = effective_base(rec, target)
    tip = f"origin/{target}"
    net = changed(base, "HEAD")
    reverted: dict = {}
    for commit in git("rev-list", f"{base}..HEAD", check=False).split():
        if run(["git", "rev-parse", "-q", "--verify", f"{commit}^"], check=False).returncode != 0:
            continue
        for path in sorted(changed(f"{commit}^", commit) - net):
            # origin/main moved this file since the base, the parent carries that move, and the commit sets it back. A lane's own revert
            # commit (origin/main never moved the file) and an unrebased lane (the parent equals the base) are not flagged.
            if blob(tip, path) != blob(base, path) and blob(f"{commit}^", path) != blob(base, path):
                reverted.setdefault(path, commit[:10])
    if reverted:
        names = ", ".join(f"{p} ({c})" for p, c in list(reverted.items())[:8])
        return (f"the branch reverts origin/main since base {base[:12]}: {names}. "
                "Rebuild the lane on the current base; never `git reset --soft origin/main`.")
    return None


def shape_notes(base: str) -> List[str]:
    """Advisory lines: one commit whose parent is the current ``origin/<base>``, else the safe squash."""
    rec = read_lane_base()
    notes = []
    tip = git("rev-parse", "-q", "--verify", f"origin/{base}", check=False)
    parent = git("rev-parse", "-q", "--verify", "HEAD^", check=False)
    if rec and rec.get("branch") == git("rev-parse", "--abbrev-ref", "HEAD"):
        count = git("rev-list", "--count", f"{effective_base(rec, base)}..HEAD", check=False)
        if count != "1":
            notes.append(f"{count} commits since the lane base; squash to one so the reviewed sha is the pushed sha: "
                         "`python3 tools/lane_check.py squash`, then commit.")
        elif parent and tip and parent != tip:
            notes.append(f"the parent is not the current origin/{base} ({tip[:12]}); the lane base is {rec['base'][:12]}. "
                         "Squash only onto the lane base (`lane_check.py squash`), or rebase deliberately and review again.")
    elif parent and tip and parent != tip:
        notes.append(f"the parent is not the current origin/{base}; no lane base is recorded, so no safe squash can be printed.")
    return notes


def cmd_check(args: argparse.Namespace) -> int:
    """Run the selected checks (all by default); print every finding; exit 1 on any failure."""
    wanted = args.only or list(CHECKS)
    failures = []
    if "hooks" in wanted and (why := check_hooks()):
        failures.append(why)
    if "scan" in wanted and (why := check_scan(args.base)):
        failures.append(why)
    if "revert" in wanted and (why := check_revert(args.base)):
        failures.append(why)
    if "shape" in wanted:
        for note in shape_notes(args.base):
            print(f"lane_check: note: {note}", file=sys.stderr)
    for why in failures:
        print(f"lane_check: {why}", file=sys.stderr)
    if not failures:
        print("lane_check: ok (" + ", ".join(wanted) + ")")
    return 1 if failures else 0


def cmd_squash(args: argparse.Namespace) -> int:
    """Soft-reset onto the recorded lane base (never ``origin/main``), leaving the lane's whole change staged.

    A plain ``git rebase onto origin/main`` keeps the recorded base in HEAD's history, so it stays the target: the squashed commit's diff
    against the base is the lane plus what merged meanwhile (identical on both sides of GitHub's three-way merge, so no conflict), and it can
    never revert anything. Only when the recorded base is gone from HEAD's history (a rewritten or force-pushed base) is the target
    ``merge-base(HEAD, origin/main)``, the point the lane really forks from; the record is updated to it and the output says so.
    """
    rec = read_lane_base()
    if not rec:
        raise LaneError("no lane base recorded here; run `lane_check.py start` first")
    base = effective_base(rec, args.base)
    if base != rec["base"]:
        print(f"history was rewritten: recorded base {rec['base'][:12]} is not in HEAD's history; squashing onto the fork point {base[:12]} and re-recording it")
        if not args.dry_run:
            rec["base"] = base
            lane_base_file().write_text(json.dumps(rec) + "\n")
    print(f"git reset --soft {base}" + ("  (dry run)" if args.dry_run else ""))
    if not args.dry_run:
        run(["git", "reset", "--soft", base])
        print('squashed onto the lane base; commit once (tools/ship.sh "Subject" --note ...), then get the review of that sha.')
    return 0


def main(argv: Optional[Sequence[str]] = None) -> int:
    """CLI entry."""
    ap = argparse.ArgumentParser(description="Lane checks: overlap, base moved, house scan, hooks path.")
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("start", help="record the lane base and report overlap")
    s.add_argument("--task", required=True)
    s.add_argument("--branch", required=True)
    s.add_argument("--paths", nargs="+", required=True)
    s.add_argument("--ack-overlap", metavar="REASON")
    c = sub.add_parser("check", help="pre-push checks without pushing")
    c.add_argument("--base", default="main")
    c.add_argument("--only", action="append", choices=CHECKS)
    q = sub.add_parser("squash", help="soft-reset onto the recorded lane base")
    q.add_argument("--dry-run", action="store_true")
    q.add_argument("--base", default="main")
    args = ap.parse_args(argv)
    try:
        return {"start": cmd_start, "check": cmd_check, "squash": cmd_squash}[args.cmd](args)
    except LaneError as exc:
        print(f"lane_check: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
