#!/usr/bin/env python3
"""Where in one session did the tokens go, and would a Jev gate have helped?

Usage: tools/phase_cost.py (--session FILE | --task T) [--projects GLOB ...] [--root DIR] [--out-dir DIR] [--replay]

Reads a Claude Code transcript the way ``tools/token_report.py`` does (same turns, same ``weighted`` cost) and cuts
it into phases at objective markers: an ``Agent`` spawn (its ``subagent_type`` names the phase; parallel spawns in
one turn are separate phases), and a Bash command that *runs* ``tasks.py flip``, ``ship.sh``, ``review/record.py``,
``jev_gate.py`` or the landing script (its first simple command, after ``cd ... &&`` or ``VAR=`` words, and inside a
``tools/bg_run.py LABEL ... --`` or ``tools/devcap.py run ... --`` wrapper; a ``sed``, ``cat`` or ``grep`` of the file
is not a marker). Each assistant turn belongs to the phase open when it was written;
the turn that holds a marker opens the new phase. A spawn phase also carries its subagent's own cost: the
``<session>/subagents/agent-<id>.jsonl`` transcript the Agent result names, else the usage the result reports.

Writes ``build/retro/<task>.phases.json`` (phase, kind, fresh tokens, weighted cost, minutes, share). A phase is
flagged when its weighted cost is above ``COST_FLOOR`` (an absolute floor; the share of the session is reported but is
not a condition, so a long session of several large phases flags each), the session has more than one phase and the
kind has a ``CANDIDATES`` row. Over the thresholds with no row it is reported as
``no_candidates`` and is not a flag. For each flagged phase ``CANDIDATES`` lists the Jev questions that could have
caught it earlier.

With ``--replay``, and only when a key file exists and the phase has archived input (the spawn prompt, sent through
``tools/redact.py``), the questions are asked in shadow through ``jev_ask.ask_question``; each reports "would have
routed differently" as ``yes`` (the gate would have fired), ``no``, ``unsure`` or ``not run``. Replay is not free of
side effects: a shadow-mode question appends a row to ``build/jev/shadow.jsonl`` with subject ``phase_cost:<task>:<n>``
(``jev_ask`` has no source tag; readers of that file can skip the prefix), and a replay ``yes`` is shadow evidence, not
a measurement. Without a key or input the replay reports ``not run``; it never errors.

Snippets are cut and passed through ``tools/redact.py``; no other transcript text is printed or written.
The Steward proposes a gate only when the same phase kind is flagged in two or more sessions
(``.agents/workflow/token-economy.md``).
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import sys
import time
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent / "hooks"))
import redact  # noqa: E402
import shell_parse  # noqa: E402
import token_report  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
STARTED = time.time()
"""This process's start: a transcript written to after it is the calling session's, never the one asked about."""
COST_FLOOR = 10_000_000.0
"""A phase is flagged only above this absolute weighted cost (``token_report.weighted`` units), so a small session never
flags. Calibrated on the real sessions (owner "Yep", 2026-11-05); the old 35 percent share condition is gone."""
SNIPPET_CHARS = 160
DEFAULT_PROJECTS = (token_report.default_project_glob(), str(Path.home()).replace("/", "-") + "-hass-agents-worktrees-*")
"""Transcript folders under ``~/.claude/projects``: interactive sessions and the triage runner's per-issue sessions."""

#: Script path suffix -> phase kind. A marker is an *execution*: the script is the first word of a simple command.
SCRIPTS = (
    ("review/record.py", "review_record"),
    ("jev_gate.py", "gate"),
    ("pr_land.sh", "land"),
    ("pr_land.py", "land"),
    ("ship.sh", "ship"),
)
INTERPRETERS = {"python", "python3", "bash", "sh", "zsh"}
#: Scripts that run the command after their first ``--``: ``bg_run.py LABEL -- CMD``, ``devcap.py run --sim U -- CMD``.
WRAPPER_SCRIPTS = ("bg_run.py", "devcap.py")

