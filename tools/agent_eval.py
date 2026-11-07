#!/usr/bin/env python3
"""agent_eval: the eval gate for changes to agents, skills, hooks, Jev questions and the triage runner.

    python3 tools/agent_eval.py [--tier 0|1|2] [--root DIR] [--target DIR] [--changed-questions] [--base REF] [--suite NAME] [-v]

Exit 0 on pass, 1 on a regression, 2 on a usage error; a summary line per suite (``suite NAME: N cases, P passed``).
Standard library only. ``tools/lane_land.py`` runs this file **from the trusted base checkout** with ``--target`` the lane's
clone (a fresh checkout of the lane SHA that has not run the lane's own tests) and also plain in the base, and compares: the
closing ``Ran N tests`` / ``OK`` lines make it count cases (a lane may not run fewer than the base, retired ones included)
and the ``FAIL: id (suite)`` lines are the failing ids (a new one blocks the lane).

**The harness never runs the code under test.** Each case executes the target's code in its own ``python3 -I`` process
(``tools/agent_eval_case.py``, a shim from the trusted checkout that is given only the case's ``kind`` and ``input``) and
prints what it observed as JSON; the comparison with ``expect`` happens in this process. Every case file is read into memory
before the first child starts, children get the case on stdin and run in a temp cwd, so code under test cannot rewrite a later
case. A lane that patches ``compare``, a hook
or the harness changes only its own child's behaviour.

**Ordering rule.** Every trusted read (scripts, cases, probes, held-out items, recorded rows, question contents) happens before
the first lane-code child, and tier 1 (the Jev re-measurement, which runs no lane code, with a fresh empty ``JEV_HOME`` so no
cache answers it) runs before tier 0. Lane code runs as the owner's macOS user, so it can modify files the runner trusts; the
owner accepted this residual on 2026-11-02 (detection over prevention). This ordering reduces exposure; see
``.agents/workflow/eval-gate.md``.

Tiers (``.agents/workflow/eval-gate.md``):

* **Tier 0, every lane, deterministic, no network.** The **routing-replay** set, ``evals/agents/routing-replay/cases/*.json``:
  each case is a recorded incident (``source`` says what happened) with ``input`` and the ``expect``ed outcome of a
  deterministic code path (routing rules, the Jev gate table, the retro digest, the Stop hook, the merge guard, the lane
  landing checks, the review round cap), run against the *current* code. Jev answers are recorded: the real question files
  fold recorded probabilities through a fake transport, so no key is read and nothing is sent. Cases under ``retired/`` still
  run, as a report-only suite (they count in the case total, so retiring one never lowers the count).
* **Tier 1, lanes that change a Jev question** (``--changed-questions``, or ``FENTON_EVAL_BASE`` set by the lander): the
  changed ``contracts/jev/questions/*.json`` (``git diff --name-only BASE...HEAD``). **The lane's wording is measured by
  trusted code:** the lane's question file (``instructions``, ``criteria``, ``type``; ``git show HEAD:path`` in the target,
  parsed as data) is asked about the *base's* held-out ``test`` items by ``tools/agent_eval_measure.py`` (``python3 -I``,
  ``sys.path`` = the trusted tools only, the trusted ``jev_ask``). No lane ``measure.py`` or ``tools/`` file runs, and nothing
  is written to a tracked results file. Pass needs precision at the lane's ``accept.yes_above`` >= its ``target.precision``
  (the lander's threshold check already forbids loosening either) and AUC >= the base's recorded AUC - 0.02. Jev unavailable
  (exit 3) fails closed: no landing without a measurement. An *active* question that cannot be measured (no probe or held-out
  set) fails closed too, unless the lane sets it to ``shadow`` or only tightens its bands.
* **Tier 2, weekly only** (``--tier 2``, run by the Steward's weekly job; the lander never runs it): a budgeted ``claude -p``
  replay (no tools, temp cwd) of the **trusted** ``evals/agents/agent-behaviour/cases`` (only cases with ``"enabled": true``;
  ``config.json`` caps cases and cost). A case a lane added is reported as "lane case not run" and never run.

Case file (``cases/<id>.json``, ``id`` equals the file name): ``{"id", "source", "recorded", "kind", "input", "expect"}``.
``expect`` maps a dotted path of the handler's observed result to a value (equality) or to ``{"has": [...], "lacks": [...],
"eq": v}``. See ``evals/agents/routing-replay/README.md`` for the kinds.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Sequence, Tuple

ROOT = Path(__file__).resolve().parents[1]
#: The one-case child (``python3 -I``): loads the code under test and prints what it observed; never sees ``expect``.
SHIM = Path(__file__).resolve().with_name("agent_eval_case.py")
CASE_TIMEOUT = 120.0
WORKERS = max(1, min(8, (os.cpu_count() or 2)))
SUITE = "routing-replay"
RETIRED_SUITE = "routing-replay-retired"
JEV_SUITE = "jev-measure"
BEHAVIOUR_SUITE = "agent-behaviour"
#: Tier 1: the AUC may fall at most this far below the recorded one.
AUC_SLACK = 0.02
EXIT_UNAVAILABLE = 3

Result = Tuple[bool, List[str]]


# MARK: - Expectations

def dig(observed: Any, path: str) -> Any:
    """``observed`` followed down a dotted ``path`` (dict keys; list indexes); ``None`` when it runs out."""
    value = observed
    for part in path.split("."):
        if isinstance(value, dict):
            value = value.get(part)
        elif isinstance(value, list) and part.isdigit() and int(part) < len(value):
            value = value[int(part)]
        else:
            return None
    return value


def _contains(value: Any, item: Any) -> bool:
    if isinstance(value, str):
        return str(item) in value
    if isinstance(value, (list, tuple, set, dict)):
        return item in value
    return False


def compare(observed: Any, expect: Dict[str, Any]) -> List[str]:
    """Mismatches between the handler's ``observed`` result and a case's ``expect`` (empty = pass)."""
    problems: List[str] = []
    for path, spec in expect.items():
        value = dig(observed, path)
        if isinstance(spec, dict) and spec and set(spec) <= {"has", "lacks", "eq"}:
            for item in spec.get("has", []):
                if not _contains(value, item):
                    problems.append(f"{path}: expected to have {item!r}, got {value!r}")
            for item in spec.get("lacks", []):
                if _contains(value, item):
                    problems.append(f"{path}: expected not to have {item!r}, got {value!r}")
            if "eq" in spec and value != spec["eq"]:
                problems.append(f"{path}: expected {spec['eq']!r}, got {value!r}")
        elif value != spec:
            problems.append(f"{path}: expected {spec!r}, got {value!r}")
    return problems


# MARK: - Tier 0 runner

def load_case(path: Path) -> Tuple[Optional[Dict[str, Any]], str]:
    """The parsed case and an error string ('' when the file is a well-formed case; the kind is checked by the child)."""
    try:
        case = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        return None, f"not valid JSON: {exc}"
    if not isinstance(case, dict):
        return None, "not an object"
    for key in ("id", "source", "kind", "input", "expect"):
        if not case.get(key) and case.get(key) != {}:
            return case, f"missing {key}"
    if case["id"] != path.stem:
        return case, f"id {case['id']!r} must equal the file name {path.stem!r}"
    if not isinstance(case["expect"], dict):
        return case, "expect must be an object"
    return case, ""


def observe(target: Path, case: Dict[str, Any], timeout: float = CASE_TIMEOUT) -> Tuple[Optional[Any], str]:
    """What the code under ``target`` does for ``case``: ``(observed, "")`` or ``(None, error)``. The case runs in its own
    ``python3 -I`` process (the shim, from *this* checkout) and gets only ``kind`` and ``input``; whatever the target's code
    does to its own process, this one only reads the JSON it wrote. The child runs in a temp cwd, is handed the case on stdin
    (never a path to a case file) and ``--target`` / ``--out`` only."""
    with tempfile.TemporaryDirectory(prefix="agent-eval-") as name:
        out = Path(name) / "result.json"
        env = {key: os.environ[key] for key in ("PATH", "LANG", "LC_ALL") if key in os.environ}
        env.update({"PYTHONPATH": str(target), "PYTHONDONTWRITEBYTECODE": "1", "HOME": name})
        try:
            proc = subprocess.run([sys.executable, "-I", str(SHIM), "--target", str(target), "--out", str(out)],
                                  input=json.dumps({"kind": case["kind"], "input": case["input"]}), capture_output=True,
                                  text=True, timeout=timeout, env=env, cwd=name, start_new_session=True)
        except subprocess.TimeoutExpired:
            return None, f"timed out after {timeout:g}s"
        try:
            result = json.loads(out.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            tail = (proc.stderr or proc.stdout or "").strip().splitlines()[-1:] or [""]
            return None, f"the case process left no result (exit {proc.returncode}) {tail[0][:200]}".strip()
    if not isinstance(result, dict) or ("observed" not in result and not isinstance(result.get("error"), str)):
        return None, "the case process left an unreadable result"
    if "observed" not in result:
        return None, result["error"]
    return result["observed"], ""


def run_case(target: Path, path: Path, timeout: float = CASE_TIMEOUT,
             loaded: Optional[Tuple[Optional[Dict[str, Any]], str]] = None) -> Result:
    """Run one case against ``target`` in a child process and compare **here**; ``(passed, problems)``. ``loaded`` is the
    case already read from ``path`` (``run_suite`` reads every file before the first child starts)."""
    case, error = loaded if loaded is not None else load_case(path)
    if error:
        return False, [error]
    observed, error = observe(target, case, timeout)
    if error:
        return False, [error]
    problems = compare(observed, case["expect"])
    return not problems, problems


def case_files(directory: Path) -> List[Path]:
    """Case files in ``directory`` (reason files excluded), sorted."""
    return sorted(p for p in directory.glob("*.json") if not p.name.endswith(".reason.json"))


def load_cases(files: Sequence[Path]) -> List[Tuple[Optional[Dict[str, Any]], str]]:
    """Every case file read into memory (active **and** retired are loaded together, before the first child starts)."""
    return [load_case(path) for path in files]


def run_suite(target: Path, files: Sequence[Path], name: str, report_only: bool = False,
              preloaded: Optional[List[Tuple[Optional[Dict[str, Any]], str]]] = None) -> Dict[str, Any]:
    """Run each case file against ``target``; ``{"name", "cases", "passed", "failures": [(id, problems)]}``."""
    failures: List[Tuple[str, List[str]]] = []
    # Every case file is read into memory before the first child starts: code under test that rewrites a later case
    # file (or the expectations) changes nothing, and the children never get a path to a case file.
    loaded = preloaded if preloaded is not None else load_cases(files)
    with ThreadPoolExecutor(max_workers=WORKERS) as pool:  # each case is its own child process; results keep file order
        results = list(pool.map(lambda item: run_case(target, item[0], loaded=item[1]), zip(files, loaded)))
    for path, (ok, problems) in zip(files, results):
        if not ok:
            failures.append((path.stem, problems))
    return {"name": name, "cases": len(files), "passed": len(files) - len(failures), "failures": failures,
            "report_only": report_only}


def tier0_sets(root: Path, target: Path) -> Tuple[List[Path], List[Path]]:
    """``(active case files, retired case files)``. The trusted ``root`` decides: its cases run (its copy, never the target's).
    A case the target moved into its ``retired/`` runs as report only; a case only the target has (a lane may add cases) runs
    from the target's folder. Nothing is dropped: the total never falls below the trusted one."""
    mine = root / "evals" / "agents" / "routing-replay"
    theirs = target / "evals" / "agents" / "routing-replay"
    own_active, own_retired = case_files(mine / "cases"), case_files(mine / "retired")
    if theirs.resolve() == mine.resolve():
        return own_active, own_retired
    their_active, their_retired = case_files(theirs / "cases"), case_files(theirs / "retired")
    retired_names = {p.name for p in their_retired}
    known = {p.name for p in own_active} | {p.name for p in own_retired}
    active = [p for p in own_active if p.name not in retired_names]
    active += [p for p in their_active if p.name not in known]
    retired = own_retired + [p for p in own_active if p.name in retired_names]
    retired += [p for p in their_retired if p.name not in known]
    return sorted(active), sorted(retired)


# MARK: - Tier 1: Jev question re-measurement

def changed_questions(root: Path, base: str, head: str = "HEAD") -> List[str]:
    """Question ids whose file changed in ``git diff --name-only BASE...HEAD`` (deleted files are not measured). Pass explicit
    SHAs: ``head`` is read once, before any code of the lane runs.

    Raises:
        RuntimeError: git could not produce the diff (fail closed: an unreadable base is not "nothing changed")."""
    proc = subprocess.run(["git", "-C", str(root), "diff", "--name-only", "--diff-filter=d", f"{base}...{head}", "--",
                           "contracts/jev/questions/"], capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(f"git diff {base}...{head} failed: {proc.stderr.strip()[:200]}")
    ids = [Path(line.strip()).stem for line in proc.stdout.splitlines() if line.strip().endswith(".json")]
    return sorted(set(ids))


def resolve_sha(repo: Path, ref: str) -> str:
    """The commit SHA ``ref`` names in ``repo``, or ``""`` when it names none."""
    if not ref:
        return ""
    proc = subprocess.run(["git", "-C", str(repo), "rev-parse", "--verify", "-q", f"{ref}^{{commit}}"],
                          capture_output=True, text=True)
    return proc.stdout.strip() if proc.returncode == 0 else ""


def question_name_problem(qid: str, question: Any) -> str:
    """A reason a changed question cannot be measured because its ``id`` is not its file name stem, else ``""``."""
    if isinstance(question, dict) and question.get("id") != qid:
        return f"the question id {question.get('id')!r} is not its file name {qid!r}"
    return ""


def auc(pairs: Sequence[Tuple[float, bool]]) -> float:
    """Area under the ROC curve from ``(score, is_positive)`` pairs; NaN with one class."""
    pos = [s for s, y in pairs if y]
    neg = [s for s, y in pairs if not y]
    if not pos or not neg:
        return float("nan")
    return sum((p > n) + 0.5 * (p == n) for p in pos for n in neg) / (len(pos) * len(neg))


def read_rows(path: Path) -> List[Dict[str, Any]]:
    try:
        return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    except (OSError, ValueError):
        return []


def score_rows(rows: Sequence[Dict[str, Any]], threshold: Optional[float]) -> Tuple[float, Optional[float], int]:
    """``(auc, precision at threshold or None when nothing is flagged, flagged)`` for measure result rows."""
    p = [float((r.get("probabilities") or {}).get("true", 0.0)) for r in rows]
    y = [bool(r.get("label")) for r in rows]
    precision, flagged = None, 0
    if threshold is not None:
        tp = sum(pi >= threshold and yi for pi, yi in zip(p, y))
        flagged = sum(pi >= threshold for pi in p)
        precision = tp / flagged if flagged else None
    return auc(list(zip(p, y))), precision, flagged


def probe_id(root: Path, question: Dict[str, Any]) -> Optional[Tuple[str, str]]:
    """``(measure id, labels path)`` for a question that has a probe or candidate with a label set, else ``None``.
    The probe for the question's version (``<id>.v<version>``) wins, then the plain id, then the newest ``<id>.vN``."""
    derived = root / "contracts" / "jev" / "derived"
    defs: Dict[str, Dict[str, Any]] = {}
    for file, key in (("candidates.json", "candidates"), ("probes.json", "probes")):
        try:
            for item in json.loads((derived / file).read_text(encoding="utf-8"))[key]:
                defs[item["id"]] = item
        except (OSError, ValueError, KeyError, TypeError):
            continue
    latest = sorted((k for k in defs if re.fullmatch(re.escape(question["id"]) + r"\.v\d+", k)),
                    key=lambda k: int(k.rsplit(".v", 1)[1]), reverse=True)
    for candidate in (f"{question['id']}.v{question.get('version')}", question["id"], *latest):
        if candidate in defs and defs[candidate].get("labels"):
            return candidate, str(defs[candidate]["labels"])
    return None


MEASURE_SHIM = Path(__file__).resolve().with_name("agent_eval_measure.py")
MEASURE_TIMEOUT = 1800.0


def api_question(question: Dict[str, Any]) -> Dict[str, Any]:
    """The Jev API question for a question file or probe definition: ``type``, ``instructions`` and the ``options`` /
    ``criteria`` (the same shape ``contracts/jev/derived/measure.py`` builds)."""
    out = {"type": question["type"], "instructions": question["instructions"]}
    criteria = question.get("options") or question.get("criteria")
    if criteria is not None:
        out["criteria"] = criteria
    return out


def default_measure(trusted: Path, spec: Dict[str, Any], items: Sequence[Dict[str, Any]]) -> Tuple[int, List[Dict[str, Any]]]:
    """Ask Jev ``spec["question"]`` (the lane's wording, as data) about each held-out ``items`` entry, with the **trusted**
    checkout's ``jev_ask`` in a ``python3 -I`` child whose ``sys.path`` holds only the trusted tools (``agent_eval_measure.py``).
    No code of the lane runs and no tracked results file is written (the rows go to a temp dir). ``(exit code, rows)``;
    exit 3 means Jev is unavailable. Spends Jev calls."""
    with tempfile.TemporaryDirectory(prefix="agent-eval-measure-") as name:
        out = Path(name) / "rows.jsonl"
        env = {key: value for key, value in os.environ.items() if not key.startswith("PYTHON")}
        # A fresh, empty JEV_HOME: no cached answer (planted or stale) can stand in for a measurement.
        jev_home = Path(name) / "jev-home"
        jev_home.mkdir()
        env.update({"PYTHONDONTWRITEBYTECODE": "1", "JEV_HOME": str(jev_home)})
        request = {"question": spec["question"], "field": spec["field"], "tag": "derive." + spec["id"],
                   "items": [{"id": it["id"], "text": it["text"], "label": it["label"]} for it in items]}
        try:
            proc = subprocess.run([sys.executable, "-I", str(MEASURE_SHIM), "--trusted", str(trusted), "--out", str(out)],
                                  input=json.dumps(request), capture_output=True, text=True, timeout=MEASURE_TIMEOUT,
                                  env=env, cwd=name, start_new_session=True)
        except subprocess.TimeoutExpired:
            return 1, []
        return proc.returncode, (read_rows(out) if proc.returncode == 0 else [])


THRESHOLD_KEYS = (("accept.yes_above", "up"), ("accept.min_confidence", "up"), ("target.precision", "up"),
                  ("accept.no_below", "down"))


def _dotted(doc: Any, dotted: str) -> Any:
    for part in dotted.split("."):
        doc = doc.get(part) if isinstance(doc, dict) else None
    return doc


def _without(doc: Dict[str, Any], dotted: Sequence[str]) -> Dict[str, Any]:
    """A deep copy of ``doc`` without the dotted keys (and without ``mode``)."""
    out = json.loads(json.dumps(doc))
    out.pop("mode", None)
    for key in dotted:
        parts = key.split(".")
        node = out
        for part in parts[:-1]:
            node = node.get(part) if isinstance(node, dict) else None
        if isinstance(node, dict):
            node.pop(parts[-1], None)
    return out


def only_tightens(old: Dict[str, Any], new: Dict[str, Any]) -> bool:
    """Does ``new`` differ from ``old`` only by thresholds that got stricter and/or ``mode`` going ``active`` to ``shadow``?
    Such a change cannot let a worse answer through, so it needs no measurement."""
    if _without(old, [k for k, _ in THRESHOLD_KEYS]) != _without(new, [k for k, _ in THRESHOLD_KEYS]):
        return False
    for key, direction in THRESHOLD_KEYS:
        before, after = _dotted(old, key), _dotted(new, key)
        if before == after:
            continue
        if not isinstance(before, (int, float)) or not isinstance(after, (int, float)) or isinstance(before, bool) \
                or isinstance(after, bool) or (after < before if direction == "up" else after > before):
            return False
    return old.get("mode") == new.get("mode") or (old.get("mode") == "active" and new.get("mode") == "shadow")


def question_at(root: Path, base: str, qid: str) -> Optional[Dict[str, Any]]:
    """The question file as it was at ``base`` (``git show``; a ref or a SHA), or ``None`` when it did not exist or cannot be
    read. Parsed as data."""
    if not base:
        return None
    proc = subprocess.run(["git", "-C", str(root), "show", f"{base}:contracts/jev/questions/{qid}.json"],
                          capture_output=True, text=True)
    try:
        doc = json.loads(proc.stdout) if proc.returncode == 0 else None
    except ValueError:
        return None
    return doc if isinstance(doc, dict) else None


def prepare_tier1(trusted: Path, target: Path, base: str, head: str, ids: Optional[Sequence[str]] = None) -> Dict[str, Any]:
    """Everything tier 1 needs, read into memory **before any code of the lane runs**: the SHAs (``base`` and ``head`` resolved
    once, explicitly), the changed question ids (``git diff base_sha...head_sha``), each lane question (``git show
    head_sha:path``, parsed as data), the base's version of it, the trusted probe, held-out items, state field and recorded rows.
    Tier 1 then uses only this dictionary: resetting the target's ``HEAD`` or editing the trusted files later changes nothing.

    Raises:
        RuntimeError: the diff cannot be produced."""
    base_sha = resolve_sha(target, base) or base
    head_sha = (resolve_sha(target, head) or head) if head else ""
    if ids is None:
        ids = changed_questions(target, base_sha, head_sha or "HEAD")
    derived = trusted / "contracts" / "jev" / "derived"
    entries: Dict[str, Dict[str, Any]] = {}
    for qid in ids:
        entry: Dict[str, Any] = {"question": None, "old": None, "found": None, "held_out": [], "field": None,
                                 "recorded": [], "problem": ""}
        entries[qid] = entry
        if head_sha:
            question = question_at(target, head_sha, qid)
        else:
            try:
                question = json.loads((target / "contracts" / "jev" / "questions" / f"{qid}.json").read_text(encoding="utf-8"))
            except (OSError, ValueError):
                question = None
        entry["question"] = question if isinstance(question, dict) else None
        if entry["question"] is None:
            continue
        entry["problem"] = question_name_problem(qid, question)
        if entry["problem"]:
            continue
        entry["old"] = question_at(target, base_sha, qid)
        found = probe_id(trusted, question)
        entry["found"] = found
        if not found:
            continue
        measure_id, labels = found
        entry["held_out"] = [r for r in read_rows(derived / labels) if r.get("split") == "test"]
        for file, key in (("candidates.json", "candidates"), ("probes.json", "probes")):
            try:
                for item in json.loads((derived / file).read_text(encoding="utf-8"))[key]:
                    if item.get("id") == measure_id and item.get("state_fields"):
                        entry["field"] = str(item["state_fields"][0])
            except (OSError, ValueError, KeyError, TypeError):
                continue
        entry["recorded"] = read_rows(derived / "results" / f"{measure_id}.test.jsonl")
    return {"base": base_sha, "head": head_sha, "ids": list(ids), "entries": entries}


def run_jev_suite(trusted: Path, ids: Sequence[str], measure: Callable[[Path, Dict[str, Any], Sequence[Dict[str, Any]]],
                  Tuple[int, List[Dict[str, Any]]]] = default_measure, base: str = "", target: Optional[Path] = None,
                  head: str = "", prepared: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    """Tier 1 for the changed question ``ids``: the **lane's question** (its ``instructions``, ``criteria`` and ``type``, read
    with ``git show <head sha>:path`` in ``target`` when ``head`` is given and parsed as data) is asked about the **base's**
    held-out items by **trusted** code (``measure(trusted, spec, items)``, injectable; see :func:`default_measure`). The probe,
    labels, splits and recorded results are the trusted checkout's. No code of the lane runs here.

    All inputs come from ``prepared`` (:func:`prepare_tier1`, built before tier 0 starts; built here when not given).

    **An active question that cannot be measured** (no probe or label set, not a single yes/no question, no held-out items)
    **fails**, unless the change moves it to ``shadow`` or only tightens its bands (checked against ``base``); a question that
    is already ``shadow`` is noted. A question whose ``id`` is not its file name fails. Jev unavailable fails."""
    if prepared is None:
        prepared = prepare_tier1(trusted, target or trusted, base, head, ids)
    failures: List[Tuple[str, List[str]]] = []
    notes: List[str] = []
    cases = 0

    def unmeasurable(qid: str, entry: Dict[str, Any], why: str) -> None:
        nonlocal cases
        question = entry["question"]
        if question.get("mode", "active") == "shadow":
            notes.append(f"{qid}: {why}, not measured (shadow)")
            return
        old = entry["old"]
        if old is not None and only_tightens(old, question):
            notes.append(f"{qid}: {why}, not measured (only tightens its bands)")
            return
        cases += 1
        failures.append((f"tier1:{qid}", [f"{why}: an active question that cannot be measured cannot change; set it to shadow "
                                          "(or add a held-out set to measure it)"]))

    for qid in prepared["ids"]:
        entry = prepared["entries"][qid]
        question = entry["question"]
        if not isinstance(question, dict):
            failures.append((f"tier1:{qid}", ["the question file is unreadable"]))
            cases += 1
            continue
        if entry["problem"]:
            failures.append((f"tier1:{qid}", [entry["problem"]]))
            cases += 1
            continue
        if not entry["found"]:
            unmeasurable(qid, entry, "no probe or label set")
            continue
        measure_id = entry["found"][0]
        held_out = entry["held_out"]
        if question.get("type") != "noul" or not held_out:
            unmeasurable(qid, entry, "not a single yes/no question" if question.get("type") != "noul"
                         else "no held-out items")
            continue
        field = entry["field"]
        cases += 1
        if not field or not isinstance(question.get("instructions"), str):
            failures.append((f"tier1:{qid}", ["the question has no instructions, or its probe has no state field: cannot measure it"]))
            continue
        recorded = entry["recorded"]
        recorded_auc = score_rows(recorded, None)[0] if recorded else float("nan")
        spec = {"id": measure_id, "question": api_question(question), "field": field}
        code, rows = measure(trusted, spec, held_out)
        if code == EXIT_UNAVAILABLE:
            failures.append((f"tier1:{qid}", ["Jev is unavailable: a changed question cannot land without a measurement"]))
            continue
        if code != 0 or not rows:
            failures.append((f"tier1:{qid}", [f"measuring {measure_id} on the held-out split failed (exit {code})"]))
            continue
        accept, goal = question.get("accept") or {}, question.get("target") or {}
        got_auc, precision, flagged = score_rows(rows, accept.get("yes_above"))
        problems = []
        want = goal.get("precision")
        if want is not None and accept.get("yes_above") is not None and precision is not None and precision < want:
            problems.append(f"precision at {accept['yes_above']} is {precision:.3f} ({flagged} flagged), below the target {want}")
        if not math.isnan(recorded_auc) and (math.isnan(got_auc) or got_auc < recorded_auc - AUC_SLACK):
            problems.append(f"AUC {got_auc:.3f} is more than {AUC_SLACK} below the recorded {recorded_auc:.3f}")
        if problems:
            failures.append((f"tier1:{qid}", problems))
    return {"name": JEV_SUITE, "cases": cases, "passed": cases - len(failures), "failures": failures,
            "report_only": False, "notes": notes}


# MARK: - Tier 2: budgeted LLM replay (weekly)

def default_claude(prompt: str, model: str, timeout: float) -> Dict[str, Any]:
    """One ``claude -p`` call, JSON output, **no tools** (``--tools ""``) and a temp cwd (no project settings or files to read);
    ``{"result": text, "total_cost_usd": n}`` (cost 0 and text '' on failure)."""
    with tempfile.TemporaryDirectory(prefix="agent-eval-claude-") as cwd:
        try:
            proc = subprocess.run(["claude", "-p", prompt, "--model", model, "--output-format", "json", "--tools", "",
                                   "--strict-mcp-config"], capture_output=True, text=True, timeout=timeout, cwd=cwd)
        except subprocess.TimeoutExpired:
            return {"result": "", "total_cost_usd": 0.0, "error": f"timed out after {timeout:g}s"}
    try:
        data = json.loads(proc.stdout)
    except ValueError:
        return {"result": "", "total_cost_usd": 0.0, "error": proc.stderr.strip()[:200] or f"exit {proc.returncode}"}
    return data if isinstance(data, dict) else {"result": "", "total_cost_usd": 0.0}


def run_behaviour_suite(root: Path, claude: Callable[[str, str, float], Dict[str, Any]] = default_claude,
                        target: Optional[Path] = None) -> Dict[str, Any]:
    """Tier 2: enabled cases of the **trusted** ``root``'s ``evals/agents/agent-behaviour/cases`` through ``claude -p``, capped
    by ``config.json`` (``max_cases``, ``max_cost_usd``, ``model``, ``timeout_s``). **Only trusted cases run:** a case file
    that exists only in ``target`` (a lane added it) is reported ("lane case not run") and never sent to ``claude``. Disabled
    cases never run, so the suite costs nothing until the owner switches a case on. Every case file is read before the first
    call. Each case: ``{"id", "prompt", "expect": {"contains": [...], "not_contains": [...]}}``."""
    base = root / "evals" / "agents" / "agent-behaviour"
    try:
        config = json.loads((base / "config.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        config = {}
    max_cases = int(config.get("max_cases", 3))
    max_cost = float(config.get("max_cost_usd", 0.5))
    model = str(config.get("model", "sonnet"))
    timeout = float(config.get("timeout_s", 180))
    failures: List[Tuple[str, List[str]]] = []
    notes: List[str] = []
    ran, spent = 0, 0.0
    trusted_files = case_files(base / "cases")
    loaded: List[Tuple[Path, Optional[Dict[str, Any]]]] = []
    for path in trusted_files:
        try:
            loaded.append((path, json.loads(path.read_text(encoding="utf-8"))))
        except (OSError, ValueError):
            loaded.append((path, None))
    if target is not None and target.resolve() != root.resolve():
        known = {p.name for p in trusted_files}
        for path in case_files(target / "evals" / "agents" / "agent-behaviour" / "cases"):
            if path.name not in known:
                notes.append(f"{path.stem}: lane case not run: tier 2 runs trusted cases only")
    for path, case in loaded:
        if not isinstance(case, dict):
            failures.append((path.stem, ["not valid JSON"]))
            ran += 1
            continue
        if not case.get("enabled", False):
            continue
        if ran >= max_cases or spent >= max_cost:
            notes.append(f"{path.stem}: skipped (budget: {ran}/{max_cases} cases, ${spent:.2f}/${max_cost:.2f})")
            continue
        ran += 1
        reply = claude(str(case.get("prompt", "")), model, timeout)
        spent += float(reply.get("total_cost_usd") or 0.0)
        text = str(reply.get("result") or "")
        expect = case.get("expect") or {}
        problems = [f"missing {s!r}" for s in expect.get("contains", []) if not re.search(s, text)]
        problems += [f"must not match {s!r}" for s in expect.get("not_contains", []) if re.search(s, text)]
        if not text:
            problems.append(f"no answer ({reply.get('error', 'empty')})")
        if problems:
            failures.append((path.stem, problems))
    notes.append(f"spent ${spent:.2f} of ${max_cost:.2f}")
    return {"name": BEHAVIOUR_SUITE, "cases": ran, "passed": ran - len(failures), "failures": failures,
            "report_only": False, "notes": notes}


# MARK: - Driver

def summary_line(suite: Dict[str, Any]) -> str:
    tag = " (report only)" if suite.get("report_only") else ""
    return f"suite {suite['name']}{tag}: {suite['cases']} cases, {suite['passed']} passed"


def evaluate(root: Path, *, tier: Optional[int] = None, base: str = "", changed: bool = False, only: str = "",
             measure: Callable[[Path, Dict[str, Any], Sequence[Dict[str, Any]]], Tuple[int, List[Dict[str, Any]]]]
             = default_measure,
             claude: Callable[[str, str, float], Dict[str, Any]] = default_claude,
             target: Optional[Path] = None, target_sha: str = "") -> List[Dict[str, Any]]:
    """The suites for the requested tiers (tier ``None`` is 0, plus 1 when ``changed`` or a ``base`` is given).

    ``root`` is the trusted checkout (this file, the cases, the shim); ``target`` (default ``root``) is the code under test,
    which runs only in the shim's child processes. Tier 1 measures the target's questions.

    Every input of every tier is read into memory **before the first child starts** (the case files, active and retired; the
    lane SHA, the changed questions and their content, the trusted held-out items and recorded results). ``target_sha`` is the
    reviewed lane commit (``lane_land`` passes it); without it the target's ``HEAD`` is resolved once, here."""
    target = (target or root).resolve()
    suites: List[Dict[str, Any]] = []
    if tier == 2:
        return [run_behaviour_suite(root, claude, target)]
    prepared = None
    if tier == 1 or (tier is None and (changed or base)):
        if not base:
            raise ValueError("tier 1 needs a base: --base REF or FENTON_EVAL_BASE")
        has_git = (target / ".git").exists()
        prepared = prepare_tier1(root, target, base, (target_sha or "HEAD") if has_git else "")
    # Ordering rule: tier 1 runs first. It runs no lane code, and nothing trusted (the measure script, jev_ask, the cases) has
    # been exposed to lane code yet; tier 0 children then run the lane's code against inputs already in memory.
    jev_suite = None
    if prepared is not None:
        jev_suite = run_jev_suite(root, prepared["ids"], measure, prepared=prepared)
        jev_suite["notes"].insert(0, f"changed questions: {', '.join(prepared['ids']) or 'none'}")
    if tier in (None, 0):
        active, retired = tier0_sets(root, target)
        loaded_active, loaded_retired = load_cases(active), load_cases(retired)
        suites.append(run_suite(target, active, SUITE, preloaded=loaded_active))
        suites.append(run_suite(target, retired, RETIRED_SUITE, report_only=True, preloaded=loaded_retired))
    if jev_suite is not None:
        suites.append(jev_suite)
    if only:
        suites = [s for s in suites if s["name"] == only]
    return suites


def report(suites: Sequence[Dict[str, Any]], elapsed: float, verbose: bool = False, out=None) -> int:
    """Print the summary lines, failures and the unittest-shaped closing lines ``lane_land`` counts; the exit code."""
    out = out or sys.stdout
    failing = 0
    total = sum(s["cases"] for s in suites if s["name"] in (SUITE, RETIRED_SUITE))
    for suite in suites:
        print(summary_line(suite), file=out)
        for note in suite.get("notes", []):
            print(f"  note: {note}", file=out)
        for case_id, problems in suite["failures"]:
            if suite.get("report_only"):
                print(f"  retired case {case_id} no longer passes (report only): " + "; ".join(problems), file=out)
                continue
            failing += 1
            print(f"FAIL: {case_id} ({suite['name']})", file=out)
            for problem in problems:
                print(f"    {problem}", file=out)
    print(f"\nRan {total} tests in {elapsed:.3f}s\n", file=out)
    print("OK" if not failing else f"FAILED (failures={failing})", file=out)
    return 0 if not failing else 1


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="The agent eval gate (routing replay, Jev re-measurement, weekly replay).")
    parser.add_argument("--tier", type=int, choices=(0, 1, 2), help="only this tier (default: 0, plus 1 when a base is known)")
    parser.add_argument("--root", default=str(ROOT), help="the trusted checkout: the cases, the shim, tier 2 (default: this one)")
    parser.add_argument("--target", default="", help="the checkout under test (default: --root); its code runs only in child processes")
    parser.add_argument("--changed-questions", action="store_true", help="also re-measure Jev questions changed since the base")
    parser.add_argument("--base", default=os.environ.get("FENTON_EVAL_BASE", ""),
                        help="diff base for tier 1 (default $FENTON_EVAL_BASE, set by lane_land)")
    parser.add_argument("--target-sha", default=os.environ.get("FENTON_EVAL_HEAD", ""),
                        help="the reviewed lane commit tier 1 reads (default $FENTON_EVAL_HEAD, set by lane_land; else the target's HEAD, read once)")
    parser.add_argument("--suite", default="", help="print only this suite")
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args(argv)
    started = time.monotonic()
    try:
        suites = evaluate(Path(args.root).resolve(), tier=args.tier, base=args.base, changed=args.changed_questions,
                          only=args.suite, target=Path(args.target) if args.target else None,
                          target_sha=args.target_sha)
    except (ValueError, RuntimeError) as exc:
        print(f"agent_eval: {exc}", file=sys.stderr)
        return 2
    return report(suites, time.monotonic() - started, args.verbose)


if __name__ == "__main__":
    sys.exit(main())
