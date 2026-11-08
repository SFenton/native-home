#!/usr/bin/env python3
"""Classify Jev gate and shadow answers against independent outcomes, and stage vetted rows for the corpus.

Usage: ``tools/jev_miss.py --task T`` or ``tools/jev_miss.py --since 7d`` (``--root DIR`` reads and writes another
tree, ``--no-gh`` skips CI and PR lookups). It always exits 0; a missing source is noted on stderr, never fatal.

Joins ``build/jev/gate.jsonl`` and ``build/jev/shadow.jsonl`` (rows from ``jev_ask.log_gate`` / ``log_shadow``; the
subject is a task id or ``pr:N``; ``--task T`` also takes the task's ``pr:N`` rows) with outcomes Jev did not produce:

- ``review_verdict``: the independent Reviewer's record ``build/review/<branch with / as __>.json`` (fields ``verdict``,
  ``findings[].rule/detail``, ``branch``, ``head``; the branch of ``pr:N`` comes from ``gh pr view``). It answers
  ``check.tests`` (true = Jev said a required test is missing; truth = a finding whose ``rule``/``category`` is the
  tests rule exists, false = a record with none; the record must be the answer's own head or round, else the row is
  ``stale_truth: true`` and not staged, because ``record.py`` overwrites per round) and ``code.custom_machinery`` (only a ``false_negative`` when a rung-0 / system-API-first finding exists;
  no such finding proves nothing). ``code.custom_machinery`` is not logged in production yet; the mapping waits for it.
  CI is not a truth for ``check.tests``: green CI says tests passed, not that the required ones exist.
- ``release_note_ui_diff``: one way only. No ``lane_land.app_ui_paths`` path and no Release-Note other than ``none``
  means ``design.user_visible`` is false (a label). A UI path or a note gives ``no_truth: true`` (speed and reliability
  notes are not visible), never staged.
- ``ledger_final_level``: the ledger level after review against the gate's route hint (``retro_digest.gate_hint``).
  It is a miss *signal* only (``self_influenced: true``): agents raise levels from the gate's own hints and a level never
  goes down, so it is never harvested and never becomes a label.
- ``owner_prompt_log`` is allowed as a source but has no reader yet; no row uses it. ``ci`` likewise maps to no question.

Gate and shadow rows carry no state text (``jev_ask`` logs "never the state text"), and the answer cache under
``build/jev/cache`` is keyed by a hash of model, questions and state that the rows do not carry (``calls.jsonl`` keeps
only 16 characters of it, with a tag and a second), and the cache file holds answers, not state. So the state cannot be
recovered: every row without a ``state`` / ``snippet`` field is marked ``needs_state: true`` and is never staged as a
label candidate. Logging the state needs a change to ``tools/jev_ask.py``, which is protected: a follow-up.

It writes ``build/jev/misses.jsonl`` (``question, subject, jev, p, truth, truth_source, kind, suggestion, needs_state,
self_influenced``) and, for allowed truth sources with state text, ``build/jev/harvest/<question>.jsonl`` (state through
``tools/redact.py``, a deterministic ``split`` from a hash of the row id). Questions whose truth would be an agent's
reading of text (``owner_msg.*``, ``turn.*``, ``transcript.turn_kind``, ``research.*``) are marked ``needs_blind_label``
and never harvested. Appending harvested rows to ``contracts/jev/derived/labels`` is a separate, append-only Coder lane.

It never writes under ``contracts/`` or ``evals/``, never reads a key and never calls Jev.
"""

from __future__ import annotations

import argparse
import calendar
import hashlib
import json
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Tuple

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lane_land  # noqa: E402
import redact  # noqa: E402
import retro_digest  # noqa: E402
from pr_land import review_file_name  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
#: Truth sources a harvested row may carry (code or an independent human/Reviewer, never an agent reading text).
ALLOWED_SOURCES = ("ci", "review_verdict", "ledger_final_level", "owner_prompt_log", "release_note_ui_diff")
#: Question prefixes whose truth is a reading of text; they need the blind second labeller.
BLIND_PREFIXES = ("owner_msg.", "turn.", "transcript.", "research.")
ROUTE_QUESTIONS = ("design.user_visible", "decision.needs_owner", "design.target_decided")
UNSURE_BAND = (0.3, 0.7)
HELDOUT_EVERY = 5


