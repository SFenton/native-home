#!/usr/bin/env python3
"""agent_eval_case: runs ONE routing-replay case against the code under test, in its own process.

    python3 -I tools/agent_eval_case.py --target DIR --out FILE < {"kind": ..., "input": {...}}

``tools/agent_eval.py`` (the trusted parent, run from the trusted base checkout) starts this once per case with
``--target`` the checkout under test (the lane). The shim loads the target's modules (so a lane's code runs here, never in the
parent), runs the handler of the case's ``kind`` and writes ``{"observed": {...}}`` (or ``{"error": "..."}``) to ``--out``. It
is given only the case's ``kind`` and ``input``, never ``expect``; **the comparison with the expected value happens in the
parent**, so code under test cannot patch the comparison or the harness. Run with ``-I`` (no environment, no user site, no cwd
on ``sys.path``); the target is put on ``sys.path`` explicitly, as ``PYTHONPATH`` would be.

This file is in the fixed set (``tools/agent_eval*.py``). Handler kinds are documented in ``evals/agents/routing-replay/README.md``.
"""

from __future__ import annotations

import argparse
import contextlib
import importlib.util
import io
import json
import os
import sys
import tempfile
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional
from unittest import mock

# MARK: - Context: module loading, recorded Jev, fixtures

class Ctx:
    """Loads the code under test from ``root`` (once per run) and builds fixtures; closed after the run."""

    def __init__(self, root: Path):
        self.root = root
        self._modules: Dict[str, Any] = {}
        self._paths: List[str] = []

    def load(self, rel: str) -> Any:
        """The module at ``root/rel``, imported once under its file stem."""
        if rel in self._modules:
            return self._modules[rel]
        path = self.root / rel
        for entry in (str(path.parent), str(self.root / "tools")):
            if entry not in sys.path:
                sys.path.insert(0, entry)
                self._paths.append(entry)
        name = path.stem
        spec = importlib.util.spec_from_file_location(name, path)
        module = importlib.util.module_from_spec(spec)
        sys.modules[name] = module
        spec.loader.exec_module(module)
        self._modules[rel] = module
        return module

    def close(self) -> None:
        for entry in self._paths:
            with contextlib.suppress(ValueError):
                sys.path.remove(entry)


@contextlib.contextmanager
def isolated(tmp: Path, extra_env: Optional[Dict[str, str]] = None):
    """A case's world: a private ``JEV_HOME``, no Jev key anywhere, not headless, and ``sys.modules`` put back afterwards."""
    snapshot = dict(sys.modules)
    env = {"JEV_HOME": str(tmp / "jev"), "JEV_KEY_FILE": str(tmp / "no-key"), "BG_RUNS_DIR": str(tmp / "runs"),
           **(extra_env or {})}
    with mock.patch.dict(os.environ, env):
        for name in ("TYPESAFE_API_KEY", "FENTON_HEADLESS", "FENTON_EVAL_BASE"):
            os.environ.pop(name, None)
        try:
            yield
        finally:
            for name in list(sys.modules):
                if name not in snapshot:
                    del sys.modules[name]
                elif sys.modules[name] is not snapshot[name]:
                    sys.modules[name] = snapshot[name]


def recorded_transport(recorded: Dict[str, Any]) -> Callable[[dict, str, float], dict]:
    """A ``jev_ask`` transport that answers from recorded probabilities.

    ``recorded`` maps a question id to P(yes) (a noul), to ``{option: P(yes)}`` (a noul-set) and ``"id__companion"`` to a
    companion's P(yes). Anything not recorded is 0.5 (the unsure band)."""
    by_prefix = {key.replace(".", "_"): value for key, value in recorded.items()}

    def transport(body: dict, _key: str, _timeout: float) -> dict:
        answers = {}
        for name in body["questions"]:
            prefix, _, option = name.partition(":")
            value = by_prefix.get(prefix)
            if option and isinstance(value, dict):
                value = value.get(option)
            elif "__" in name:
                value = by_prefix.get(name)
            if not isinstance(value, (int, float)) or isinstance(value, bool):
                value = 0.5
            answers[name] = {"type": "noul", "noul": float(value)}
        return {"answers": answers, "model": "recorded", "usage": {"input_tokens": 0}}

    return transport


