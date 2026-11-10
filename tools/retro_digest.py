#!/usr/bin/env python3
"""retro_digest: the deterministic evidence digest of one finished flow (no LLM, no network).

    tools/retro_digest.py --task ID [--worktree PATH] [--log FILE] [--status FILE] [--archive DIR] [--json OUT]
                          [--comments FILE] [--outcome CODE] [--attempt N] [--max-tokens N] [--max-minutes N]
    tools/retro_digest.py --lane NAME [--worktree PATH] [--base REF] [--json OUT] [--max-minutes N]

Reads whatever exists of: the task ledger (``build/tasks/ID.json``), the Jev gate and shadow logs
(``build/jev/gate.jsonl``, ``shadow.jsonl``), the triage status JSON, a ``claude -p`` stream-json log, review
verdicts (``build/review/*.json``), ``bg_run`` digests (``build/runs``) and the owner's replies, and writes
``build/retro/ID.json`` (or ``ARCHIVE/retro/ID.json``, or ``--json OUT``) with the fired ``triggers`` (each with
evidence lines), ``counts``, ``durations``, ``cost`` and a three-line ``aar`` (after-action note). A missing or
unreadable input is skipped, never fatal. The Steward reads the result; this script never judges it.

``--lane NAME`` (a worktree lane such as ``loop-followups``, or a branch such as ``claude/loop-followups``) digests a lane that has no
ledger task, e.g. an interactive subagent flow, from what it leaves behind: the lane worktree's ``build/runs`` (``*.digest``
and ``*.running`` markers from ``bg_run``, with their durations and executed/skipped/failed counts), ``build/review/<branch>.json``
(the round), and the branch's commit count and timestamps since ``--base`` (default ``origin/main``). It writes ``build/retro/lane-NAME.json`` with the same triggers (``review_rounds_over_cap``, ``over_budget``,
``stopped_with_live_children``) and two lane ones: ``repeated_long_device_rounds`` and ``empty_runs``.

For each branch in the ledger's ``branches`` (``tools/tasks.py add-branch``), the digest also reads that branch's records from the
trusted verdict store (``review_verdict.reviews_dir()``, files ``<branch with / as __>-<sha12>.json``) and merges their highest
``round`` and their count into ``review_rounds`` and ``review_verdicts``; stray records for another branch or sha are not counted.
A verdict that is also in the task's ``build/review`` (``record.py --lane`` writes both copies) counts once. ``--archive`` still reads
the live store, not an archived copy.

``--archive DIR`` reads the layout ``hass_triage.py archive_evidence`` writes: ``tasks/``, ``review/``,
``gate.jsonl``, ``shadow.jsonl``, ``runs/``, ``status.json``, ``worker.log.tail``, ``owner_replies.json``.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

sys.path.insert(0, str(Path(__file__).resolve().parent))
from redact import redact  # noqa: E402
import review_verdict  # noqa: E402  (stdlib only; read-only use of the trusted store's location)

#: Over-budget defaults (fresh tokens: input + output + cache creation; wall-clock minutes).
MAX_TOKENS = 2_000_000
MAX_MINUTES = 120
#: A slot wait at least this long fires ``slot_wait``.
SLOT_WAIT_MINUTES = 20
#: More review rounds than this fires ``review_rounds_over_cap``.
REVIEW_ROUND_CAP = 2
#: A device round (journeys, perf, coverage on a simulator) at least this long is "long"; this many of them fire
#: ``repeated_long_device_rounds`` (the camera dry run repeated 34-minute rounds, 2026-11-03).
LONG_ROUND_MINUTES = 30
REPEATED_LONG_ROUNDS = 2
DEVICE_LABEL = re.compile(r"(?i)(?<![a-z])(?:uitest|journeys?|device|iphone|duo|ipad|navperf|flingfps|scrollcost|launchperf|motionperf|perf|cov|coverage|pose)(?![a-z])")
#: ios_uitest.sh's deliberate skips of a run that already passed on this tree (they finish in under a second and are not empty runs).
RERUN_SKIP = re.compile(r"already passed on this tree|== nothing to run")
RUN_HEAD = re.compile(r"^RESULT: (?P<verdict>\w+)(?: \(exit (?P<exit>-?\d+)\))?(?:  (?P<label>\S+))?(?:  (?P<time>\S+))?")
RUN_DURATION = re.compile(r"^(?:(\d+)h(\d+)m|(\d+)m(\d+)s|(\d+)s)$")
RUN_COUNTS = re.compile(r"executed (\d+), skipped (\d+), failed (\d+)")

WAITING = re.compile(r"(?i)\b(i'?ll wait|i will wait|waiting (for|on)|will report back|i'?ll report back|"
                     r"once (it|that|they|the \w+) (finishes|completes|is done|are done)|when (it|they) (finish|complete)|"
                     r"standing by|check back (later|when))")
DEVCAP_WAIT = re.compile(r"devcap: still waiting \((?:(\d+)h(\d+)m|(\d+)m|(\d+)s)\)")
TOOL_ERRORS = (
    ("gh_401", re.compile(r"HTTP 401|Requires authentication")),
    ("not_logged_in", re.compile(r"(?i)not logged in|please run /login")),
    ("enospc", re.compile(r"ENOSPC|No space left on device")),
    ("label_not_found", re.compile(r"'[^']+' not found")),
)
LEVELS = ("L0", "L1", "L2", "L3")
#: The gate's route hint as a level, keyed by (visible, chosen, pick) (see ``tools/jev_gate.py`` ROUTES).
HINT_LEVELS = {(False, None, False): "L0", (False, None, True): "L2", (True, True, False): "L1",
               (True, True, True): "L2", (True, False, None): "L2"}


def review_file_name(branch: str) -> str:
    """``build/review/`` file name for a branch (as ``tools/pr_land.py``; not imported, so the runner's import closure stays small)."""
    return branch.replace("/", "__") + ".json"


#: A branch name as ``tools/tasks.py add-branch`` accepts it.
BRANCH_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/-]*$")