# MARK: - Small helpers

def note(message: str) -> None:
    """Report a missing source on stderr; never fatal."""
    print(f"jev_miss: {message}", file=sys.stderr)


def read_jsonl(path: Path) -> List[Dict[str, Any]]:
    """Rows of a JSON-lines file; ``[]`` (with a note) when it is missing or unreadable, bad lines skipped."""
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError:
        note(f"missing {path}")
        return []
    rows = []
    for line in lines:
        try:
            row = json.loads(line)
        except ValueError:
            continue
        if isinstance(row, dict):
            rows.append(row)
    return rows


def read_json(path: Path) -> Optional[Dict[str, Any]]:
    """A JSON object file, or None."""
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    return data if isinstance(data, dict) else None


def as_bool(value: Any) -> Optional[bool]:
    """True/False for a boolean-like Jev value, None otherwise."""
    if isinstance(value, bool):
        return value
    text = str(value).strip().lower()
    return True if text in ("true", "yes") else False if text in ("false", "no") else None


def parse_since(text: str, now: Optional[float] = None) -> float:
    """Epoch seconds for ``7d`` / ``12h`` ago.

    Raises:
        ValueError: The text is not ``<n>d`` or ``<n>h``.
    """
    match = re.fullmatch(r"(\d+)([dh])", text.strip())
    if not match:
        raise ValueError(f"--since wants 7d or 12h, got {text!r}")
    seconds = int(match.group(1)) * (86400 if match.group(2) == "d" else 3600)
    return (time.time() if now is None else now) - seconds


def row_time(row: Dict[str, Any]) -> float:
    """Epoch seconds of a row's ``at`` stamp, 0 when absent."""
    try:
        return calendar.timegm(time.strptime(str(row.get("at")), "%Y-%m-%dT%H:%M:%SZ"))
    except ValueError:
        return 0.0


def question_name(row: Dict[str, Any]) -> str:
    """The question id without its ``@version``."""
    return str(row.get("question", "")).split("@")[0]


def row_id(row: Dict[str, Any]) -> str:
    """A stable id from question, subject, time and value."""
    key = "|".join(str(row.get(k, "")) for k in ("question", "subject", "at", "value"))
    return hashlib.sha256(key.encode()).hexdigest()[:12]


def split_of(identifier: str) -> str:
    """``heldout`` for one id in five, else ``train``; deterministic from the id's hash."""
    return "heldout" if int(hashlib.sha256(identifier.encode()).hexdigest(), 16) % HELDOUT_EVERY == 0 else "train"


def probability(row: Dict[str, Any]) -> Optional[float]:
    """P(true) of a gate row (``p``) or a shadow row (``probabilities.true``)."""
    if isinstance(row.get("p"), (int, float)):
        return float(row["p"])
    probs = row.get("probabilities")
    if isinstance(probs, dict) and isinstance(probs.get("true"), (int, float)):
        return float(probs["true"])
    return None


# MARK: - Outcome sources

def product_repo() -> str:
    """The product repository (``owner/name``) from ``tools/triage/config.json``, read at runtime."""
    try:
        value = json.loads((Path(__file__).resolve().parent / "triage" / "config.json").read_text(encoding="utf-8")).get("product_repo")
    except (OSError, ValueError):
        value = ""
    return value if isinstance(value, str) and value else "-"