@contextlib.contextmanager
def recorded_jev(jev_module: Any, recorded: Dict[str, Any]):
    """``jev_module`` (a loaded ``jev_ask``) answers from ``recorded``; the real banding and folding still run."""
    with mock.patch.object(jev_module, "api_key", lambda: "recorded"), \
            mock.patch.object(jev_module, "_post", recorded_transport(recorded)):
        yield


def write_files(base: Path, files: Dict[str, Any]) -> None:
    """Fixture files under ``base``. A string is written as is; a list is joined into lines (dicts as JSON); a dict is JSON;
    ``{"$repeat": {"line": s, "n": N}}`` is ``s`` N times (a long log)."""
    for rel, content in files.items():
        path = base / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        if isinstance(content, dict) and "$repeat" in content:
            text = (content["$repeat"]["line"] + "\n") * int(content["$repeat"]["n"])
        elif isinstance(content, list):
            text = "\n".join(c if isinstance(c, str) else json.dumps(c) for c in content) + "\n"
        elif isinstance(content, (dict, int, float, bool)):
            text = json.dumps(content)
        else:
            text = str(content)
        path.write_text(text, encoding="utf-8")


# MARK: - Handlers (one per case kind; each returns the observed dict)

Handler = Callable[[Ctx, Dict[str, Any], Path], Dict[str, Any]]
HANDLERS: Dict[str, Handler] = {}


def handler(kind: str) -> Callable[[Handler], Handler]:
    def register(fn: Handler) -> Handler:
        HANDLERS[kind] = fn
        return fn
    return register


@handler("route")
def _route(ctx: Ctx, data: Dict[str, Any], tmp: Path) -> Dict[str, Any]:
    """``route_rule`` / ``ledger_level`` and, with ``jev`` (recorded probabilities), ``jev_level_raise``."""
    ht = ctx.load("tools/triage/hass_triage.py")
    issue = {"number": 1, "title": data.get("title", ""), "body": data.get("body", ""),
             "labels": [{"name": name} for name in data.get("labels", [])]}
    nightly = bool(data.get("nightly"))
    observed: Dict[str, Any] = {"route": ht.route_rule(issue, nightly), "level": ht.ledger_level(issue, nightly)}
    if "jev" in data:
        with recorded_jev(ht._hints_module().jev, data["jev"]):
            raised = ht.jev_level_raise(data.get("cfg", {}), issue["title"], issue["body"], subject="eval")
        observed["raise"] = raised[0] if raised else None
        observed["raise_p"] = round(raised[1], 2) if raised else None
        observed["final"] = max(observed["level"], raised[0]) if raised else observed["level"]
    return observed


@handler("gate_route")
def _gate_route(ctx: Ctx, data: Dict[str, Any], tmp: Path) -> Dict[str, Any]:
    """``jev_gate.route_hint`` from recorded (visible, chosen, pick) verdicts."""
    gate = ctx.load("tools/jev_gate.py")
    return {"route": gate.route_hint(data.get("visible"), data.get("chosen"), data.get("pick"))}


@handler("gate_hints")
def _gate_hints(ctx: Ctx, data: Dict[str, Any], tmp: Path) -> Dict[str, Any]:
    """The full ``jev_gate.hints`` lines for a plan whose Jev answers are recorded."""
    gate = ctx.load("tools/jev_gate.py")
    with recorded_jev(gate.jev, data["jev"]):
        lines = gate.hints(data.get("plan", "a plan"), data.get("title", ""), "eval")
    return {"lines": lines, "text": "\n".join(lines)}


