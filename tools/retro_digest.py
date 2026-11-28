#!/usr/bin/env python3
"""retro_digest: the deterministic evidence digest of one finished flow (no LLM, no network).

    tools/retro_digest.py --task ID [--worktree PATH] [--log FILE] [--status FILE] [--archive DIR] [--json OUT]
                          [--comments FILE] [--outcome CODE] [--attempt N] [--max-tokens N] [--max-minutes N]
    tools/retro_digest.py --lane NAME [--worktree PATH] [--base REF] [--json OUT] [--max-minutes N]

Reads whatever exists of: the task ledger (``build/tasks/ID.json``), the Jev gate and shadow logs
(``build/jev/gate.jsonl``, ``shadow.jsonl``), the triage status JSON, a ``claude -p`` stream-json log, review
verdicts (``build/review/*.json``), ``bg_run`` digests (``build/runs``) and the owner's replies, and writes
``build/retro/ID.json`` (or ``ARCHIVE/retro/ID.json``, or ``--json OUT``) with the fired ``triggers`` (each with
evidence lines), ``status_stale`` check IDs, ``counts``, ``durations``, ``cost`` and a three-line ``aar`` (after-action
note). A check-only blocked snapshot is suppressed only when a complete matching ledger proves every stale failure
resolved and no independent status signal remains. A missing or unreadable input is skipped, never fatal. The Steward
reads the result; this script never judges it.

Named waits use a blocked status whose ``blocked_reason`` starts with ``owner_wait:`` or ``lane_wait:`` followed by
non-empty text. With a complete matching ledger and matching status task, they count as waits instead of firing
``blocked`` unless reconciliation reports stale status (``pass`` for a ledger check that does not pass, or ``fail`` for
one that does). A missing, unreadable or malformed ledger cancels the wait, as does a mismatching status task. An open
ledger check with ``passes: false`` remains compatible with status ``fail`` or ``not_run``. A runner outcome beginning
with ``blocked`` always remains a block.

``--lane NAME`` (a worktree lane such as ``loop-followups``, or a branch such as ``claude/loop-followups``) digests a lane that has no
ledger task, e.g. an interactive subagent flow, from what it leaves behind: the lane worktree's ``build/runs`` (``*.digest``
and ``*.running`` markers from ``bg_run``, with their durations and executed/skipped/failed counts), ``build/review/<branch>.json``
(the round), and the branch's commit count and timestamps since ``--base`` (default ``origin/main``). It writes ``build/retro/lane-NAME.json`` with the same triggers (``review_rounds_over_cap``, ``over_budget``,
``stopped_with_live_children``) and two lane ones: ``repeated_long_device_rounds`` and ``empty_runs``.

For each branch in the ledger's ``branches`` (``tools/tasks.py add-branch``), the digest also reads that branch's records from the
trusted verdict store (``review_verdict.reviews_dir()``, files ``<branch with / as __>-<sha12>.json``) and merges their highest
``round`` and their count into ``review_rounds`` and ``review_verdicts``; stray records for another branch or sha are not counted.
The cap trigger counts only non-pass records per branch, and branches older than the task's Steward note are not news. A verdict that
is also in the task's ``build/review`` (``record.py --lane`` writes both copies) counts once. ``--archive`` still reads the live store,
not an archived copy.

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
RUN_SHA = re.compile(r"\bsha=(\S+)")
RUN_TASK = re.compile(r"\btask=(\S+)")
RUN_PRODUCTS = re.compile(r"(?m)^products: (?:hit|built) ([0-9a-f]+)")
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
            try:
                data["_retro_record_time"] = (folder / name).stat().st_mtime
            except OSError:
                data["_retro_record_time"] = 0
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
    """From a stream-json log: the final ``result`` object, the last assistant text, background launches and raw text.

    A T3 launch (``agent.launcher: "t3code"``) logs ``t3_launch`` then ``t3_thread`` lines instead: the last assistant message becomes
    ``last_text``, tool outputs are appended to ``raw`` one per line (the ``devcap: still waiting`` scan reads them), there is no
    ``result`` (T3 reports no cost) and ``launcher`` is ``"t3code"`` so the digest says cost ``unknown`` rather than zero."""
    info: Dict[str, Any] = {"result": None, "last_text": "", "background": 0, "raw": "", "launcher": "claude"}
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
        elif event.get("type") == "t3_thread":
            info["launcher"] = "t3code"
            thread = (event.get("data") or {}).get("thread")
            thread = thread if isinstance(thread, dict) else (event.get("data") or {})
            texts = [str(m.get("text") or "") for m in thread.get("messages") or [] if isinstance(m, dict) and m.get("role") == "assistant"]
            info["last_text"] = next((t for t in reversed(texts) if t.strip()), info["last_text"])
            info["raw"] += "\n" + "\n".join(str(c.get("output")) for c in thread.get("toolCalls") or [] if isinstance(c, dict) and c.get("output"))
        elif t3_launch_seen(event):
            info["launcher"] = "t3code"
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


def t3_launch_seen(event: Dict[str, Any]) -> bool:
    """Is ``event`` the first line a T3 launch writes to the log (``t3_launch``, or ``t3_launch_failed`` when it never started)?"""
    return event.get("type") in ("t3_launch", "t3_launch_failed")


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
        default_status = build / "status" / f"{task}.json"  # tools/agent_status.py writes it, when the worktree holds one
        if default_status.is_file():
            src["status"] = default_status
    for key, flag in (("status", args.status), ("log", args.log), ("comments", args.comments), ("out", args.json)):
        if flag:
            src[key] = Path(flag)
    return src


def gate_hint(gate: List[Dict[str, Any]], task: Optional[str] = None) -> Optional[str]:
    """The level the gate's latest answers route to, keeping only exact-subject rows for a task."""
    latest: Dict[str, Any] = {}
    for record in gate:
        if task is not None:
            subject = record.get("subject")
            if not isinstance(subject, str) or not subject or subject != task:
                continue
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