def store_records(branch: str, directory: Optional[Path] = None) -> List[Dict[str, Any]]:
    """The trusted verdict store's records for ``branch``: files named ``<branch with / as __>-<sha12>.json`` whose own ``branch``
    equals ``branch`` and whose ``head`` starts with the sha in the name. A stray record (another branch or sha, a name that only
    shares a prefix, unreadable JSON) is skipped. The store is the one the push gate trusts (``review_verdict.reviews_dir``)."""
    if not BRANCH_NAME.match(branch):  # the pattern ``tasks.py add-branch`` validates
        return []
    folder = directory if directory is not None else review_verdict.reviews_dir()
    pattern = re.compile("^" + re.escape(branch.replace("/", "__")) + r"-([0-9a-f]{12})\.json$")
    found: List[Dict[str, Any]] = []
    try:
        names = sorted(os.listdir(folder))
    except OSError:
        return found
    for name in names:
        match = pattern.match(name)
        data = read_json(folder / name) if match else None
        if isinstance(data, dict) and data.get("branch") == branch and str(data.get("head") or "").startswith(match.group(1)):
            found.append(data)
    return found


def clip(text: Any, limit: int = 220) -> str:
    """One redacted, single-line evidence string."""
    out = " ".join(str(text).split())
    return redact(out)[:limit]


def read_json(path: Optional[Path]) -> Any:
    """The parsed JSON file, or None when it is missing or not JSON."""
    if not path:
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8", errors="replace"))
    except (OSError, ValueError):
        return None


def read_jsonl(path: Optional[Path]) -> List[Dict[str, Any]]:
    """The dict records of a JSON-lines file; bad lines are skipped."""
    records: List[Dict[str, Any]] = []
    try:
        text = path.read_text(encoding="utf-8", errors="replace") if path else ""
    except OSError:
        return records
    for line in text.splitlines():
        try:
            item = json.loads(line)
        except ValueError:
            continue
        if isinstance(item, dict):
            records.append(item)
    return records


def parse_time(text: Any) -> Optional[datetime]:
    """An ISO-8601 time (with ``Z`` or an offset), or None."""
    try:
        return datetime.fromisoformat(str(text).replace("Z", "+00:00"))
    except ValueError:
        return None


# MARK: - The claude -p log