# Phase kind -> Jev questions whose state existed at the phase start and that could have routed it differently.
# Per-item questions (they need items we do not have) are left out.
CANDIDATES: Dict[str, List[str]] = {
    "coder_rework": ["review.finding_family", "code.custom_machinery", "context.patterns"],
    "design_loop": ["design.target_decided", "decision.needs_owner"],
    "coder": ["code.custom_machinery", "context.patterns"],
    "reviewer": ["review.finding_family", "review.weakens_safety"],
    "researcher": ["research.release_impact"],
    "verifier": ["check.tests"],
}
#: A choice question fires (the gate would have said something) when its top label is one of these.
FIRES_LABELS: Dict[str, set] = {
    "review.finding_family": {"pattern_rule", "system_api_first", "tests_missing_or_weak"},
}


# MARK: - Markers

def kind_of(subagent: str, previous: List[str]) -> str:
    """The phase kind for an Agent spawn of ``subagent`` after the phases ``previous`` (kinds, oldest first)."""
    name = (subagent or "general-purpose").lower()
    if name == "designer":
        return "design_loop"
    if name == "coder" and any(k in ("reviewer", "review_record") for k in previous):
        return "coder_rework"
    return name


def script_kind(words: List[str]) -> Optional[str]:
    """The marker kind when the simple command ``words`` *runs* a marker script, else ``None``."""
    words = shell_parse.strip_prefixes(list(words))
    if words and os.path.basename(words[0]) in INTERPRETERS:
        words = words[1:]
        while words and words[0].startswith("-"):
            words = words[1:]
    if not words:
        return None
    head = words[0]
    if os.path.basename(head) in WRAPPER_SCRIPTS:
        return script_kind(words[words.index("--") + 1:]) if "--" in words else None
    if head.endswith("tasks.py"):
        return "flip" if words[1:2] == ["flip"] else None
    for suffix, kind in SCRIPTS:
        if head == suffix or head.endswith("/" + suffix):
            return kind
    return None


def command_kind(command: str) -> Optional[str]:
    """The marker kind of the first executed marker in a Bash ``command``, else ``None``."""
    for _, words in shell_parse.tokenize(command):
        kind = script_kind(words)
        if kind:
            return kind
    return None


def markers_of(blocks: List[Dict[str, Any]], previous: List[str]) -> List[Dict[str, str]]:
    """Every marker in an assistant turn's content blocks: ``{"kind", "prompt", "tool_use_id"}`` dicts, in order."""
    found: List[Dict[str, str]] = []
    for block in blocks:
        if block.get("type") != "tool_use":
            continue
        data = block.get("input") or {}
        if block.get("name") in ("Agent", "Task"):
            kind = kind_of(str(data.get("subagent_type", "")), previous + [m["kind"] for m in found])
            found.append({"kind": kind, "prompt": str(data.get("prompt", "")), "tool_use_id": str(block.get("id", ""))})
        elif block.get("name") == "Bash":
            kind = command_kind(str(data.get("command", "")))
            if kind:
                found.append({"kind": kind, "prompt": "", "tool_use_id": ""})
    return found


# MARK: - Phases

def load_turns(path: Path) -> tuple:
    """``(turns, results)``.

    ``turns``: assistant turns (one per message id, time order) with ``usage``, ``model``, ``time`` and content
    ``blocks``. ``results``: ``{tool_use_id: toolUseResult}`` for Agent results (agent id, usage, model).
    """
    by_id: Dict[str, Dict[str, Any]] = {}
    results: Dict[str, Dict[str, Any]] = {}
    with open(path, encoding="utf-8", errors="replace") as handle:
        for raw in handle:
            try:
                record = json.loads(raw)
            except ValueError:
                continue
            outcome = record.get("toolUseResult")
            if record.get("type") == "user" and isinstance(outcome, dict) and outcome.get("agentId"):
                content = (record.get("message") or {}).get("content")
                for block in content if isinstance(content, list) else []:
                    if block.get("type") == "tool_result":
                        results[str(block.get("tool_use_id"))] = outcome
            if record.get("type") != "assistant":
                continue
            message = record.get("message") or {}
            key = message.get("id") or record.get("uuid")
            turn = by_id.setdefault(key, {"model": message.get("model") or "", "usage": message.get("usage") or {},
                                          "time": record.get("timestamp"), "blocks": []})
            turn["blocks"].extend(message.get("content") or [])
    turns = sorted((t for t in by_id.values() if t["usage"] and t["time"]), key=lambda t: t["time"])
    return turns, results