class Outcomes:
    """Lazy lookups of the independent outcome sources under one root; each degrades to None when unavailable."""

    def __init__(self, root: Path, use_gh: bool = True, runner: Optional[Callable[[List[str]], str]] = None) -> None:
        self.root, self.use_gh = root, use_gh
        self.runner = runner or self._gh
        self.cache: Dict[Tuple[str, str], Any] = {}

    @staticmethod
    def _gh(args: List[str]) -> str:
        done = subprocess.run(["gh", *args], capture_output=True, text=True, timeout=60)
        if done.returncode not in (0, 8):  # 8: pending checks still print
            raise OSError(done.stderr.strip() or "gh failed")
        return done.stdout

    def ledger(self, task: str) -> Optional[Dict[str, Any]]:
        """The task's ledger entry."""
        return read_json(self.root / "build" / "tasks" / f"{task}.json")

    def branch(self, number: str) -> Optional[str]:
        """The head branch of PR ``number`` (``gh pr view``), or None."""
        if not self.use_gh:
            return None
        key = ("branch", number)
        if key not in self.cache:
            try:
                self.cache[key] = json.loads(self.runner(["pr", "view", number, "--json", "headRefName"]) or "{}").get(
                    "headRefName")
            except (OSError, ValueError, subprocess.SubprocessError) as exc:
                note(f"branch of pr:{number} unavailable ({exc})")
                self.cache[key] = None
        return self.cache[key]

    def pr_numbers(self, task: str) -> List[str]:
        """PR numbers the task's ledger entry names (``pr``, ``pr_number`` or a product-repo ``/pull/N`` URL)."""
        ledger = self.ledger(task) or {}
        found = [str(ledger[k]) for k in ("pr", "pr_number") if ledger.get(k)]
        found += re.findall(r"github\.com/" + re.escape(product_repo()) + r"/pull/(\d+)", json.dumps(ledger))
        return sorted(set(found))

    def invisible(self, number: str) -> Optional[bool]:
        """True when no app-UI path changed (``lane_land.app_ui_paths`` is empty) and no Release-Note other than
        ``none`` exists; False when either exists (the PR may still be invisible: speed and reliability notes are not
        visible, so that gives no truth); None when unknown."""
        if not self.use_gh:
            return None
        key = ("ui", number)
        if key not in self.cache:
            try:
                data = json.loads(self.runner(["pr", "view", number, "--json", "commits,files"]) or "{}")
                notes = []
                for commit in data.get("commits") or []:
                    body = f"{commit.get('messageHeadline', '')}\n{commit.get('messageBody', '')}"
                    notes += re.findall(r"(?mi)^Release-Note:\s*(.+)$", body)
                paths = [str(f.get("path", "")) for f in data.get("files") or []]
                ui = lane_land.app_ui_paths([("M", p, "", "") for p in paths])
                self.cache[key] = not ui and all(n.strip().lower() == "none" for n in notes)
            except (OSError, ValueError, subprocess.SubprocessError) as exc:
                note(f"PR pr:{number} unavailable ({exc})")
                self.cache[key] = None
        return self.cache[key]

    def review(self, subject: str) -> Optional[Dict[str, Any]]:
        """The Reviewer record for the subject's branch (``pr:N`` via the PR, else the subject as a branch name)."""
        branch = self.branch(subject[3:]) if subject.startswith("pr:") else subject
        if not branch:
            return None
        return read_json(self.root / "build" / "review" / review_file_name(branch))


def finding_text(record: Dict[str, Any]) -> str:
    """The Reviewer findings' rule, family and detail as one string."""
    return " ".join(f"{f.get('rule', '')} {f.get('family', '')} {f.get('detail', '')}"
                    for f in record.get("findings") or [] if isinstance(f, dict))


def review_flags_machinery(record: Dict[str, Any]) -> bool:
    """True when a Reviewer finding names custom machinery or the rung-0 / system-API-first rule."""
    return bool(re.search(r"(?i)machinery|rung[- ]?0|system[- ]api[- ]first", finding_text(record)))


TESTS_RULE = re.compile(r"(?i)tests?(?:[._:/-].*)?")