CHECK_ID = re.compile(r"^[a-z][a-z0-9_-]{0,15}$")
STATUS_VALUES = ("pass", "fail", "not_run")


def reconcile_status(task: str, ledger: Dict[str, Any], status: Dict[str, Any]) -> Dict[str, Any]:
    """Compare a matching task's status snapshot with unambiguous Boolean ledger checks."""
    acceptance = ledger.get("acceptance")
    ledger_matches = ledger.get("id") == task
    checks: Dict[str, bool] = {}
    duplicates = set()
    ledger_well_formed = ledger_matches and isinstance(acceptance, list) and bool(acceptance)
    if isinstance(acceptance, list):
        for check in acceptance:
            check_id = check.get("id") if isinstance(check, dict) else None
            passes = check.get("passes") if isinstance(check, dict) else None
            if not isinstance(check_id, str) or not CHECK_ID.fullmatch(check_id) or type(passes) is not bool:  # noqa: E721
                ledger_well_formed = False
                continue
            if check_id in checks:
                duplicates.add(check_id)
                ledger_well_formed = False
                continue
            checks[check_id] = passes
    for check_id in duplicates:
        checks.pop(check_id, None)

    status_matches = ledger_matches and status.get("task") == task
    raw_status_checks = status.get("acceptance")
    status_well_formed = status_matches and isinstance(raw_status_checks, dict)
    stale = set()
    stale_failures = set()
    if status_matches and isinstance(raw_status_checks, dict):
        for check_id, observed in raw_status_checks.items():
            if check_id not in checks or observed not in STATUS_VALUES:
                status_well_formed = False
                continue
            passed = checks[check_id]
            if observed == "fail" and passed:
                stale.add(check_id)
                stale_failures.add(check_id)
            elif observed == "pass" and not passed:
                stale.add(check_id)

    reason = status.get("blocked_reason")
    summary = status.get("summary")
    reported_states = {str(status.get(key) or "").strip() for key in ("state", "status")}
    separate_reason = bool(reported_states & {"needs_decision", "needs_research"})
    questions = [status.get("question")]
    decision = status.get("decision")
    if isinstance(decision, dict):
        if decision.get("owner_only"):
            separate_reason = True
        questions.append(decision.get("question"))
    elif decision is not None:
        separate_reason = True
    if any((question.strip() if isinstance(question, str) else question) for question in questions):
        separate_reason = True
    if reason is None:
        reason_text = ""
    elif isinstance(reason, str):
        reason_text = reason.strip()
    else:
        reason_text, separate_reason = "", True
    if summary is not None and not isinstance(summary, str):
        separate_reason = True
    if reason_text:
        match = re.fullmatch(r"checks:([a-z][a-z0-9_-]{0,15}(?:,[a-z][a-z0-9_-]{0,15})*)", reason_text)
        listed = match.group(1).split(",") if match else []
        if (not match or len(listed) != len(set(listed))
                or set(listed) != stale_failures or not stale_failures):
            separate_reason = True
    elif summary:
        separate_reason = True

    all_checks_pass = ledger_well_formed and all(checks.values())
    suppress = bool(status_well_formed and stale_failures and all_checks_pass and not separate_reason)
    return {"stale": sorted(stale), "suppress": suppress, "ledger_well_formed": ledger_well_formed}


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
    """``bg_run`` markers (``LABEL.running``) whose process is still alive.

    A ``ci-*`` marker is the orchestrator's sanctioned wait (``orchestrator.md``: start ``ci-<pr>`` and end the turn), so it
    is not a stray job and is skipped; when stray jobs are listed, a closing "N ci wait" line says how many were skipped.
    """
    live: List[str] = []
    waits = 0
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
        if marker.stem.startswith("ci-"):
            waits += 1
            continue
        live.append(f"{marker.stem} pid {pid} still running")
    if live and waits:
        live.append(f"{waits} ci wait (sanctioned, not counted)")
    return live


