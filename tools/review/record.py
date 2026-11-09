#!/usr/bin/env python3
"""Record the pre-merge reviewer's verdict.

Usage: ``tools/review/record.py [FILE|-] [--pr N] [--lane BRANCH] [--root WORKTREE]``. ``--root`` records for the checkout at WORKTREE from any cwd
(the branch and head are read there, the stamp must name that directory); with ``--pr`` the PR's head branch must equal that checkout's branch. Reads the verdict JSON (stdin or FILE), validates it, stamps
the branch and head SHA, writes ``build/review/<branch>.json`` (read by ``tools/pr_land.sh`` and ``tools/ship.sh``)
and, with ``--pr``, replaces the review summary section of the PR body and posts the check run ``ai-review`` on the reviewed head
as the reviewer App (``success`` for ``pass``, or ``changes`` at the round cap with no blocker; ``failure`` otherwise). That check is what
GitHub's ruleset requires; the latest run on a head wins. With ``--pr`` the PR head must equal this checkout's HEAD (exit 2 otherwise), and
a check that cannot be posted prints ``ai-review check NOT posted`` and exits 3 (the JSON and the PR body stay recorded).

Only the reviewer records: ``tools/hooks/review_guard.py`` lets a session whose ``agent_type`` is ``reviewer`` run this script and leaves an
identity stamp that is copied into the verdict as ``reviewer`` (``pr_land`` and ``lane_land`` refuse a verdict without it); no other session
may write ``build/review/*.json``.

The review round cap is enforced here: recording round 3 or later needs ``--confirm-round "reason"``. The rule is two
rounds; a blocker after round 2 goes to Needs Decision, and a confirmation pass after round 2 that finds no blockers
is allowed, with the reason on the record (stored as ``round_confirmation``).
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import gh_app_token  # noqa: E402  (already in the protected import closure; never import a landing tool here)


def review_file_name(branch: str) -> str:
    """``build/review/`` file name for a branch (``/`` becomes ``__``). Kept equal to ``pr_land.review_file_name`` by a test; this file
    imports nothing from the landing tools, so the recorder's import closure stays small enough to protect (owner-only set)."""
    return branch.replace("/", "__") + ".json"


#: Where ``tools/hooks/review_guard.py`` leaves the identity of the reviewer about to run this script (kept equal by a test).
IDENT_PATH = Path.home() / ".cache" / "fenton-hass" / "reviewer-ident.json"
IDENT_MAX_AGE = 900.0

VERDICTS = ("pass", "changes", "blocker")
SEVERITIES = ("blocker", "major", "minor")
START, END = "<!-- review:start -->", "<!-- review:end -->"
#: The check run GitHub's ruleset requires on the PR head, the App that posts it, and the cap on its text (the API limit is 65535).
CHECK_NAME = "ai-review"
CHECK_ROLE = "reviewer"
SUMMARY_MAX = 60000


def validate(data: Dict[str, Any]) -> List[str]:
    """Problems with a verdict document; empty when valid."""
    problems = []
    if data.get("verdict") not in VERDICTS:
        problems.append("verdict must be pass, changes or blocker")
    for i, f in enumerate(data.get("findings") or []):
        if f.get("severity") not in SEVERITIES:
            problems.append(f"finding {i}: severity must be blocker, major or minor")
        for key in ("rule", "detail"):
            if not f.get(key):
                problems.append(f"finding {i}: {key} is required")
    if not problems and data["verdict"] != derive_verdict(data.get("findings") or []):
        problems.append(f"verdict {data['verdict']} does not match the findings (expected "
                        f"{derive_verdict(data.get('findings') or [])}: pass = only minors, changes = a major and no "
                        "blocker, blocker = any blocker)")
    return problems


def derive_verdict(findings: List[Dict[str, Any]]) -> str:
    """The verdict the severities imply."""
    severities = {f.get("severity") for f in findings}
    return "blocker" if "blocker" in severities else "changes" if "major" in severities else "pass"


def check_outcome(data: Dict[str, Any]) -> tuple:
    """``(conclusion, title)`` of the ``ai-review`` check for a recorded verdict. ``success`` when the verdict is ``pass``, or ``changes``
    at the round cap (``round >= MAX_ROUNDS``) with no blocker finding; ``failure`` otherwise (round 1 ``changes``, any blocker)."""
    verdict, rnd = data.get("verdict"), int(data.get("round") or 1)
    blocker = any(f.get("severity") == "blocker" for f in data.get("findings") or [])
    ok = verdict == "pass" or (verdict == "changes" and rnd >= MAX_ROUNDS and not blocker)
    return ("success" if ok else "failure"), f"{CHECK_NAME}: {verdict} (round {rnd})"