def parse_log(path: Optional[Path]) -> Dict[str, Any]:
    """From a stream-json log: the final ``result`` object, the last assistant text, background launches and raw text."""
    info: Dict[str, Any] = {"result": None, "last_text": "", "background": 0, "raw": ""}
    if not path:
        return info
    try:
        raw = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return info
    info["raw"] = raw
    for line in raw.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            event = json.loads(line)
        except ValueError:
            continue
        if not isinstance(event, dict):
            continue
        if event.get("type") == "result":
            info["result"] = event
        elif event.get("type") == "assistant":
            content = (event.get("message") or {}).get("content")
            if isinstance(content, str):
                info["last_text"] = content
                continue
            for block in content or []:
                if not isinstance(block, dict):
                    continue
                if block.get("type") == "text" and str(block.get("text", "")).strip():
                    info["last_text"] = block["text"]
                elif block.get("type") == "tool_use" and (block.get("input") or {}).get("run_in_background"):
                    info["background"] += 1
    if not info["last_text"] and isinstance(info["result"], dict):
        info["last_text"] = str(info["result"].get("result") or "")
    return info


# MARK: - Collection

def find_sources(args: argparse.Namespace) -> Dict[str, Optional[Path]]:
    """Resolve every input path from the flags (an archive layout or a worktree) without requiring any to exist."""
    task = args.task
    src: Dict[str, Optional[Path]] = {}
    if args.archive:
        base = Path(args.archive)
        src.update(ledger=base / "tasks" / f"{task}.json", review=base / "review", gate=base / "gate.jsonl",
                   shadow=base / "shadow.jsonl", runs=base / "runs", status=base / "status.json",
                   log=base / "worker.log.tail", comments=base / "owner_replies.json", out=base / "retro" / f"{task}.json")
    else:
        base = Path(args.worktree or ".")
        build = base / "build"
        src.update(ledger=build / "tasks" / f"{task}.json", review=build / "review", gate=build / "jev" / "gate.jsonl",
                   shadow=build / "jev" / "shadow.jsonl", runs=build / "runs", status=None, log=None, comments=None,
                   out=build / "retro" / f"{task}.json")
    for key, flag in (("status", args.status), ("log", args.log), ("comments", args.comments), ("out", args.json)):
        if flag:
            src[key] = Path(flag)
    return src


def gate_hint(gate: List[Dict[str, Any]]) -> Optional[str]:
    """The level the gate's latest answers route to (the ``jev_gate.py`` table), or None when they are not enough."""
    latest: Dict[str, Any] = {}
    for record in gate:
        name = str(record.get("question", "")).split("@")[0]
        latest[name] = record.get("value")

    def truth(value: Any) -> Optional[bool]:
        if isinstance(value, bool):
            return value
        text = str(value).lower()
        return True if text in ("true", "yes") else False if text in ("false", "no") else None

    visible = truth(latest.get("design.user_visible"))
    pick = truth(latest.get("decision.needs_owner"))
    chosen = truth(latest.get("design.target_decided"))
    if visible is None:
        return None
    key = (False, None, bool(pick)) if visible is False else (True, False, None) if chosen is False else (True, chosen, bool(pick))
    return HINT_LEVELS.get(key)


def wait_minutes(raw: str) -> Tuple[int, str]:
    """The longest ``devcap: still waiting (…)`` in the log, in minutes, and its line."""
    best, line_of = 0, ""
    for line in raw.splitlines():
        match = DEVCAP_WAIT.search(line)
        if not match:
            continue
        h, m, only_m, s = match.groups()
        minutes = int(h) * 60 + int(m) if h else int(only_m) if only_m else int(s or 0) // 60
        if minutes > best:
            best, line_of = minutes, line
    return best, line_of


def live_children(runs: Optional[Path]) -> List[str]:
    """``bg_run`` markers (``LABEL.running``) whose process is still alive."""
    live: List[str] = []
    try:
        markers = sorted(runs.glob("*.running")) if runs else []
    except OSError:
        return live
    for marker in markers:
        data = read_json(marker)
        pid = data.get("pid") if isinstance(data, dict) else None
        try:
            os.kill(int(pid), 0)
        except (TypeError, ValueError, OSError):
            continue
        live.append(f"{marker.stem} pid {pid} still running")
    return live


# MARK: - A lane without a ledger task