def review_flags_tests(record: Dict[str, Any]) -> bool:
    """True when a finding's ``rule`` or ``category`` field is the tests rule (``tests``, ``tests.missing``); the word
    "test" in a detail does not count."""
    return any(TESTS_RULE.fullmatch(str(f.get(k) or "")) for f in record.get("findings") or []
               if isinstance(f, dict) for k in ("rule", "category"))


def record_matches(record: Dict[str, Any], row: Dict[str, Any]) -> bool:
    """True when the Reviewer record is the one the answer was asked about: the row carries a ``head`` (or ``round``)
    equal to the record's. ``record.py`` overwrites the file each round and gate rows carry neither, so usually False."""
    return bool((row.get("head") and row.get("head") == record.get("head"))
                or (row.get("round") and row.get("round") == record.get("round")))


# MARK: - Classification

def classify(jev: Optional[bool], truth: bool, p: Optional[float]) -> Tuple[str, str]:
    """``(kind, suggestion)`` for a boolean answer against its truth."""
    if jev is True and not truth:
        return "false_positive", "tighten_or_remove"
    if jev is not True and truth:
        return "false_negative", "add_question"
    if p is not None and UNSURE_BAND[0] <= p <= UNSURE_BAND[1]:
        return "unsure_band", "label_only"
    return "agree", "label_only"


def level_miss(hint: str, final: str) -> Tuple[str, str]:
    """``(kind, suggestion)`` for a route hint against the ledger's final level."""
    order = retro_digest.LEVELS
    if hint == final:
        return "agree", "label_only"
    if order.index(final) > order.index(hint):
        return "false_negative", "add_question"
    return "false_positive", "tighten_or_remove"


def state_of(row: Dict[str, Any]) -> str:
    """The state text a row carries (``state`` or ``snippet``), usually empty."""
    return str(row.get("state") or row.get("snippet") or "")


def make_row(source: Dict[str, Any], truth: Any, truth_source: str, kind: str, suggestion: str) -> Dict[str, Any]:
    """One ``misses.jsonl`` row."""
    return {"question": question_name(source), "subject": source.get("subject", ""), "jev": source.get("value"),
            "p": probability(source), "truth": truth, "truth_source": truth_source, "kind": kind,
            "suggestion": suggestion, "id": row_id(source), "needs_state": not state_of(source),
            "self_influenced": truth_source == "ledger_final_level", "stale_truth": False, "no_truth": False}


def judge(rows: List[Dict[str, Any]], outcomes: Outcomes) -> List[Dict[str, Any]]:
    """Misses rows for every logged answer that has an independent outcome (or needs a blind label)."""
    out: List[Dict[str, Any]] = []
    gate_by_subject: Dict[str, List[Dict[str, Any]]] = {}
    for row in rows:
        gate_by_subject.setdefault(str(row.get("subject", "")), []).append(row)
    for subject, group in gate_by_subject.items():
        ledger = outcomes.ledger(subject) if subject and not subject.startswith("pr:") else None
        final = (ledger or {}).get("level")
        hint = retro_digest.gate_hint([g for g in group if question_name(g) in ROUTE_QUESTIONS])
        number = subject[3:] if subject.startswith("pr:") else ""
        for row in group:
            name, jev, p = question_name(row), as_bool(row.get("value")), probability(row)
            if name.startswith(BLIND_PREFIXES):
                out.append(make_row(row, None, "needs_blind_label", "unsure_band", "label_only"))
            elif name in ROUTE_QUESTIONS and hint in retro_digest.LEVELS and final in retro_digest.LEVELS:
                kind, suggestion = level_miss(hint, final)
                out.append(make_row(row, final, "ledger_final_level", kind, suggestion))
            elif name == "check.tests":
                record = outcomes.review(subject)
                if record:
                    truth = review_flags_tests(record)
                    out.append(dict(make_row(row, truth, "review_verdict", *classify(jev, truth, p)),
                                    stale_truth=not record_matches(record, row)))
            elif name == "design.user_visible" and number and outcomes.invisible(number) is not None:
                if outcomes.invisible(number):  # no app-UI path and no note: not user-visible, a usable label
                    out.append(make_row(row, False, "release_note_ui_diff", *classify(jev, False, p)))
                else:  # a UI path or a note proves nothing (speed and reliability notes are not visible)
                    out.append(dict(make_row(row, None, "release_note_ui_diff", "unsure_band", "label_only"),
                                    no_truth=True))
            elif name == "code.custom_machinery":
                record = outcomes.review(subject)
                if record and review_flags_machinery(record) and jev is not True:
                    out.append(make_row(row, True, "review_verdict", "false_negative", "add_question"))
    return out