# MARK: - A lane without a ledger task

def duration_seconds(token: str) -> Optional[int]:
    """Seconds in a ``bg_run`` duration (``45s``, ``3m05s``, ``2h05m``), or None."""
    match = RUN_DURATION.match(token or "")
    if not match:
        return None
    h, m, m2, s2, s = match.groups()
    return int(h) * 3600 + int(m) * 60 if h else int(m2) * 60 + int(s2) if m2 else int(s)


def run_records(runs: Optional[Path], task: Optional[str] = None, skipped: Optional[List[str]] = None) -> List[Dict[str, Any]]:
    """One record per ``bg_run`` digest (``build/runs/*.digest``): label, verdict, exit, seconds, counts, device flag.

    With ``task`` (a ledger task) a digest stamped with another task is dropped and its file name appended to ``skipped``. A digest
    with no stamp is kept and marked ``unscoped`` (its task is unknown, so it counts as before). Without ``task`` (``--lane``)
    every digest is kept."""
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
        stamp = (RUN_TASK.search(lines[0]) or [None, None])[1]
        if task is not None and stamp is not None and stamp != task:
            if skipped is not None:
                skipped.append(path.name)
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
            "label": label or path.stem, "unscoped": task is not None and stamp is None, "verdict": head["verdict"], "exit": int(head["exit"]) if head["exit"] else None,
            "seconds": seconds, "finished": finished,
            "sha": (RUN_SHA.search(lines[0]) or [None, ""])[1],
            "products": frozenset(RUN_PRODUCTS.findall(text)),  # keys only: `built K in 9s` and `hit K, saved` name one build
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
    branches = ledger.get("branches") if isinstance(ledger.get("branches"), list) else []
    skipped_reviews: List[str] = []
    if getattr(args, "lane", None):  # only the lane's own branch file (the lane worktree's build/review may hold others)
        review_files = [p for p in review_files if p.name == review_file_name(args.branch)]
    for path in review_files:
        data = read_json(path)
        if not isinstance(data, dict):
            continue
        # A ledger task that lists branches keeps only their rounds; one that lists none cannot be scoped, so it keeps every file.
        if not getattr(args, "lane", None) and branches and data.get("branch") not in branches:
            skipped_reviews.append(path.name)
            continue
        try:
            data["_retro_record_time"] = path.stat().st_mtime
        except OSError:
            data["_retro_record_time"] = 0
        reviews.append(data)
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
    state = str(status.get("state") or status.get("status") or "")  # the runner writes state; agents write status
    reconciliation = reconcile_status(args.task, ledger, status)
    status_suppressed = state == "blocked" and reconciliation["suppress"]
    blocked_reason = status.get("blocked_reason")
    wait_prefixed = state == "blocked" and isinstance(blocked_reason, str) and any(
        blocked_reason.startswith(prefix) and blocked_reason[len(prefix):].strip()
        for prefix in ("owner_wait:", "lane_wait:")
    )
    wait_ledger_invalid = bool(wait_prefixed and not reconciliation["ledger_well_formed"])
    named_wait = bool(wait_prefixed and not wait_ledger_invalid
                      and status.get("task") == args.task and not reconciliation["stale"])
    wait_ledger_evidence = f"ledger {src['ledger']} is missing, unreadable, or malformed"
    if outcome.startswith("blocked"):
        fire("blocked", wait_ledger_evidence if wait_ledger_invalid
             else outcome if status_suppressed else status.get("blocked_reason") or status.get("summary") or outcome)
    elif state == "blocked" and not status_suppressed and not named_wait:
        evidence = (wait_ledger_evidence if wait_ledger_invalid
                    else status.get("blocked_reason") or status.get("summary") or outcome)
        fire("blocked", evidence)
    if outcome in ("timeout", "blocked:timeout"):
        fire("timeout", "the session ran past the timeout and was stopped")
    if outcome == "retry":
        fire("retry", f"no status file; attempt {args.attempt or '?'} re-queued")
    if outcome in ("worker_failed", "blocked:worker_failed", "blocked:worker_lost"):
        fire("worker_failed", "the session ended without a result")

    rounds = max([int(r.get("round") or 1) for r in reviews] or [0])
    ledger_rounds = int(((ledger.get("rounds") or {}).get("review") or 0)) if isinstance(ledger.get("rounds"), dict) else 0
    rounds = max(rounds, ledger_rounds)
    non_pass_by_branch: Dict[str, int] = {}
    newest_by_branch: Dict[str, float] = {}
    confirmation_rounds = 0
    for review in reviews:
        branch = review.get("branch")
        if not isinstance(branch, str) or not branch.strip():
            continue
        record_time = float(review.get("_retro_record_time") or 0)
        newest_by_branch[branch] = max(record_time, newest_by_branch.get(branch, 0))
        if review.get("verdict") in ("changes", "blocker"):
            non_pass_by_branch[branch] = non_pass_by_branch.get(branch, 0) + 1
        elif review.get("verdict") == "pass":
            confirmation_rounds += 1
    review_rounds_max = max(non_pass_by_branch.values(), default=0)
    note = src["out"].with_suffix(".md") if src["out"] else None
    try:
        note_time = note.stat().st_mtime if note else None
    except OSError:
        note_time = None
    for branch, count in sorted(non_pass_by_branch.items()):
        if count > REVIEW_ROUND_CAP and (note_time is None or newest_by_branch.get(branch, 0) > note_time):
            fire("review_rounds_over_cap", f"branch {branch}: {count} non-pass rounds (cap {REVIEW_ROUND_CAP})")

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
    hint = gate_hint(gate, args.task)
    override = []
    for h in history:
        if not isinstance(h, dict):
            continue
        reason = str(h.get("reason") or "").strip()
        lowered = h.get("from") in LEVELS and h.get("to") in LEVELS and LEVELS.index(h["to"]) < LEVELS.index(h["from"])
        away = (hint in LEVELS and h.get("from") in LEVELS and h.get("to") in LEVELS
                and abs(LEVELS.index(h["to"]) - LEVELS.index(hint))
                > abs(LEVELS.index(h["from"]) - LEVELS.index(hint)))
        if not reason or away:
            override.append(f"{h.get('from')} -> {h.get('to')}: {reason}"
                            + ("" if reason or not lowered else " (lowered with no reason recorded)")
                            + (" (moved away from hint)" if away else ""))
    if hint in LEVELS and final_level in LEVELS and LEVELS.index(final_level) < LEVELS.index(hint):
        text = f"gate routed to {hint}, final level {final_level}"
        if LEVELS.index(final_level) < LEVELS.index(hint) and not any(str(h.get("reason") or "").strip() for h in history if isinstance(h, dict)):
            text += ": lowered with no reason recorded"
        override.append(text)
    if override:
        fire("routing_override", *override)
    intake_above_hint = int(
        hint in LEVELS and final_level in LEVELS and not history
        and LEVELS.index(final_level) > LEVELS.index(hint)
    )

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
    skipped_runs: List[str] = []
    # A ledger task keeps only the digests stamped with its id (``bg_run --task``); a lane keeps all of its worktree's.
    runs = run_records(src["runs"], None if getattr(args, "lane", None) else args.task, skipped_runs)
    long_rounds = [r for r in runs if r["device"] and (r["seconds"] or 0) >= LONG_ROUND_MINUTES * 60]
    if len(long_rounds) >= REPEATED_LONG_ROUNDS:
        fire("repeated_long_device_rounds", *[f"{r['label']}: {describe_seconds(r['seconds'] or 0)} ({r['verdict']})" for r in long_rounds],
             f"{len(long_rounds)} device rounds of {LONG_ROUND_MINUTES}+ minutes (limit {REPEATED_LONG_ROUNDS - 1})")
    def superseded(record: Dict[str, Any]) -> bool:
        """An EMPTY record is cleared by an equal-or-later PASS that executed tests on the same sha and products."""
        return bool(record["sha"]) and any(
            o["verdict"] == "PASS" and (o["executed"] or 0) > 0 and o["finished"] >= record["finished"]
            and o["sha"] == record["sha"] and o["products"] == record["products"] for o in runs)

    empties = [r for r in runs if (r["verdict"] == "EMPTY" and not superseded(r))
               or (r["verdict"] == "PASS" and r["device"] and (r["executed"] == 0 or (r["seconds"] is not None and r["seconds"] < 2))
                                             and not r["rerun_skip"])]
    if empties:
        fire("empty_runs", *[f"{r['label']}: {r['verdict']}, executed {r['executed'] if r['executed'] is not None else '?'}, "
                             f"skipped {r['skipped'] if r['skipped'] is not None else '?'}, {describe_seconds(r['seconds'] or 0)}"
                             f"{' (unscoped: no task stamp)' if r['unscoped'] else ''}"
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
    effective_outcome = outcome or ("" if status_suppressed else state) or None
    if outcome:
        happened = outcome if status_suppressed else f"{outcome}: {summary}".strip(": ")
    elif status_suppressed:
        passing = sum(1 for check in checks if isinstance(check, dict) and check.get("passes"))
        happened = f"ledger: {passing}/{len(checks)} checks pass"
    else:
        happened = f"{state or 'no status'}: {summary}".strip(": ")
    return {
        "task": args.task,
        "sources": sources,
        "triggers": triggers,
        "status_stale": reconciliation["stale"],
        "counts": {
            "triggers": len(triggers), "review_rounds": rounds, "review_rounds_max": review_rounds_max,
            "review_verdicts": len(reviews), "confirmation_rounds": confirmation_rounds,
            "checks": len(checks), "checks_passing": sum(1 for c in checks if isinstance(c, dict) and c.get("passes")),
            "level_changes": len(history), "intake_above_hint": intake_above_hint,
            "gate_answers": len(gate), "shadow_records": len(shadow),
            "turns": int(result.get("num_turns") or 0), "attempt": args.attempt or 0, "waits": 1 if named_wait else 0,
            "owner_replies": len(comments), "tool_errors": errors,
            "skipped_runs": len(skipped_runs), "unscoped_runs": sum(1 for r in runs if r["unscoped"]), "skipped_reviews": len(skipped_reviews), **lane_counts,
        },
        "durations": {"minutes": minutes, "api_minutes": round(float(result.get("duration_api_ms") or 0) / 60000, 1),
                      "slot_wait_minutes": waited},
        "cost": {"total_cost_usd": result.get("total_cost_usd"), "tokens": None if log["launcher"] == "t3code" else tokens, "usage": usage,
                 "modelUsage": result.get("modelUsage") if isinstance(result.get("modelUsage"), dict) else {}},
        "outcome": effective_outcome,
        "level": {"initial": initial, "final": final_level, "gate_hint": hint},
        "aar": {
            "intended": clip(f"{intake} {brief}".strip() + (f" (level {initial})" if initial else ""), 400),
            "happened": clip(happened, 400),
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
    counts = document.get("counts") or {}
    if counts.get("skipped_runs"):
        print(f"retro_digest: skipped {counts['skipped_runs']} run digest(s) stamped for another task")
    if counts.get("unscoped_runs"):
        print(f"retro_digest: {counts['unscoped_runs']} run digest(s) carry no task stamp and count as unscoped")
    return 0


if __name__ == "__main__":
    sys.exit(main())