def duration_seconds(token: str) -> Optional[int]:
    """Seconds in a ``bg_run`` duration (``45s``, ``3m05s``, ``2h05m``), or None."""
    match = RUN_DURATION.match(token or "")
    if not match:
        return None
    h, m, m2, s2, s = match.groups()
    return int(h) * 3600 + int(m) * 60 if h else int(m2) * 60 + int(s2) if m2 else int(s)


def run_records(runs: Optional[Path]) -> List[Dict[str, Any]]:
    """One record per ``bg_run`` digest (``build/runs/*.digest``): label, verdict, exit, seconds, counts, device flag."""
    records: List[Dict[str, Any]] = []
    try:
        files = sorted(runs.glob("*.digest")) if runs else []
    except OSError:
        return records
    for path in files:
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
            finished = path.stat().st_mtime
        except OSError:
            continue
        lines = text.splitlines()
        head = RUN_HEAD.match(lines[0]) if lines else None
        if not head:
            continue
        label, token = head["label"] or path.stem, head["time"]
        if label and duration_seconds(label) is not None and not token:  # `RESULT: PASS (exit 0)  3m05s`: no label given
            label, token = path.stem, label
        try:
            log_text = path.with_suffix(".log").read_text(encoding="utf-8", errors="replace")
        except OSError:
            log_text = ""
        counts = RUN_COUNTS.search(text)
        seconds = duration_seconds(token or "")
        records.append({
            "label": label or path.stem, "verdict": head["verdict"], "exit": int(head["exit"]) if head["exit"] else None,
            "seconds": seconds, "finished": finished,
            "executed": int(counts[1]) if counts else None, "skipped": int(counts[2]) if counts else None,
            "failed": int(counts[3]) if counts else None,
            "rerun_skip": bool(RERUN_SKIP.search(log_text) or RERUN_SKIP.search(text)),
            "device": bool(DEVICE_LABEL.search(label or path.stem) or "products: " in text or "xcodebuild" in text)})
    return records