def harvest_row(miss: Dict[str, Any], snippet: str = "") -> Dict[str, Any]:
    """The staged candidate label for one miss row: redacted snippet, deterministic split."""
    return {"id": miss["id"], "question": miss["question"], "subject": redact.redact(str(miss["subject"])),
            "text": redact.redact(snippet), "jev": miss["jev"], "p": miss["p"], "label": miss["truth"],
            "truth_source": miss["truth_source"], "kind": miss["kind"], "split": split_of(miss["id"]),
            "source": "jev_miss harvest, unvetted"}


# MARK: - Output

def append_unique(path: Path, rows: List[Dict[str, Any]]) -> int:
    """Append rows whose ``id`` is not in the file yet; returns how many were written."""
    seen = {r.get("id") for r in read_jsonl(path)} if path.exists() else set()
    fresh = [r for r in rows if r["id"] not in seen]
    if fresh:
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a", encoding="utf-8") as handle:
            for row in fresh:
                handle.write(json.dumps(row, sort_keys=True, default=str) + "\n")
    return len(fresh)


def run(root: Path, task: str = "", since: str = "", use_gh: bool = True,
        runner: Optional[Callable[[List[str]], str]] = None) -> Dict[str, int]:
    """Classify, then write ``misses.jsonl`` and the allowed ``harvest`` files under ``root/build/jev``."""
    home = root / "build" / "jev"
    rows = read_jsonl(home / "gate.jsonl") + read_jsonl(home / "shadow.jsonl")
    if task:
        subjects = {task, *(f"pr:{n}" for n in Outcomes(root, False).pr_numbers(task))}
        rows = [r for r in rows if r.get("subject") in subjects]
    if since:
        cutoff = parse_since(since)
        rows = [r for r in rows if row_time(r) >= cutoff]
    snippets = {row_id(r): state_of(r) for r in rows}
    misses = judge(rows, Outcomes(root, use_gh, runner))
    written = append_unique(home / "misses.jsonl", [dict(m, subject=redact.redact(str(m["subject"]))) for m in misses])
    harvested = 0
    for miss in misses:
        if (miss["truth_source"] in ALLOWED_SOURCES and not miss["question"].startswith(BLIND_PREFIXES)
                and not miss["self_influenced"] and not miss["needs_state"] and not miss["stale_truth"]
                and not miss["no_truth"]):
            harvested += append_unique(home / "harvest" / f"{miss['question']}.jsonl",
                                       [harvest_row(miss, snippets.get(miss["id"], ""))])
    return {"rows": len(rows), "misses": written, "harvested": harvested,
            "needs_blind_label": sum(1 for m in misses if m["truth_source"] == "needs_blind_label")}


def main(argv: Optional[List[str]] = None) -> int:
    """CLI entry; always 0."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--task", default="")
    parser.add_argument("--since", default="")
    parser.add_argument("--root", default=str(ROOT))
    parser.add_argument("--no-gh", action="store_true")
    args = parser.parse_args(argv)
    try:
        counts = run(Path(args.root), args.task, args.since, not args.no_gh)
    except (ValueError, OSError) as exc:
        note(str(exc))
        return 0
    print(json.dumps(counts, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