@handler("gate_cli")
def _gate_cli(ctx: Ctx, data: Dict[str, Any], tmp: Path) -> Dict[str, Any]:
    """``jev_gate.py --plan-file`` on a missing or empty plan: exit code and stderr (no Jev is reachable)."""
    gate = ctx.load("tools/jev_gate.py")
    plan = tmp / "plan.md"
    if data.get("plan") is not None:
        plan.write_text(data["plan"], encoding="utf-8")
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err), \
            mock.patch.object(gate.jev, "api_key", lambda: ""):
        code = gate.main(["--plan-file", str(plan)])
    return {"exit": code, "stdout": out.getvalue(), "stderr": err.getvalue()}


@handler("brief")
def _brief(ctx: Ctx, data: Dict[str, Any], tmp: Path) -> Dict[str, Any]:
    """``brief.complete`` on a brief with recorded per-part probabilities: which parts are present, unsure, missing."""
    jev_ask = ctx.load("tools/jev_ask.py")
    question = jev_ask.load_questions(ctx.root / "contracts" / "jev" / "questions")["brief.complete"]
    with recorded_jev(jev_ask, {"brief.complete": data["jev"]}):
        decision = jev_ask.ask_question(question, {"brief": data.get("brief", "")}, subject="eval")
    options = list(question.data["criteria"])
    present, unsure = list(decision.value), list(decision.unsure)
    return {"present": present, "unsure": unsure, "missing": [o for o in options if o not in present]}


@handler("digest")
def _digest(ctx: Ctx, data: Dict[str, Any], tmp: Path) -> Dict[str, Any]:
    """``retro_digest.py`` on fixture files under a worktree dir (``{dir}`` in ``args`` is that dir)."""
    rd = ctx.load("tools/retro_digest.py")
    work = tmp / "wt"
    write_files(work, data.get("files", {}))
    args = [a.replace("{dir}", str(work)) for a in data.get("args", [])]
    task = data.get("task", "EVAL-1")
    with contextlib.redirect_stdout(io.StringIO()):
        code = rd.main(["--task", task, "--worktree", str(work), *args])
    document = json.loads((work / "build" / "retro" / f"{task}.json").read_text(encoding="utf-8"))
    return {"exit": code, "triggers": [t["id"] for t in document["triggers"]],
            "evidence": {t["id"]: " | ".join(t["evidence"]) for t in document["triggers"]},
            "counts": document["counts"], "durations": document["durations"]}


@handler("stop_hook")
def _stop_hook(ctx: Ctx, data: Dict[str, Any], tmp: Path) -> Dict[str, Any]:
    """``stop_continue_guard.py`` ``main`` on a fixture transcript (``headless`` sets ``FENTON_HEADLESS=1``)."""
    guard = ctx.load("tools/hooks/stop_continue_guard.py")
    runs = tmp / "runs"
    runs.mkdir(parents=True, exist_ok=True)
    transcript = tmp / "transcript.jsonl"
    transcript.write_text("".join(json.dumps(item) + "\n" for item in data.get("items", [])), encoding="utf-8")
    event = {"transcript_path": str(transcript), **data.get("event", {})}
    out = io.StringIO()
    env = {"FENTON_HEADLESS": "1"} if data.get("headless", True) else {}
    with mock.patch.dict(os.environ, env), mock.patch("sys.stdin", io.StringIO(json.dumps(event))), \
            contextlib.redirect_stdout(out):
        code = guard.main()
    printed = out.getvalue().strip()
    decision = json.loads(printed) if printed else {}
    return {"exit": code, "blocked": decision.get("decision") == "block", "reason": decision.get("reason", "")}