def fresh(usage: Dict[str, Any]) -> int:
    """Tokens the turn paid full price for: input, cache writes and output (not cache reads)."""
    return usage.get("input_tokens", 0) + usage.get("cache_creation_input_tokens", 0) + usage.get("output_tokens", 0)


def subagent_cost(path: Path, result: Dict[str, Any]) -> tuple:
    """``(weighted cost, fresh tokens, source)`` of the subagent an Agent ``result`` names.

    Its own transcript (``<session>/subagents/agent-<id>.jsonl``) when present (``source`` ``transcript``), else the
    usage the result reports (``result``), else zero (``none``).
    """
    sub = path.parent / path.stem / "subagents" / f"agent-{result.get('agentId')}.jsonl"
    if sub.exists():
        turns = token_report.Session(sub).load().turns
        return (sum(token_report.weighted(t["usage"], t["model"]) for t in turns),
                sum(fresh(t["usage"]) for t in turns), "transcript")
    usage = result.get("usage")
    if isinstance(usage, dict):
        return token_report.weighted(usage, str(result.get("resolvedModel") or "sonnet")), fresh(usage), "result"
    return 0.0, 0, "none"


def split(turns: List[Dict[str, Any]], results: Optional[Dict[str, Any]] = None,
          path: Optional[Path] = None) -> List[Dict[str, Any]]:
    """Cut ``turns`` into phase dicts; each keeps its spawn ``prompt`` for the replay until :func:`run` drops it.

    A spawn phase also carries its subagent's own cost (``subagent_cost``, ``subagent_source``) when ``results`` and
    ``path`` let it be found. A session with one phase is never flagged; a phase over the thresholds whose kind has
    no ``CANDIDATES`` row is marked ``no_candidates`` and not flagged.
    """
    phases: List[Dict[str, Any]] = []

    def open_phase(turn: Dict[str, Any], kind: str, prompt: str = "", tool_use_id: str = "") -> None:
        phases.append({"kind": kind, "start": turn["time"], "end": turn["time"], "fresh_tokens": 0, "cost": 0.0,
                       "turns": 0, "prompt": prompt, "tool_use_id": tool_use_id, "subagent_cost": 0.0,
                       "subagent_source": "none"})

    for turn in turns:
        found = markers_of(turn["blocks"], [p["kind"] for p in phases])
        if not phases and not found:
            open_phase(turn, "work")
        for marker in found:
            open_phase(turn, marker["kind"], marker["prompt"], marker["tool_use_id"])
        current = phases[len(phases) - len(found)] if found else phases[-1]
        current["fresh_tokens"] += fresh(turn["usage"])
        current["cost"] += token_report.weighted(turn["usage"], turn["model"])
        current["turns"] += 1
        for phase in phases[len(phases) - max(len(found), 1):]:
            phase["end"] = turn["time"]
    for phase in phases:
        result = (results or {}).get(phase["tool_use_id"])
        if result and path is not None:
            cost, tokens, source = subagent_cost(path, result)
            phase["subagent_cost"], phase["subagent_source"] = cost, source
            phase["cost"] += cost
            phase["fresh_tokens"] += tokens
    total = sum(p["cost"] for p in phases) or 1.0
    for index, phase in enumerate(phases):
        end = phases[index + 1]["start"] if index + 1 < len(phases) else phase["end"]
        phase["minutes"] = round((token_report.parse_time(end) - token_report.parse_time(phase["start"])).total_seconds() / 60, 1)
        phase["phase"] = index + 1
        phase["share"] = round(phase["cost"] / total, 3)
        phase["cost"] = round(phase["cost"], 1)
        phase["subagent_cost"] = round(phase["subagent_cost"], 1)
        over = len(phases) > 1 and phase["cost"] > COST_FLOOR
        phase["no_candidates"] = over and phase["kind"] not in CANDIDATES
        phase["flagged"] = over and not phase["no_candidates"]
    return phases


