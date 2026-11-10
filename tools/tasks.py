#!/usr/bin/env python3
"""Task ledger CLI: ``build/tasks/<id>.json`` (git-ignored), schema ``contracts/task-ledger.schema.json``.

    tasks.py new T-0142 --intake "issue #12" --level L1 --brief build/briefs/T-0142.md \\
        --check "iPhone shows the chip" --check "duo-folded unchanged"
    tasks.py add-check T-0142 "ipad-landscape splits"      # orchestrator only
    tasks.py new T-0143 ... --check "r1=review round 1 clean"   # custom id r1; plain text gets a1, a2, ...
    tasks.py flip T-0142 a2 --evidence build/evidence/b/iphone.png   # agents: this is all they may change
    tasks.py flip T-0142 a2 --fail                          # mark a check failing again
    tasks.py set-level T-0142 L2 --reason "needs the owner's pick"   # raise only; recorded in level_history
    tasks.py add-branch T-0142 agents/x-20261110      # record a lane branch; the retro digest reads its review records
    tasks.py show T-0142 | list | check T-0142              # check exits 0 only when every check passes

A check given as ``id=text`` gets that id (``[a-z][a-z0-9_-]{0,15}``, unique in the entry, text not empty); anything
else is plain text and gets ``a1``, ``a2``, .... Beware the trap: "count=3 tiles" is read as id ``count`` with text
"3 tiles"; write such a check without ``=`` or give it an id (``tiles=count=3 tiles``). The id is printed on add.

Only ``new`` and ``add-check`` change the list of checks; ``flip`` touches ``passes`` and ``evidence`` alone, and
setting ``passes`` requires the evidence path to exist. ``TASKS_DIR`` overrides the directory (tests).
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Optional

ROOT = Path(__file__).resolve().parents[1]
LEVELS = ("L0", "L1", "L2", "L3")
STATUSES = ("new", "in_progress", "in_review", "needs_decision", "blocked", "done")
ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
BRANCH = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/-]*$")
CHECK_ID = re.compile(r"^[a-z][a-z0-9_-]{0,15}$")


def tasks_dir() -> Path:
    """Directory of ledger files."""
    return Path(os.environ.get("TASKS_DIR") or ROOT / "build" / "tasks")


def path_of(task: str) -> Path:
    """Ledger file of ``task``; rejects ids that could escape the directory."""
    if not ID.match(task):
        raise SystemExit(f"tasks: bad task id {task!r}")
    return tasks_dir() / f"{task}.json"


def load(task: str) -> Dict:
    """Read a ledger entry or exit with a message."""
    path = path_of(task)
    if not path.is_file():
        raise SystemExit(f"tasks: no ledger entry {path}")
    return json.loads(path.read_text())


def save(entry: Dict) -> None:
    """Write ``entry`` atomically."""
    path = path_of(entry["id"])
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(entry, indent=2) + "\n")
    tmp.replace(path)


def parse_check(spec: str) -> "tuple[Optional[str], str]":
    """Split ``id=text`` into (id, text); plain text gives (None, text). A bad id exits."""
    head, sep, rest = spec.partition("=")
    if sep and rest.strip() and CHECK_ID.match(head):
        return head, rest.strip()
    if sep and rest.strip() and re.match(r"^[A-Za-z0-9_-]+$", head) and head[:1].isupper():
        raise SystemExit(f"tasks: check id {head!r} must match [a-z][a-z0-9_-]{{0,15}}")
    return None, spec


def new_check(entry: Dict, spec: str) -> Dict:
    """Append a failing check to ``entry``: ``id=text`` sets the id, plain text gets the next ``aN``."""
    custom, text = parse_check(spec)
    if not text:
        raise SystemExit("tasks: a check needs text")
    taken = {c["id"] for c in entry["acceptance"]}
    if custom is not None:
        if custom in taken:
            raise SystemExit(f"tasks: check id {custom} already exists")
        check_id = custom
    else:
        n = max([int(i[1:]) for i in taken if re.fullmatch(r"a[0-9]+", i)], default=0) + 1
        while f"a{n}" in taken:
            n += 1
        check_id = f"a{n}"
    check = {"id": check_id, "check": text, "passes": False, "evidence": None}
    entry["acceptance"].append(check)
    return check


def cmd_new(args: argparse.Namespace) -> int:
    if path_of(args.id).exists():
        raise SystemExit(f"tasks: {args.id} already exists")
    entry = {"id": args.id, "intake": args.intake, "level": args.level, "brief": args.brief, "acceptance": [],
             "rounds": {"design": 0, "review": 0}, "budget": {"usd": args.usd, "turns": args.turns}, "status": "new"}
    if args.route_rule:
        entry["route"] = {"rule": args.route_rule, "jev": args.route_jev or None}
    for text in args.check:
        check = new_check(entry, text)
        print(f"added {check['id']}: {check['check']}")
    save(entry)
    print(path_of(args.id))
    return 0


def cmd_add_check(args: argparse.Namespace) -> int:
    entry = load(args.id)
    check = new_check(entry, args.text)
    print(f"added {check['id']}: {check['check']}")
    save(entry)
    return 0


def cmd_flip(args: argparse.Namespace) -> int:
    entry = load(args.id)
    check = next((c for c in entry["acceptance"] if c["id"] == args.check), None)
    if check is None:
        raise SystemExit(f"tasks: {args.id} has no check {args.check}")
    if args.fail:
        check["passes"] = False
        if args.evidence:
            check["evidence"] = args.evidence
    else:
        if not args.evidence:
            raise SystemExit("tasks: flipping to pass needs --evidence PATH")
        if not Path(args.evidence).exists():
            raise SystemExit(f"tasks: evidence path does not exist: {args.evidence}")
        check["passes"] = True
        check["evidence"] = args.evidence
    save(entry)
    print(f"{args.id} {args.check} passes={check['passes']}")
    return 0


def cmd_set_level(args: argparse.Namespace) -> int:
    entry = load(args.id)
    old = entry["level"]
    if args.level == old:
        print(f"{args.id} is already {old}")
        return 0
    if LEVELS.index(args.level) < LEVELS.index(old):
        raise SystemExit(f"tasks: {args.id} is {old}; a level is raised, never lowered ({args.level} refused)")
    at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    entry["level"] = args.level
    entry.setdefault("level_history", []).append({"from": old, "to": args.level, "reason": args.reason, "at": at})
    save(entry)
    print(f"{args.id} level {old} -> {args.level}")
    return 0


def cmd_add_branch(args: argparse.Namespace) -> int:
    """Record ``args.branch`` in the entry's ``branches`` (once; the retro digest reads the review store for each)."""
    branch = args.branch.strip()
    if not BRANCH.match(branch):
        raise SystemExit(f"tasks: bad branch name {args.branch!r}")
    entry = load(args.id)
    branches = entry.setdefault("branches", [])
    if branch not in branches:
        branches.append(branch)
        save(entry)
    print(f"{args.id} branches: {', '.join(branches)}")
    return 0