@handler("merge_guard")
def _merge_guard(ctx: Ctx, data: Dict[str, Any], tmp: Path) -> Dict[str, Any]:
    """``merge_guard.reason(command)``: ``blocked`` and the matched reason."""
    guard = ctx.load("tools/hooks/merge_guard.py")
    env = {"FENTON_HEADLESS": "1"} if data.get("headless", True) else {}
    real = guard.git_out
    url = data.get("origin_url", "git@github.com:SFenton/native-home.git")

    def git_out(top: str, *args: str) -> str:
        """``git remote get-url [--push] origin`` answers the product URL; any other remote name fails, as in a repo without it."""
        if args[:2] == ("remote", "get-url"):
            if args[-1] != "origin":
                raise OSError(f"error: No such remote '{args[-1]}'")
            return url
        return real(top, *args)

    with mock.patch.dict(os.environ, env), mock.patch.object(guard, "git_out", git_out):
        why = guard.reason(data["command"], data.get("cwd"))
    return {"blocked": why is not None, "reason": why or ""}


@handler("record_round")
def _record_round(ctx: Ctx, data: Dict[str, Any], tmp: Path) -> Dict[str, Any]:
    """``tools/review/record.py`` ``round_refusal``: would recording this review round be refused?"""
    record = ctx.load("tools/review/record.py")
    message = record.round_refusal(int(data["round"]), data.get("reason"), data.get("verdict", "pass"))
    return {"refused": message is not None, "message": message or ""}


@handler("lane_check")
def _lane_check(ctx: Ctx, data: Dict[str, Any], tmp: Path) -> Dict[str, Any]:
    """A ``lane_land`` check on a fixture ``git diff --raw`` list: ``rows`` are ``[status, path, old blob, new blob]``,
    ``blobs`` maps a blob id to its text, ``exists`` lists the paths present at the lane SHA."""
    ll = ctx.load("tools/lane_land.py")
    rows = [tuple(row) for row in data["rows"]]
    blobs, exists = data.get("blobs", {}), set(data.get("exists", []))
    check = data["check"]
    try:
        with mock.patch.object(ll, "blob_text", lambda _clone, blob: blobs.get(blob, "")), \
                mock.patch.object(ll, "_exists", lambda _clone, _sha, path: path in exists):
            if check == "paths":
                ll.check_paths(rows, ll.DEFAULT_PROTECTED, ll.DEFAULT_APPEND_ONLY)
            elif check == "separation":
                ll.check_separation(rows)
            elif check == "thresholds":
                ll.check_jev_thresholds(Path("."), rows)
            elif check == "retired":
                ll.check_retired(Path("."), "0" * 40, rows)
            else:
                raise ValueError(f"unknown lane check {check!r}")
    except ll.Refused as refusal:
        return {"refused": True, "kind": refusal.kind, "message": str(refusal)}
    return {"refused": False, "kind": "", "message": ""}



# MARK: - Entry point

def run(kind: str, data: Dict[str, Any], target: Path) -> Dict[str, Any]:
    """The observed result of one case ``kind`` against the code under ``target``, in a private world."""
    if kind not in HANDLERS:
        raise ValueError(f"unknown kind {kind!r} (known: {', '.join(sorted(HANDLERS))})")
    ctx = Ctx(target)
    try:
        with tempfile.TemporaryDirectory(prefix="agent-eval-") as name:
            tmp = Path(name)
            with isolated(tmp):
                return HANDLERS[kind](ctx, data, tmp)
    finally:
        ctx.close()


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Run one routing-replay case (called by tools/agent_eval.py).")
    parser.add_argument("--target", required=True, help="the checkout under test")
    parser.add_argument("--out", required=True, help="file the result JSON is written to")
    args = parser.parse_args(argv)
    result: Dict[str, Any]
    try:
        request = json.loads(sys.stdin.read())
        result = {"observed": run(str(request["kind"]), request.get("input") or {}, Path(args.target).resolve())}
    except BaseException as exc:  # noqa: BLE001 (a crashing code path is a failing case; SystemExit included)
        result = {"error": f"{type(exc).__name__}: {exc}"}
    Path(args.out).write_text(json.dumps(result, default=str), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