def check_payload(data: Dict[str, Any]) -> Dict[str, Any]:
    """The ``POST /repos/{repo}/check-runs`` body for a recorded verdict, bound to the reviewed head (``data["head"]``)."""
    conclusion, title = check_outcome(data)
    lines = []
    for f in data.get("findings") or []:
        lines.append(f"{f['severity']} [{f['rule']}] {f.get('file') or '-'}: {f['detail']}" + (f" Fix: {f['fix']}" if f.get("fix") else ""))
    return {"name": CHECK_NAME, "head_sha": data["head"], "status": "completed", "conclusion": conclusion,
            "completed_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "output": {"title": title, "summary": summary(data)[:SUMMARY_MAX], "text": "\n".join(lines)[:SUMMARY_MAX]}}


def post_check(repo: str, payload: Dict[str, Any]) -> Any:
    """Post the check run as the reviewer App (token narrowed to issues write, pull_requests read, checks write). Raises ``AppError``."""
    bearer = gh_app_token.token(CHECK_ROLE, extra={"checks": "write"})
    return gh_app_token.api_request("POST", f"repos/{repo}/check-runs", bearer, payload)


def next_round(previous: Dict[str, Any], head: str) -> int:
    """Round 1 first; bumped only when the head moved after a ``changes`` verdict. ``round`` in the input is ignored."""
    if not previous:
        return 1
    rnd = int(previous.get("round") or 1)
    if previous.get("head") != head and previous.get("verdict") == "changes":
        return rnd + 1
    return rnd


MAX_ROUNDS = 2


def round_refusal(round_number: int, reason: Optional[str], verdict: str = "pass") -> Optional[str]:
    """Why recording ``round_number`` is refused, or ``None``. Round 3+ needs ``--confirm-round``, and a ``blocker``
    verdict at round 3+ is refused even with one."""
    if round_number > MAX_ROUNDS and verdict == "blocker":
        return (f"round {round_number} has a blocker; a blocker after round {MAX_ROUNDS} parks as Needs Decision, "
                "it is not recorded as another round, even with --confirm-round.")
    if round_number <= MAX_ROUNDS or (reason or "").strip():
        return None
    return (f"round {round_number} exceeds the {MAX_ROUNDS}-round rule (a blocker after round {MAX_ROUNDS} goes to "
            "Needs Decision, not another round). A confirmation pass with no blockers is allowed: "
            'pass --confirm-round "reason".')


def summary(data: Dict[str, Any]) -> str:
    """Markdown for the PR body."""
    lines = [START, f"### Review: {data['verdict']} (round {data['round']})"]
    for f in data.get("findings") or []:
        where = f" `{f['file']}`" if f.get("file") else ""
        fix = f" Fix: {f['fix']}" if f.get("fix") else ""
        lines.append(f"- **{f['severity']}** [{f['rule']}]{where}: {f['detail']}{fix}")
    if not data.get("findings"):
        lines.append("No findings.")
    lines.append(END)
    return "\n".join(lines)


def merge_body(body: str, section: str) -> str:
    """``body`` with the review section replaced, or appended when there is none."""
    pattern = re.compile(re.escape(START) + ".*?" + re.escape(END), re.S)
    return pattern.sub(lambda _m: section, body) if pattern.search(body) else (body.rstrip() + "\n\n" + section + "\n")


def reviewer_identity(path: Path = IDENT_PATH, now: Optional[float] = None, cwd: Optional[str] = None) -> Optional[Dict[str, str]]:
    """Who is recording: the stamp ``review_guard`` leaves when the session whose ``agent_type`` is ``reviewer`` runs this script, or ``None``
    (no stamp, a stale one, one for another directory, or one of another agent type). Verdicts without it are refused by the landers."""
    import os
    import time
    try:
        stamp = json.loads(path.read_text())
    except (OSError, ValueError):
        return None
    if not isinstance(stamp, dict) or stamp.get("agent_type") != "reviewer" or not str(stamp.get("session_id") or ""):
        return None
    if (time.time() if now is None else now) - float(stamp.get("at") or 0) > IDENT_MAX_AGE:
        return None
    where = os.path.realpath(cwd or os.getcwd())
    if stamp.get("cwd") and os.path.realpath(str(stamp["cwd"])) != where and not where.startswith(os.path.realpath(str(stamp["cwd"])) + os.sep):
        return None
    return {"agent_type": "reviewer", "session_id": str(stamp["session_id"]), "agent_id": str(stamp.get("agent_id") or "")}


def git(*args: str) -> str:
    return subprocess.run(["git", *args], capture_output=True, text=True, check=True).stdout.strip()


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("file", nargs="?", default="-")
    parser.add_argument("--pr")
    parser.add_argument("--lane", metavar="BRANCH", help="also write the verdict where the interactive lane lander reads it "
                                                        "(~/hass-agents/reviews/<lane>-<head12>.json); HEAD must be the lane tip")
    parser.add_argument("--root", metavar="DIR", help="the PR's worktree (default: the current directory's checkout)")
    parser.add_argument("--confirm-round", metavar="REASON", help="required to record round 3 or later")
    args = parser.parse_args(argv)
    try:
        data = json.loads(sys.stdin.read() if args.file == "-" else Path(args.file).read_text())
    except ValueError as exc:
        print(f"record: not JSON: {exc}", file=sys.stderr)
        return 2
    problems = validate(data)
    if problems:
        print("record: " + "; ".join(problems), file=sys.stderr)
        return 2
    root = str(Path(args.root).expanduser().resolve()) if args.root else None
    at = ["-C", root] if root else []  # every git call below runs in the PR's worktree when --root is given
    if root and not Path(root).is_dir():
        print(f"record: --root {args.root} is not a directory", file=sys.stderr)
        return 2
    branch = git(*at, "rev-parse", "--abbrev-ref", "HEAD")
    if branch != "HEAD" and args.pr:  # a checkout on another branch (the coordinator's primary) cannot stamp this PR
        pr_branch = json.loads(subprocess.run(["gh", "pr", "view", args.pr, "--json", "headRefName"], capture_output=True,
                                              text=True, check=True).stdout)["headRefName"]
        if pr_branch != branch:
            print(f"record: PR {args.pr} is branch {pr_branch}, but this checkout is on {branch}; run from the PR's worktree or pass --root", file=sys.stderr)
            return 2
    if branch == "HEAD":  # detached: the PR names the branch
        if not args.pr:
            print("record: detached HEAD; pass --pr N so the branch can be read from the PR", file=sys.stderr)
            return 2
        branch = json.loads(subprocess.run(["gh", "pr", "view", args.pr, "--json", "headRefName"], capture_output=True,
                                           text=True, check=True).stdout)["headRefName"]
    out = Path(git(*at, "rev-parse", "--show-toplevel")) / "build" / "review" / review_file_name(branch)
    previous: Dict[str, Any] = {}
    if out.is_file():
        try:
            previous = json.loads(out.read_text())
        except ValueError:
            pass
    data["branch"], data["head"] = branch, git(*at, "rev-parse", "HEAD")
    repo = ""
    if args.pr:  # the check binds to the reviewed head, so the PR head must be this checkout's HEAD
        view = json.loads(subprocess.run(["gh", "pr", "view", args.pr, "--json", "headRefOid,url"], capture_output=True,
                                         text=True, check=True).stdout)
        if view.get("headRefOid") != data["head"]:
            print(f"record: PR head {view.get('headRefOid')} is not this checkout's HEAD {data['head']}: push or pull first", file=sys.stderr)
            return 2
        match = re.match(r"https://[^/]+/([^/]+/[^/]+)/pull/", str(view.get("url") or ""))
        repo = match.group(1) if match else ""
    data["round"] = next_round(previous, data["head"])
    refusal = round_refusal(data["round"], args.confirm_round, data["verdict"])
    if refusal:
        print(f"record: {refusal}", file=sys.stderr)
        return 2
    identity = (reviewer_identity(cwd=root) if root else reviewer_identity())
    if identity is None:
        print("record: no reviewer identity: only the reviewer (agent_type reviewer, through the review_guard hook) records a verdict", file=sys.stderr)
        return 2
    data["reviewer"] = identity
    if data["round"] > MAX_ROUNDS:
        data["round_confirmation"] = args.confirm_round.strip()
    data.setdefault("findings", [])
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(data, indent=2) + "\n")
    if args.lane:
        lane_out = Path.home() / "hass-agents" / "reviews" / f"{args.lane.replace('/', '__')}-{data['head'][:12]}.json"
        lane_out.parent.mkdir(parents=True, exist_ok=True)
        lane_out.write_text(json.dumps(data, indent=2) + "\n")
    if args.pr:
        body = json.loads(subprocess.run(["gh", "pr", "view", args.pr, "--json", "body"], capture_output=True,
                                         text=True, check=True).stdout)["body"]
        subprocess.run(["gh", "pr", "edit", args.pr, "--body", merge_body(body, summary(data))], check=True)
    print(f"recorded {data['verdict']} (round {data['round']}) -> {out}")
    if args.pr:
        try:
            if not repo:
                raise gh_app_token.AppError("cannot read the repository from the PR URL")
            post_check(repo, check_payload(data))
        except gh_app_token.AppError as exc:
            print(f"record: ai-review check NOT posted: {exc}; GitHub will keep the PR blocked", file=sys.stderr)
            return 3
        print(f"posted {CHECK_NAME} {check_outcome(data)[0]} on {data['head'][:8]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