def cmd_show(args: argparse.Namespace) -> int:
    print(json.dumps(load(args.id), indent=2))
    return 0


def cmd_check(args: argparse.Namespace) -> int:
    entry = load(args.id)
    open_checks = [c for c in entry["acceptance"] if not c["passes"]]
    for c in open_checks:
        print(f"open {c['id']}: {c['check']}")
    if not entry["acceptance"]:
        print("no checks defined")
        return 1
    print("all checks pass" if not open_checks else f"{len(open_checks)} of {len(entry['acceptance'])} open")
    return 1 if open_checks else 0


def cmd_list(args: argparse.Namespace) -> int:
    for path in sorted(tasks_dir().glob("*.json")):
        try:
            entry = json.loads(path.read_text())
        except ValueError:
            continue
        done = sum(1 for c in entry.get("acceptance", []) if c.get("passes"))
        print(f"{entry.get('id')}\t{entry.get('level')}\t{entry.get('status')}\t{done}/{len(entry.get('acceptance', []))}\t{entry.get('intake')}")
    return 0


CHECK_HELP = ("check text; 'id=text' sets the id ([a-z][a-z0-9_-]{0,15}, unique), plain text gets a1, a2, ...; "
              "'count=3 tiles' is read as id 'count', so reword it or give it an id")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = parser.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("new")
    p.add_argument("id")
    p.add_argument("--intake", required=True)
    p.add_argument("--level", choices=LEVELS, required=True)
    p.add_argument("--brief", required=True)
    p.add_argument("--check", action="append", default=[], help=CHECK_HELP)
    p.add_argument("--route-rule", help="role the routing rules chose (optional)")
    p.add_argument("--route-jev", help="role the Jev route.role hint named in shadow (optional)")
    p.add_argument("--usd", type=float, default=0)
    p.add_argument("--turns", type=int, default=0)
    p.set_defaults(fn=cmd_new)
    p = sub.add_parser("add-check", help="add a failing check", description=CHECK_HELP)
    p.add_argument("id")
    p.add_argument("text", help=CHECK_HELP)
    p.set_defaults(fn=cmd_add_check)
    p = sub.add_parser("flip")
    p.add_argument("id")
    p.add_argument("check")
    p.add_argument("--evidence")
    p.add_argument("--fail", action="store_true")
    p.set_defaults(fn=cmd_flip)
    p = sub.add_parser("add-branch", help="record a lane branch on the entry")
    p.add_argument("id")
    p.add_argument("branch")
    p.set_defaults(fn=cmd_add_branch)
    p = sub.add_parser("set-level")
    p.add_argument("id")
    p.add_argument("level", choices=LEVELS)
    p.add_argument("--reason", required=True)
    p.set_defaults(fn=cmd_set_level)
    for name, fn in (("show", cmd_show), ("check", cmd_check)):
        p = sub.add_parser(name)
        p.add_argument("id")
        p.set_defaults(fn=fn)
    p = sub.add_parser("list")
    p.set_defaults(fn=cmd_list)
    return parser


def main(argv: Optional[List[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