def snippet(text: str) -> str:
    """A short redacted excerpt of ``text``."""
    return redact.redact(" ".join(text.split())[:SNIPPET_CHARS])


# MARK: - Replay

def verdict(decision: Any, happened: Optional[str] = None) -> str:
    """Would the question have routed this phase differently? Compared per question type.

    - boolean (``noul``): ``yes`` / ``no`` from its banded value, ``unsure`` inside the band.
    - set (``noul-set``): ``yes`` when any option is picked, ``no`` when none is, ``unsure`` inside the bands.
    - choice: with ``happened`` (the label of what actually occurred) ``differs`` when the top label is another one,
      else ``same``; without it ``yes`` when the top label is in ``FIRES_LABELS`` for the question, else ``no``.
    - per-item questions are never replayed (no items): ``unsure``.
    """
    question = decision.question
    if question.data.get("per_item") or not decision.accepted:
        return "unsure"
    kind = question.data["type"]
    if kind == "choice":
        label = str(decision.value)
        if happened is not None:
            return "same" if label == happened else "differs"
        return "yes" if label in FIRES_LABELS.get(question.id, set()) else "no"
    if kind == "noul-set":
        return "yes" if decision.value else "no"
    if kind == "noul":
        return "yes" if decision.value is True else "no" if decision.value is False else "unsure"
    return "unsure"


def replay(phase: Dict[str, Any], questions: Dict[str, Any], ask: Any, subject: str) -> Dict[str, str]:
    """Per candidate question, the :func:`verdict` of a shadow ask on the phase's redacted spawn prompt, or ``not run``."""
    text = redact.redact(phase.get("prompt") or "")
    out: Dict[str, str] = {}
    for qid in phase["candidates"]:
        question = questions.get(qid)
        if question is None or not text or ask is None:
            out[qid] = "not run"
            continue
        context = {f: text for f in (question.data.get("state") or {}).get("fields") or ["plan"]}
        try:
            decision = ask(question, context, subject=subject)
        except Exception:  # a replay must never fail the report
            decision = None
        out[qid] = "not run" if decision is None else verdict(decision)
    return out


def jev() -> tuple:
    """``(questions, ask)`` when ``jev_ask`` loads and a key exists, else ``({}, None)``."""
    try:
        import jev_ask
        if jev_ask.api_key():
            return jev_ask.load_questions(), jev_ask.ask_question
    except Exception:
        pass
    return {}, None


def run(path: Path, task: str, out_dir: Path, do_replay: bool = False, questions: Optional[Dict[str, Any]] = None,
        ask: Any = None) -> Dict[str, Any]:
    """Build the report for ``path``, write ``<task>.phases.json`` under ``out_dir`` and return it.

    ``questions`` and ``ask`` replace the real Jev (tests); with ``do_replay`` and no ``ask``, :func:`jev` decides.
    """
    turns, results = load_turns(path)
    phases = split(turns, results, path)
    if do_replay and ask is None:
        questions, ask = jev()
    for phase in phases:
        prompt = phase.pop("prompt")
        phase.pop("tool_use_id", None)
        phase["snippet"] = snippet(prompt)
        phase["candidates"] = CANDIDATES.get(phase["kind"], []) if phase["flagged"] else []
        if phase["flagged"] and do_replay:
            phase["replay"] = replay(dict(phase, prompt=prompt), questions or {}, ask, f"phase_cost:{task}:{phase['phase']}")
    report = {"task": task, "session": path.stem[:12], "cost_floor": COST_FLOOR, "phases": phases}
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / f"{task}.phases.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    return report