def lane_git(worktree: Optional[Path], *args: str) -> str:
    """Output of ``git -C worktree ARGS`` (empty when it fails or there is no checkout)."""
    if not worktree:
        return ""
    try:
        done = subprocess.run(["git", "-C", str(worktree), *args], capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        return ""
    return done.stdout.strip() if done.returncode == 0 else ""


def lane_paths(args: argparse.Namespace) -> Tuple[Optional[Path], str]:
    """(the lane's worktree or None, its branch). ``--worktree`` wins; else ``REPO/.claude/worktrees/NAME`` of this checkout."""
    name = args.lane
    short = name.split("/")[-1]
    worktree: Optional[Path] = Path(args.worktree) if args.worktree else None
    if worktree is None:
        common = lane_git(Path("."), "rev-parse", "--path-format=absolute", "--git-common-dir")
        if common:
            guess = Path(common).parent / ".claude" / "worktrees" / short
            worktree = guess if guess.is_dir() else None
    branch = lane_git(worktree, "rev-parse", "--abbrev-ref", "HEAD") if worktree else ""
    if not branch or branch == "HEAD":
        candidates = [name] if "/" in name else [f"claude/{name}", name]
        probe = worktree or Path(".")
        branch = next((c for c in candidates if lane_git(probe, "rev-parse", "--verify", "--quiet", c)), candidates[0])
    return worktree, branch


def lane_commits(worktree: Optional[Path], branch: str, base: str) -> Dict[str, Any]:
    """Commit count and first/last commit times of ``branch`` since ``base`` (the first of ``base``, origin/main that exists)."""
    probe = worktree or Path(".")
    refs = [base] if base else ["origin/main", "main"]
    ref = next((r for r in refs if lane_git(probe, "rev-parse", "--verify", "--quiet", r)), "")
    out = lane_git(probe, "log", "--format=%ct", f"{ref}..{branch}" if ref else branch, "--") if ref else ""
    times = sorted(int(t) for t in out.split() if t.isdigit())
    return {"base": ref, "count": len(times), "first": times[0] if times else None, "last": times[-1] if times else None}


def digest(args: argparse.Namespace) -> Dict[str, Any]:
    """Build the retro document for ``args.task`` (``lane-NAME`` under ``--lane``)."""
    src = find_sources(args)
    ledger = read_json(src["ledger"])
    ledger = ledger if isinstance(ledger, dict) else {}
    status = read_json(src.get("status"))
    status = status if isinstance(status, dict) else {}
    gate = read_jsonl(src["gate"])
    shadow = read_jsonl(src["shadow"])
    log = parse_log(src.get("log"))
    result = log["result"] if isinstance(log["result"], dict) else {}
    reviews = []
    try:
        review_files = sorted(src["review"].glob("*.json")) if src["review"] else []
    except OSError:
        review_files = []
    if getattr(args, "lane", None):  # only the lane's own branch file (the lane worktree's build/review may hold others)
        review_files = [p for p in review_files if p.name == review_file_name(args.branch)]
    for path in review_files:
        data = read_json(path)
        if isinstance(data, dict):
            reviews.append(data)
    branches = ledger.get("branches") if isinstance(ledger.get("branches"), list) else []
    seen = {(r.get("branch"), r.get("head"), r.get("round")) for r in reviews if r.get("branch") and r.get("head")}
    for branch in dict.fromkeys(b.strip() for b in branches if isinstance(b, str) and b.strip()):  # each ledger branch once
        for record in store_records(branch):  # ``record.py --lane`` also writes the local copy: count a verdict once
            key = (record.get("branch"), record.get("head"), record.get("round"))
            if key not in seen:
                seen.add(key)
                reviews.append(record)
    comments = read_json(src.get("comments"))
    comments = [c for c in comments if isinstance(c, dict)] if isinstance(comments, list) else []
    sources = [name for name, found in (("ledger", ledger), ("status", status), ("gate", gate), ("shadow", shadow),
                                        ("log", log["raw"]), ("review", reviews), ("owner_replies", comments)) if found]

    triggers: List[Dict[str, Any]] = []

    def fire(trigger: str, *evidence: Any) -> None:
        triggers.append({"id": trigger, "evidence": [clip(e) for e in evidence if str(e).strip()]})

    outcome = args.outcome or ""
    state = str(status.get("state") or "")
    if state == "blocked" or outcome.startswith("blocked"):
        fire("blocked", status.get("blocked_reason") or status.get("summary") or outcome)
    if outcome in ("timeout", "blocked:timeout"):
        fire("timeout", "the session ran past the timeout and was stopped")
    if outcome == "retry":
        fire("retry", f"no status file; attempt {args.attempt or '?'} re-queued")
    if outcome in ("worker_failed", "blocked:worker_failed", "blocked:worker_lost"):
        fire("worker_failed", "the session ended without a result")

    rounds = max([int(r.get("round") or 1) for r in reviews] or [0])
    ledger_rounds = int(((ledger.get("rounds") or {}).get("review") or 0)) if isinstance(ledger.get("rounds"), dict) else 0
    rounds = max(rounds, ledger_rounds)
    if rounds > REVIEW_ROUND_CAP:
        fire("review_rounds_over_cap", f"{rounds} review rounds (cap {REVIEW_ROUND_CAP})")

    started = parse_time(status.get("started") or args.started)
    owner_lines = []
    for item in comments:
        when = parse_time(item.get("createdAt") or item.get("created_at"))
        if started and when and when <= started:
            continue
        owner_lines.append(f"{item.get('createdAt') or item.get('created_at') or ''} {item.get('body', '')}")
    if status.get("owner_reply"):
        owner_lines.append(str(status["owner_reply"]))
    if owner_lines:
        fire("owner_correction", *owner_lines[:3])

    history = ledger.get("level_history") if isinstance(ledger.get("level_history"), list) else []
    final_level = ledger.get("level")
    hint = gate_hint(gate)
    override = [f"{h.get('from')} -> {h.get('to')}: {h.get('reason', '')}" for h in history if isinstance(h, dict)]
    if hint and final_level in LEVELS and hint != final_level:
        override.append(f"gate routed to {hint}, final level {final_level}")
    if override:
        fire("routing_override", *override)

    last = str(log["last_text"]).strip()
    tail = last[-400:]
    if tail and WAITING.search(tail):
        fire("waiting_ending", tail)

    usage = result.get("usage") if isinstance(result.get("usage"), dict) else {}
    tokens = sum(int(usage.get(k) or 0) for k in ("input_tokens", "output_tokens", "cache_creation_input_tokens"))
    minutes = round(float(result.get("duration_ms") or 0) / 60000, 1)
    began, ended = parse_time(status.get("started") or args.started), parse_time(status.get("finished"))
    if not minutes and began and ended:
        minutes = round((ended - began).total_seconds() / 60, 1)
    max_tokens, max_minutes = args.max_tokens, args.max_minutes
    over = []
    if tokens > max_tokens:
        over.append(f"{tokens} fresh tokens (limit {max_tokens})")
    if minutes > max_minutes:
        over.append(f"{minutes} minutes (limit {max_minutes})")
    if over:
        fire("over_budget", *over)

    repro = status.get("repro") if isinstance(status.get("repro"), dict) else None
    if repro is None:  # the agent's own status block in the log
        for found in reversed(re.findall(r'"repro"\s*:\s*(\{[^{}]*\})', log["raw"].replace('\\"', '"'))):
            try:
                repro = json.loads(found)
                break
            except ValueError:
                continue
    if isinstance(repro, dict) and str(repro.get("class")) == "timing" and str(repro.get("instrument")) in ("screenshot", "recording"):
        fire("wrong_instrument", f"a {repro.get('instrument')} was used to reproduce a timing-class issue; "
                                 "signposts/os_log/trace with timestamps fit it (agent-roster, Record first)")

    waited, wait_line = wait_minutes(log["raw"])
    if waited >= SLOT_WAIT_MINUTES:
        fire("slot_wait", wait_line, f"{waited} minutes")

    live = live_children(src["runs"])
    if live:
        fire("stopped_with_live_children", *live)

    lane_counts: Dict[str, Any] = {}
    runs = run_records(src["runs"])  # task flows and lanes alike: the same run digests feed these two triggers
    long_rounds = [r for r in runs if r["device"] and (r["seconds"] or 0) >= LONG_ROUND_MINUTES * 60]
    if len(long_rounds) >= REPEATED_LONG_ROUNDS:
        fire("repeated_long_device_rounds", *[f"{r['label']}: {describe_seconds(r['seconds'] or 0)} ({r['verdict']})" for r in long_rounds],
             f"{len(long_rounds)} device rounds of {LONG_ROUND_MINUTES}+ minutes (limit {REPEATED_LONG_ROUNDS - 1})")
    empties = [r for r in runs if r["verdict"] == "EMPTY"
               or (r["verdict"] == "PASS" and r["device"] and (r["executed"] == 0 or (r["seconds"] is not None and r["seconds"] < 2))
                                             and not r["rerun_skip"])]
    if empties:
        fire("empty_runs", *[f"{r['label']}: {r['verdict']}, executed {r['executed'] if r['executed'] is not None else '?'}, "
                             f"skipped {r['skipped'] if r['skipped'] is not None else '?'}, {describe_seconds(r['seconds'] or 0)}"
                             for r in empties])
    if getattr(args, "lane", None):
        commits = lane_commits(args.worktree and Path(args.worktree), args.branch, args.base or "")
        if commits["first"] and commits["last"] and commits["last"] > commits["first"]:
            minutes = round((commits["last"] - commits["first"]) / 60, 1)
            if minutes > args.max_minutes:
                fire("over_budget", f"{minutes} minutes from the first to the last commit (limit {args.max_minutes})")
        lane_counts = {"lane": args.lane, "branch": args.branch, "commits": commits["count"], "base": commits["base"],
                       "first_commit": commits["first"], "last_commit": commits["last"], "runs": len(runs),
                       "run_minutes": round(sum(r["seconds"] or 0 for r in runs) / 60, 1), "empty_runs": len(empties),
                       "long_device_rounds": len(long_rounds)}
        minutes = minutes_between(commits) or minutes

    errors: Dict[str, int] = {}
    first: Dict[str, str] = {}
    for line in log["raw"].splitlines():
        for name, pattern in TOOL_ERRORS:
            if pattern.search(line):
                errors[name] = errors.get(name, 0) + 1
                first.setdefault(name, line)
    if errors:
        fire("tool_error", *[f"{name} x{count}: {first[name]}" for name, count in sorted(errors.items())])

    checks = ledger.get("acceptance") if isinstance(ledger.get("acceptance"), list) else []
    initial = history[0].get("from") if history and isinstance(history[0], dict) else final_level
    intake = ledger.get("intake") or ""
    brief = ledger.get("brief") or ""
    summary = str(status.get("summary") or status.get("blocked_reason") or "").strip()
    return {
        "task": args.task,
        "sources": sources,
        "triggers": triggers,
        "counts": {
            "triggers": len(triggers), "review_rounds": rounds, "review_verdicts": len(reviews),
            "checks": len(checks), "checks_passing": sum(1 for c in checks if isinstance(c, dict) and c.get("passes")),
            "level_changes": len(history), "gate_answers": len(gate), "shadow_records": len(shadow),
            "turns": int(result.get("num_turns") or 0), "attempt": args.attempt or 0,
            "owner_replies": len(comments), "tool_errors": errors, **lane_counts,
        },
        "durations": {"minutes": minutes, "api_minutes": round(float(result.get("duration_api_ms") or 0) / 60000, 1),
                      "slot_wait_minutes": waited},
        "cost": {"total_cost_usd": result.get("total_cost_usd"), "tokens": tokens, "usage": usage,
                 "modelUsage": result.get("modelUsage") if isinstance(result.get("modelUsage"), dict) else {}},
        "outcome": outcome or state or None,
        "level": {"initial": initial, "final": final_level, "gate_hint": hint},
        "aar": {
            "intended": clip(f"{intake} {brief}".strip() + (f" (level {initial})" if initial else ""), 400),
            "happened": clip(f"{outcome or state or 'no status'}: {summary}".strip(": "), 400),
            "why_different": "",
        },
    }


def describe_seconds(seconds: int) -> str:
    """``45s``, ``3m05s`` or ``2h05m`` (the ``bg_run`` digest format)."""
    return f"{seconds}s" if seconds < 60 else f"{seconds // 60}m{seconds % 60:02d}s" if seconds < 3600 else f"{seconds // 3600}h{seconds % 3600 // 60:02d}m"


def minutes_between(commits: Dict[str, Any]) -> float:
    """Minutes from a lane's first to its last commit; 0 when there are fewer than two."""
    if commits.get("first") and commits.get("last"):
        return round((commits["last"] - commits["first"]) / 60, 1)
    return 0.0


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Deterministic evidence digest of one finished flow.")
    parser.add_argument("--task")
    parser.add_argument("--lane", help="a worktree lane or branch with no ledger task (digest from build/runs, build/review and git)")
    parser.add_argument("--base", help="--lane: the ref the lane branched from (default origin/main)")
    parser.add_argument("--worktree")
    parser.add_argument("--log")
    parser.add_argument("--status")
    parser.add_argument("--archive")
    parser.add_argument("--json")
    parser.add_argument("--comments")
    parser.add_argument("--outcome", help="runner outcome: done, blocked:timeout, retry, blocked:worker_failed, ...")
    parser.add_argument("--attempt", type=int)
    parser.add_argument("--started", help="ISO start time (owner replies before it are not corrections)")
    parser.add_argument("--max-tokens", type=int, default=MAX_TOKENS)
    parser.add_argument("--max-minutes", type=float, default=MAX_MINUTES)
    args = parser.parse_args(argv)
    if not args.task and not args.lane:
        parser.error("one of --task or --lane is required")
    if args.worktree and not Path(args.worktree).is_dir():
        print(f"retro_digest: --worktree {args.worktree} does not exist", file=sys.stderr)
        return 2
    if args.lane:
        worktree, args.branch = lane_paths(args)
        args.worktree = str(worktree) if worktree else args.worktree
        args.task = args.task or "lane-" + args.lane.split("/")[-1]
    try:
        document = digest(args)
        out = find_sources(args)["out"]
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
    except Exception as exc:  # noqa: BLE001 (a digest is best effort; the flow it describes already ended)
        print(f"retro_digest: {type(exc).__name__}: {clip(exc)}", file=sys.stderr)
        return 0
    fired = ", ".join(t["id"] for t in document["triggers"]) or "none"
    print(f"{out} (triggers: {fired})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