# MARK: - Finding the session

def first_user_text(path: Path) -> str:
    """Text of the first user turn of the transcript at ``path`` (``""`` when none)."""
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            for raw in handle:
                try:
                    record = json.loads(raw)
                except ValueError:
                    continue
                if record.get("type") != "user":
                    continue
                content = (record.get("message") or {}).get("content")
                if isinstance(content, str):
                    return content
                if isinstance(content, list):
                    return " ".join(str(b.get("text", "")) for b in content if b.get("type") == "text")
    except OSError:
        pass
    return ""


def find_task_session(root: Path, projects: Iterable[str], task: str, exclude: Iterable[str] = (),
                      started: Optional[float] = None) -> Optional[Path]:
    """The transcript under ``root`` that is most plausibly the session about ``task``, never the calling one.

    Left out: a transcript whose id is in ``exclude`` (the running session) and one written to since ``started``
    (default: this process's start). Of the rest, one whose *first* user turn names ``task`` beats one that only
    mentions it later; ties go to the newest.
    """
    cutoff = STARTED if started is None else started
    skip = set(exclude)
    best, best_key = None, None
    for pattern in projects:
        for directory in glob.glob(str(root / pattern)):
            for path in Path(directory).glob("*.jsonl"):
                try:
                    stamp = path.stat().st_mtime
                    if path.stem in skip or stamp >= cutoff:
                        continue
                    if task not in path.read_text(encoding="utf-8", errors="replace"):
                        continue
                except OSError:
                    continue
                key = (2 if task in first_user_text(path) else 1, stamp)
                if best_key is None or key > best_key:
                    best, best_key = path, key
    return best


def running_sessions() -> List[str]:
    """Ids of the session running this tool, from the environment."""
    return [v for v in (os.environ.get("CLAUDE_CODE_SESSION_ID"), os.environ.get("CLAUDE_SESSION_ID")) if v]


def render(report: Dict[str, Any]) -> str:
    """A short plain-text table of the phases."""
    lines = [f"{report['task']}: {len(report['phases'])} phases",
             "  #  kind            fresh-tok   cost(M)   min  share  flag"]
    for p in report["phases"]:
        flag = "FLAG" if p["flagged"] else "no_candidates" if p["no_candidates"] else ""
        lines.append(f"{p['phase']:3}  {p['kind'][:14]:14} {p['fresh_tokens']:10} {p['cost'] / 1e6:8.1f} {p['minutes']:5.1f} "
                     f"{100 * p['share']:5.1f}%  {flag}")
        if p["flagged"]:
            lines.append("       questions: " + ", ".join(p["candidates"]))
            for question, answer in (p.get("replay") or {}).items():
                lines.append(f"       would have routed differently, {question}: {answer}")
    return "\n".join(lines)


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--session", type=Path, help="a transcript .jsonl file")
    parser.add_argument("--task", help="task id: names the output and, without --session, finds the transcript")
    parser.add_argument("--projects", action="append", help="glob of project directories under --root (repeatable)")
    parser.add_argument("--root", type=Path, default=Path(os.path.expanduser("~/.claude/projects")))
    parser.add_argument("--out-dir", type=Path, default=ROOT / "build" / "retro")
    parser.add_argument("--replay", action="store_true",
                        help="ask the candidate Jev questions in shadow (needs a key; appends shadow.jsonl rows)")
    args = parser.parse_args(argv)
    path = args.session
    if path is None and args.task:
        path = find_task_session(args.root, args.projects or DEFAULT_PROJECTS, args.task, running_sessions())
    if path is None or not path.exists():
        print("phase_cost: no transcript found (give --session FILE or a --task that appears in one)", file=sys.stderr)
        return 1
    print(render(run(path, args.task or path.stem[:12], args.out_dir, args.replay)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
