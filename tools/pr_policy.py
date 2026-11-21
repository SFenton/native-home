#!/usr/bin/env python3
"""Base-trusted pull-request policy for agent, rule, grader and Jev changes.

The checkout containing this file is the trusted base.  The driver accepts
separate clean base and head checkouts plus tier-0 observations collected by
untrusted head code, compares exact trees, imports policy code only from the
base, and emits one small JSON verdict.

    python3 BASE/tools/pr_policy.py --base-checkout BASE --head-checkout HEAD \
        --base-sha BASE_SHA --head-sha HEAD_SHA \
        --head-observations tier0-observations.json

Tier 0 runs only trusted base code against base cases.  The head side is
replayed entirely from validated observations with the base evaluator and
expectations.  A changed Jev question deliberately remains a ``hold`` until a
trusted tier-1 result can be enforced without a pull-request credential.  The
driver scrubs child environments, fingerprints trusted inputs and terminates
evaluator process groups. Bytecode writes stay disabled for the driver's
trusted imports and every evaluator child. A recorded observation can be
fabricated, but it cannot choose a case, count or expectation, or publish the
trusted verdict.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import math
import multiprocessing
import os
import re
import signal
import stat
import subprocess
import sys
import time
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Dict, Iterator, List, Mapping, Optional, Sequence, Set, Tuple

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]
SHA_RE = re.compile(r"^[0-9a-f]{40}(?:[0-9a-f]{24})?$")
OBSERVATION_SHA_RE = re.compile(r"^[0-9a-f]{40}$")
CASE_ID_RE = re.compile(r"^[A-Za-z0-9._-]{1,128}$")
SCHEMA = 1
EVALUATOR_TIMEOUT = 300.0
OBSERVATIONS_MAX_BYTES = 8 * 1024 * 1024
JSON_MAX_DEPTH = 32
ENV_ALLOWLIST = ("PATH", "LANG", "LC_ALL", "LC_CTYPE", "TMPDIR")

PASS = "pass"
FAIL = "fail"
HOLD = "hold"
NOOP = "noop"

# Only this positively identified, self-contained product tree can skip tier 0.
PRODUCT_PATHS = ("apple/**",)
# These extend the older lander separation set for neutral roles and executable
# routing, runner and adapter inputs.
EXTRA_BEHAVIOUR_PATHS = (
    ".claude/**",
    ".agents/**",
    "agents/roles/**",
    "tools/triage/**",
    "tools/**/*runner*.py",
    "tools/**/*adapter*.py",
)
BEHAVIOUR_EXCLUDED_PATHS = frozenset(("tools/triage/config.json",))
EXTRA_EVAL_PATHS = (
    "tools/agent_eval.py",
    "tools/agent_eval_case.py",
    "tools/agent_eval_measure.py",
    "tools/pr_policy.py",
    "tools/ci_aggregate.py",
    "tools/lane_land.py",
    "tools/triage/config.json",
    "tools/jev_*.py",
    "evals/**/*.py",
    "evals/**/run*",
)

Change = Tuple[str, str, str, str]


class PolicyError(Exception):
    """A policy failure represented by an enumerated verdict reason."""

    def __init__(self, reason: str):
        super().__init__(reason)
        self.reason = reason
        self.base_sha = ""
        self.head_sha = ""


def _json_pairs(pairs: Sequence[Tuple[str, Any]]) -> Dict[str, Any]:
    result: Dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key")
        result[key] = value
    return result


def _json_float(value: str) -> float:
    number = float(value)
    if not math.isfinite(number):
        raise ValueError("non-finite JSON number")
    return number


def _json_integer(value: str) -> int:
    if len(value.lstrip("-")) > 128:
        raise ValueError("JSON integer exceeds the limit")
    return int(value)


def _json_constant(_value: str) -> Any:
    raise ValueError("non-finite JSON number")


def _json_depth(value: Any, current: int = 1) -> int:
    if not isinstance(value, (dict, list)):
        return 0
    if current > JSON_MAX_DEPTH:
        raise ValueError("JSON depth exceeds the limit")
    child_depths = [
        _json_depth(child, current + 1)
        for child in (value.values() if isinstance(value, dict) else value)
        if isinstance(child, (dict, list))
    ]
    return max(child_depths or [current])


def _strict_json(payload: bytes) -> Any:
    text = payload.decode("utf-8")
    parsed = json.loads(
        text,
        object_pairs_hook=_json_pairs,
        parse_int=_json_integer,
        parse_float=_json_float,
        parse_constant=_json_constant,
    )
    _json_depth(parsed)
    return parsed


def _read_observations(path: Optional[Path], base_sha: str,
                       head_sha: str) -> Dict[str, Mapping[str, Any]]:
    """Read and validate the closed, bounded observations data contract."""
    if path is None:
        raise PolicyError("tier0_unavailable")
    try:
        metadata = path.lstat()
    except OSError as exc:
        raise PolicyError("tier0_unavailable") from exc
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        raise PolicyError("tier0_malformed")
    try:
        flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
        descriptor = os.open(str(path), flags)
        with os.fdopen(descriptor, "rb") as stream:
            opened = os.fstat(stream.fileno())
            if not stat.S_ISREG(opened.st_mode):
                raise PolicyError("tier0_malformed")
            if opened.st_size > OBSERVATIONS_MAX_BYTES:
                raise PolicyError("tier0_malformed")
            payload = stream.read(OBSERVATIONS_MAX_BYTES + 1)
    except PolicyError:
        raise
    except OSError as exc:
        raise PolicyError("tier0_unavailable") from exc
    if len(payload) > OBSERVATIONS_MAX_BYTES:
        raise PolicyError("tier0_malformed")
    try:
        document = _strict_json(payload)
    except (UnicodeDecodeError, ValueError, TypeError, RecursionError) as exc:
        raise PolicyError("tier0_malformed") from exc
    if not isinstance(document, dict) or set(document) != {
            "schema", "base_sha", "head_sha", "cases",
    }:
        raise PolicyError("tier0_malformed")
    if type(document["schema"]) is not int or document["schema"] != SCHEMA:
        raise PolicyError("tier0_malformed")
    for label, actual, expected in (
        ("base", document["base_sha"], base_sha),
        ("head", document["head_sha"], head_sha),
    ):
        if not isinstance(actual, str) or \
                not OBSERVATION_SHA_RE.fullmatch(actual) or actual != expected:
            raise PolicyError("tier0_malformed")
    cases = document["cases"]
    if not isinstance(cases, dict):
        raise PolicyError("tier0_malformed")
    validated: Dict[str, Mapping[str, Any]] = {}
    for case_id, entry in cases.items():
        if not isinstance(case_id, str) or not CASE_ID_RE.fullmatch(case_id):
            raise PolicyError("tier0_malformed")
        if not isinstance(entry, dict) or set(entry) not in ({"observed"}, {"error"}):
            raise PolicyError("tier0_malformed")
        if "observed" in entry:
            if not isinstance(entry["observed"], dict):
                raise PolicyError("tier0_malformed")
        else:
            error = entry["error"]
            if not isinstance(error, str) or not error or len(error) > 200:
                raise PolicyError("tier0_malformed")
        validated[case_id] = entry
    return validated


def _git(checkout: Path, *args: str, text: bool = True) -> subprocess.CompletedProcess:
    """Run one read-only Git plumbing command with repository hooks disabled."""
    safe = ("-c", "core.hooksPath=/dev/null", "-c", "core.fsmonitor=false",
            "-c", "protocol.ext.allow=never")
    return subprocess.run(
        ["git", "-C", str(checkout), *safe, *args],
        capture_output=True,
        text=text,
        env=_child_environment(),
    )


def _child_environment() -> Dict[str, str]:
    """A fresh process environment with no inherited Git, Python or Actions state."""
    env = {key: os.environ[key] for key in ENV_ALLOWLIST if key in os.environ}
    env.setdefault("PATH", os.defpath)
    env.update({
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": os.devnull,
        "GIT_ATTR_NOSYSTEM": "1",
        "GIT_NO_REPLACE_OBJECTS": "1",
        "GIT_TERMINAL_PROMPT": "0",
        "PYTHONDONTWRITEBYTECODE": "1",
    })
    return env


@contextmanager
def _scrubbed_process_environment() -> Iterator[None]:
    saved = dict(os.environ)
    os.environ.clear()
    os.environ.update(_child_environment())
    try:
        yield
    finally:
        os.environ.clear()
        os.environ.update(saved)


def _checkout_sha(path: Path, label: str) -> str:
    checkout = path.resolve()
    if not checkout.is_dir() or not (checkout / ".git").exists():
        raise PolicyError(f"{label}_checkout_unreadable")
    inside = _git(checkout, "rev-parse", "--is-inside-work-tree")
    head = _git(checkout, "rev-parse", "--verify", "-q", "HEAD^{commit}")
    if inside.returncode != 0 or inside.stdout.strip() != "true" or head.returncode != 0:
        raise PolicyError(f"{label}_checkout_unreadable")
    actual = head.stdout.strip()
    if not SHA_RE.fullmatch(actual):
        raise PolicyError(f"{label}_sha_unreadable")
    return actual


def verify_checkout(path: Path, expected: str, label: str) -> str:
    """Return the clean checkout's exact commit after verifying its advertised SHA."""
    checkout = path.resolve()
    actual = _checkout_sha(checkout, label)
    if not expected or not SHA_RE.fullmatch(expected.lower()):
        raise PolicyError(f"{label}_sha_unreadable")
    if expected.lower() != actual:
        raise PolicyError(f"{label}_sha_mismatch")
    status = _git(checkout, "status", "--porcelain=v1", "--untracked-files=all")
    if status.returncode != 0 or status.stdout:
        raise PolicyError(f"{label}_checkout_dirty")
    return actual


def _object_dir(checkout: Path) -> Path:
    common = _git(checkout, "rev-parse", "--git-common-dir")
    if common.returncode != 0:
        raise PolicyError("git_objects_unreadable")
    result = Path(common.stdout.strip())
    if not result.is_absolute():
        result = checkout / result
    result = (result / "objects").resolve()
    if not result.is_dir():
        raise PolicyError("git_objects_unreadable")
    return result


def trusted_object_repo(base: Path, head: Path) -> "TemporaryObjectRepo":
    """A temporary Git view that can read base and head objects without checkout code."""
    return TemporaryObjectRepo(base, head)


class TemporaryObjectRepo:
    """A temporary repository whose object database exposes two read-only inputs."""

    def __init__(self, base: Path, head: Path):
        import tempfile

        self._temporary = tempfile.TemporaryDirectory(prefix="pr-policy-objects-")
        self.path = Path(self._temporary.name)
        initialized = _git(self.path, "init", "-q")
        if initialized.returncode != 0:
            self.close()
            raise PolicyError("git_objects_unreadable")
        alternates = self.path / ".git" / "objects" / "info" / "alternates"
        try:
            alternates.write_text(
                f"{_object_dir(base)}\n{_object_dir(head)}\n",
                encoding="utf-8",
            )
        except PolicyError:
            self.close()
            raise
        except OSError as exc:
            self.close()
            raise PolicyError("git_objects_unreadable") from exc

    def close(self) -> None:
        self._temporary.cleanup()

    def __enter__(self) -> "TemporaryObjectRepo":
        return self

    def __exit__(self, *_args: object) -> None:
        self.close()


def _tree(checkout: Path, sha: str) -> Dict[str, Tuple[str, str, str]]:
    proc = _git(checkout, "ls-tree", "-rz", "--full-tree", sha, text=False)
    if proc.returncode != 0:
        raise PolicyError("scope_unreadable")
    rows: Dict[str, Tuple[str, str, str]] = {}
    for raw in proc.stdout.split(b"\0"):
        if not raw:
            continue
        try:
            meta, raw_path = raw.split(b"\t", 1)
            mode, kind, oid = meta.decode("ascii").split()
            path = raw_path.decode("utf-8")
        except (ValueError, UnicodeDecodeError) as exc:
            raise PolicyError("scope_unreadable") from exc
        if "\n" in path or "\t" in path or path.startswith("/") or ".." in path.split("/"):
            raise PolicyError("scope_unreadable")
        rows[path] = (mode, kind, oid)
    return rows


def changed_paths(base: Path, base_sha: str, head: Path, head_sha: str) -> List[Change]:
    """Return the pull request's merge-base-to-head diff, with both rename sides."""
    with trusted_object_repo(base, head) as objects:
        merge = _git(objects.path, "merge-base", base_sha, head_sha)
        if merge.returncode != 0 or not SHA_RE.fullmatch(merge.stdout.strip()):
            raise PolicyError("scope_unreadable")
        before, after = _tree(objects.path, merge.stdout.strip()), _tree(objects.path, head_sha)
    rows: List[Change] = []
    for path in sorted(before.keys() | after.keys()):
        old, new = before.get(path), after.get(path)
        if old == new:
            continue
        if old is None:
            rows.append(("A", path, "", str(new[2])))
        elif new is None:
            rows.append(("D", path, str(old[2]), ""))
        else:
            rows.append(("T" if old[:2] != new[:2] else "M", path, old[2], new[2]))
    return rows


def load_tool(base: Path, name: str) -> Any:
    """Import one trusted module from the base checkout."""
    path = base / "tools" / f"{name}.py"
    if not path.is_file():
        raise PolicyError("trusted_tool_unreadable")
    spec = importlib.util.spec_from_file_location(f"pr_policy_{name}", path)
    if spec is None or spec.loader is None:
        raise PolicyError("trusted_tool_unreadable")
    module = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(module)
    except (ImportError, OSError, SyntaxError, ValueError) as exc:
        raise PolicyError("trusted_tool_unreadable") from exc
    return module


def _check_separation(lander: Any, rows: Sequence[Change]) -> None:
    try:
        lander.check_separation(rows)
    except lander.Refused as exc:
        raise PolicyError("trusted_separation") from exc
    paths = [path for _status, path, _old, _new in rows]
    behaviour = lander.BEHAVIOUR_PATHS + EXTRA_BEHAVIOUR_PATHS
    evaluation = lander.EVAL_PATHS + EXTRA_EVAL_PATHS
    if any(path not in BEHAVIOUR_EXCLUDED_PATHS and lander.matches(path, behaviour)
           for path in paths) and \
            any(lander.matches(path, evaluation) for path in paths):
        raise PolicyError("trusted_separation")


def _run_prechecks(lander: Any, objects: TemporaryObjectRepo, rows: Sequence[Change],
                   head_sha: str) -> None:
    _check_separation(lander, rows)
    try:
        lander.check_paths(rows, (), lander.DEFAULT_APPEND_ONLY)
    except lander.Refused as exc:
        raise PolicyError("append_only") from exc
    try:
        lander.check_jev_thresholds(objects.path, rows)
    except lander.Refused as exc:
        raise PolicyError("jev_threshold") from exc
    try:
        lander.check_retired(objects.path, head_sha, rows)
    except lander.Refused as exc:
        raise PolicyError("retirement_invalid") from exc


def _case_entries(tree: Mapping[str, Tuple[str, str, str]]) -> Tuple[
        Dict[str, Tuple[str, str]], Dict[str, Tuple[str, str]]]:
    """Regular case blobs from the two canonical top-level case folders."""
    groups = {
        "cases": {},
        "retired": {},
    }
    prefix = "evals/agents/routing-replay/"
    for path, (mode, kind, oid) in sorted(tree.items()):
        if not path.startswith(prefix) or not path.endswith(".json") or \
                path.endswith(".reason.json"):
            continue
        relative = Path(path[len(prefix):])
        if len(relative.parts) != 2 or relative.parts[0] not in groups:
            continue
        stem = relative.stem
        if not CASE_ID_RE.fullmatch(stem):
            raise PolicyError("tier0_malformed")
        if not mode.startswith("100") or kind != "blob":
            raise PolicyError("tier0_malformed")
        if stem in groups[relative.parts[0]]:
            raise PolicyError("tier0_malformed")
        groups[relative.parts[0]][stem] = (path, oid)
    return groups["cases"], groups["retired"]


def _load_blob_case(evaluator: Any, objects: Path, path: str,
                    oid: str) -> Tuple[Path, Any]:
    proc = _git(objects, "cat-file", "blob", oid, text=False)
    if proc.returncode != 0 or len(proc.stdout) > 8 * 1024 * 1024:
        raise PolicyError("tier0_malformed")
    try:
        text = proc.stdout.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise PolicyError("tier0_malformed") from exc
    selected = Path(path)
    case, error = evaluator.parse_case(selected, text)
    if error or case is None or case.get("id") != selected.stem:
        raise PolicyError("tier0_malformed")
    return selected, (case, "")


def _tier0_selection(lander: Any, evaluator: Any, objects: TemporaryObjectRepo,
                     base: Path, head: Path, base_sha: str, head_sha: str,
                     rows: Sequence[Change]) -> Tuple[Any, Any, Set[str]]:
    """Build base-owned active/retired suites from exact Git blobs, including validated additions."""
    base_active, base_retired = _case_entries(_tree(objects.path, base_sha))
    head_active, head_retired = _case_entries(_tree(objects.path, head_sha))
    known = set(base_active) | set(base_retired)
    if set(base_active) & set(base_retired):
        raise PolicyError("tier0_malformed")

    base_loaded: Dict[str, Tuple[Path, Any]] = {}
    for case_id, (path, oid) in sorted({**base_active, **base_retired}.items()):
        base_loaded[case_id] = _load_blob_case(
            evaluator, objects.path, path, oid,
        )

    base_paths: List[Path] = []
    base_preloaded: List[Any] = []
    retired_paths: List[Path] = []
    retired_preloaded: List[Any] = []
    for case_id in sorted(base_active):
        selected, loaded = base_loaded[case_id]
        base_paths.append(base / selected)
        base_preloaded.append(loaded)
    for case_id in sorted(base_retired):
        selected, loaded = base_loaded[case_id]
        retired_paths.append(base / selected)
        retired_preloaded.append(loaded)

    moved = {
        Path(old).stem
        for old, _new in lander.retire_moves(rows)
        if old in {row[0] for row in base_active.values()}
    }
    classified = set(head_retired) & set(base_active)
    if moved != classified or (set(head_active) & classified):
        raise PolicyError("retirement_mismatch")
    duplicate = (set(head_active) & set(head_retired)) - set(base_active)
    if duplicate:
        raise PolicyError("tier0_malformed")

    additions: Dict[str, Tuple[Path, Any]] = {}
    for case_id in sorted(set(head_active) | set(head_retired)):
        if case_id in known:
            continue
        suite = head_active if case_id in head_active else head_retired
        path, oid = suite[case_id]
        additions[case_id] = _load_blob_case(evaluator, objects.path, path, oid)

    head_active_paths: List[Path] = []
    head_active_loaded: List[Any] = []
    head_retired_paths: List[Path] = []
    head_retired_loaded: List[Any] = []
    for case_id in sorted(set(base_active) | set(base_retired)):
        selected, loaded = base_loaded[case_id]
        is_retired = case_id in base_retired or case_id in head_retired
        paths = head_retired_paths if is_retired else head_active_paths
        cases = head_retired_loaded if is_retired else head_active_loaded
        paths.append(base / selected)
        cases.append(loaded)
    for case_id, (path, loaded) in sorted(additions.items()):
        is_retired = case_id in head_retired
        paths = head_retired_paths if is_retired else head_active_paths
        cases = head_retired_loaded if is_retired else head_active_loaded
        paths.append(head / path)
        cases.append(loaded)

    for files in (base_paths, retired_paths, head_active_paths, head_retired_paths):
        if len(files) != len({path.stem for path in files}):
            raise PolicyError("tier0_malformed")
    base_selection = (
        (base_paths, base_preloaded),
        (retired_paths, retired_preloaded),
    )
    head_selection = (
        (head_active_paths, head_active_loaded),
        (head_retired_paths, head_retired_loaded),
    )
    required = {path.stem for path in head_active_paths + head_retired_paths}
    return base_selection, head_selection, required


def _suite_map(evaluator: Any, suites: Any) -> Dict[str, Dict[str, Any]]:
    if not isinstance(suites, list):
        raise PolicyError("tier0_malformed")
    found: Dict[str, Dict[str, Any]] = {}
    for suite in suites:
        if not isinstance(suite, dict) or not isinstance(suite.get("name"), str):
            raise PolicyError("tier0_malformed")
        name = suite["name"]
        if name in found or type(suite.get("cases")) is not int or \
                type(suite.get("passed")) is not int or \
                not isinstance(suite.get("failures"), list):
            raise PolicyError("tier0_malformed")
        if suite["cases"] < 0:
            raise PolicyError("tier0_malformed")
        found[name] = suite
    required = {evaluator.SUITE, evaluator.RETIRED_SUITE}
    if set(found) != required:
        raise PolicyError("tier0_missing_summary")
    return found


def _active_failures(suite: Dict[str, Any]) -> Set[str]:
    failures: Set[str] = set()
    for row in suite.get("failures", []):
        if not isinstance(row, (list, tuple)) or not row or not isinstance(row[0], str):
            raise PolicyError("tier0_malformed")
        failures.add(row[0])
    if len(failures) != len(suite.get("failures", [])):
        raise PolicyError("tier0_malformed")
    return failures


def _terminate_process_group(process: multiprocessing.Process) -> None:
    """Terminate a worker group and any children that outlived its leader."""
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except (ProcessLookupError, PermissionError):
        return
    time.sleep(0.05)
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        pass


def _bytecode_safe_command(command: Any) -> Any:
    """Add Python's bytecode flag after its interpreter, including behind a launcher."""
    if not isinstance(command, (list, tuple)):
        return command
    result = list(command)
    interpreter = str(sys.executable)
    try:
        position = next(index for index, part in enumerate(result)
                        if str(part) == interpreter)
        script = next(index for index, part in enumerate(result[position + 1:], position + 1)
                      if str(part).endswith("agent_eval_case.py"))
    except StopIteration:
        return command
    if "-B" not in result[position + 1:script]:
        result.insert(position + 1, "-B")
    return result


def _case_run(original: Any, *popenargs: Any, **kwargs: Any) -> subprocess.CompletedProcess:
    """Run one evaluator child and end its whole process group before returning."""
    command = popenargs[0] if popenargs else kwargs.get("args")
    if not isinstance(command, (list, tuple)) or \
            not any(str(part).endswith("agent_eval_case.py") for part in command):
        return original(*popenargs, **kwargs)
    command = _bytecode_safe_command(command)
    if popenargs:
        popenargs = (command, *popenargs[1:])
    else:
        kwargs["args"] = command
    child_env = dict(kwargs.get("env") or os.environ)
    child_env["PYTHONDONTWRITEBYTECODE"] = "1"
    kwargs["env"] = child_env
    input_value = kwargs.pop("input", None)
    timeout = kwargs.pop("timeout", None)
    check = kwargs.pop("check", False)
    if input_value is not None and "stdin" not in kwargs:
        kwargs["stdin"] = subprocess.PIPE
    if kwargs.pop("capture_output", False):
        if "stdout" in kwargs or "stderr" in kwargs:
            raise ValueError("stdout and stderr arguments may not be used with capture_output")
        kwargs["stdout"] = subprocess.PIPE
        kwargs["stderr"] = subprocess.PIPE
    kwargs["start_new_session"] = True
    process = subprocess.Popen(*popenargs, **kwargs)
    try:
        stdout, stderr = process.communicate(input=input_value, timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        _terminate_process(process.pid)
        stdout, stderr = process.communicate()
        raise subprocess.TimeoutExpired(command, timeout, stdout or exc.output, stderr or exc.stderr) from exc
    finally:
        _terminate_process(process.pid)
    result = subprocess.CompletedProcess(command, process.returncode, stdout, stderr)
    if check:
        result.check_returncode()
    return result


def _terminate_process(pid: int) -> None:
    try:
        os.killpg(pid, signal.SIGTERM)
    except (ProcessLookupError, PermissionError):
        return
    time.sleep(0.05)
    try:
        os.killpg(pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        pass


def _bounded_pipe_suites(suites: Any) -> Any:
    """Remove child/observation text before crossing the worker pipe."""
    if not isinstance(suites, list):
        return suites
    bounded = []
    for suite in suites:
        if not isinstance(suite, dict):
            bounded.append(suite)
            continue
        item = dict(suite)
        failures = item.get("failures")
        if isinstance(failures, list):
            item["failures"] = [
                [row[0][:128], ["tier 0 mismatch"]]
                if isinstance(row, (list, tuple)) and row and isinstance(row[0], str)
                else row
                for row in failures
            ]
        for key in ("name",):
            if isinstance(item.get(key), str):
                item[key] = item[key][:200]
        item.pop("notes", None)
        bounded.append(item)
    return bounded


def _tier0_worker(connection: Any, evaluator: Any, base: Path, head: Path,
                  base_selection: Any, head_selection: Any,
                  observations: Mapping[str, Mapping[str, Any]]) -> None:
    """Run trusted tier 0 in a private process group and return validated data shapes."""
    devnull: Optional[int] = None
    try:
        os.setsid()
        devnull = os.open(os.devnull, os.O_RDWR)
        os.dup2(devnull, 1)
        os.dup2(devnull, 2)
        with _scrubbed_process_environment():
            original = evaluator.subprocess.run
            evaluator.subprocess.run = lambda *args, **kwargs: _case_run(original, *args, **kwargs)
            base_suites = evaluator.evaluate(
                base, tier=0, target=base, tier0_selection=base_selection,
            )
            head_suites = evaluator.evaluate(
                base, tier=0, target=head, tier0_selection=head_selection,
                observer=evaluator.recorded_observer(observations),
            )
        payload = json.dumps(
            {
                "status": "ok",
                "base_suites": _bounded_pipe_suites(base_suites),
                "head_suites": _bounded_pipe_suites(head_suites),
            },
            ensure_ascii=True,
            separators=(",", ":"),
        ).encode("utf-8")
        connection.send_bytes(payload)
    except BaseException:
        try:
            connection.send_bytes(b'{"status":"error"}')
        except (BrokenPipeError, EOFError, OSError):
            pass
    finally:
        connection.close()
        if devnull is not None:
            os.close(devnull)


def _evaluate_tier0(evaluator: Any, base: Path, head: Path,
                    base_selection: Any, head_selection: Any,
                    observations: Mapping[str, Mapping[str, Any]]) -> Tuple[Any, Any]:
    context = multiprocessing.get_context("fork")
    receive, send = context.Pipe(duplex=False)
    process = context.Process(
        target=_tier0_worker,
        args=(send, evaluator, base, head, base_selection, head_selection, observations),
    )
    process.start()
    send.close()
    try:
        if not receive.poll(EVALUATOR_TIMEOUT):
            raise PolicyError("tier0_unavailable")
        try:
            payload = receive.recv_bytes(8 * 1024 * 1024)
        except OSError as exc:
            raise PolicyError("tier0_malformed") from exc
        try:
            message = json.loads(payload.decode("utf-8"))
        except (UnicodeDecodeError, ValueError) as exc:
            raise PolicyError("tier0_malformed") from exc
        if not isinstance(message, dict) or \
                not isinstance(message.get("status"), str) or \
                message["status"] not in ("ok", "error"):
            raise PolicyError("tier0_malformed")
        if message["status"] == "error":
            if set(message) != {"status"}:
                raise PolicyError("tier0_malformed")
            raise PolicyError("tier0_unavailable")
        if set(message) != {"status", "base_suites", "head_suites"}:
            raise PolicyError("tier0_malformed")
    except EOFError as exc:
        raise PolicyError("tier0_unavailable") from exc
    finally:
        receive.close()
        _terminate_process_group(process)
        process.join(1.0)
        if process.is_alive():
            process.kill()
            process.join()
    return message["base_suites"], message["head_suites"]


def _validate_tier0(evaluator: Any, base_suites: Any, head_suites: Any,
                    base_selection: Any, head_selection: Any) -> None:
    """Compare trusted and target tier-0 suites without accepting child text."""
    base_map, head_map = _suite_map(evaluator, base_suites), _suite_map(evaluator, head_suites)
    expected_base = {
        evaluator.SUITE: {path.stem for path in base_selection[0][0]},
        evaluator.RETIRED_SUITE: {path.stem for path in base_selection[1][0]},
    }
    expected_head = {
        evaluator.SUITE: {path.stem for path in head_selection[0][0]},
        evaluator.RETIRED_SUITE: {path.stem for path in head_selection[1][0]},
    }
    base_total = sum(suite["cases"] for suite in base_map.values())
    head_total = sum(suite["cases"] for suite in head_map.values())
    wanted_base_total = sum(len(ids) for ids in expected_base.values())
    wanted_head_total = sum(len(ids) for ids in expected_head.values())
    if base_total < wanted_base_total or head_total < base_total or \
            head_total < wanted_head_total:
        raise PolicyError("tier0_lost_count")
    if base_total > wanted_base_total or head_total > wanted_head_total:
        raise PolicyError("tier0_malformed")
    for suites, expected in (
        (base_map, expected_base),
        (head_map, expected_head),
    ):
        for name, ids in expected.items():
            suite = suites[name]
            if suite["cases"] != len(ids) or \
                    suite["passed"] != suite["cases"] - len(suite["failures"]):
                raise PolicyError("tier0_malformed")
            failures = _active_failures(suite)
            if not failures <= ids:
                raise PolicyError("tier0_malformed")
    base_failures = _active_failures(base_map[evaluator.SUITE])
    head_failures = _active_failures(head_map[evaluator.SUITE])
    if head_failures - base_failures:
        raise PolicyError("tier0_new_failure")


def _fingerprint(base: Path) -> str:
    """Hash checkout entries without Git, repository config or attribute filters."""
    rows: List[Tuple[str, str]] = []
    try:
        def unreadable(error: OSError) -> None:
            raise error

        for root, directories, files in os.walk(
                base, topdown=True, onerror=unreadable, followlinks=False):
            directories[:] = sorted(name for name in directories if name != ".git")
            entries = directories + sorted(name for name in files if name != ".git")
            for name in entries:
                path = Path(root) / name
                relative = path.relative_to(base).as_posix()
                if relative.startswith("/") or ".." in Path(relative).parts:
                    raise PolicyError("trusted_fingerprint_unreadable")
                path = base / relative
                metadata = path.lstat()
                if stat.S_ISLNK(metadata.st_mode):
                    value = f"link:{os.readlink(path)}"
                elif stat.S_ISDIR(metadata.st_mode):
                    value = f"dir:{stat.S_IMODE(metadata.st_mode)}"
                elif stat.S_ISREG(metadata.st_mode):
                    value = (
                        f"{stat.S_IMODE(metadata.st_mode)}:"
                        f"{hashlib.sha256(path.read_bytes()).hexdigest()}"
                    )
                else:
                    value = (
                        f"type:{stat.S_IFMT(metadata.st_mode)}:"
                        f"{stat.S_IMODE(metadata.st_mode)}"
                    )
                rows.append((relative, value))
    except PolicyError:
        raise
    except (OSError, UnicodeError) as exc:
        raise PolicyError("trusted_fingerprint_unreadable") from exc
    encoded = json.dumps(sorted(set(rows)), ensure_ascii=True, separators=(",", ":"))
    return hashlib.sha256(encoded.encode("utf-8")).hexdigest()


def _run_tier0(evaluator: Any, base: Path, head: Path,
               base_selection: Any, head_selection: Any,
               observations: Mapping[str, Mapping[str, Any]]) -> None:
    before = _fingerprint(base)
    try:
        base_suites, head_suites = _evaluate_tier0(
            evaluator, base, head, base_selection, head_selection, observations,
        )
    except PolicyError:
        raise
    except (OSError, RuntimeError, ValueError) as exc:
        raise PolicyError("tier0_unavailable") from exc
    if _fingerprint(base) != before:
        raise PolicyError("trusted_checkout_changed")
    _validate_tier0(
        evaluator, base_suites, head_suites, base_selection, head_selection,
    )


def _verdict(base_sha: str, head_sha: str, outcome: str, reasons: Sequence[str]) -> Dict[str, Any]:
    return {
        "schema": SCHEMA,
        "outcome": outcome,
        "reasons": sorted(set(reasons)),
        "base_sha": base_sha,
        "head_sha": head_sha,
    }


def evaluate_policy(base: Path, head: Path, base_sha: str, head_sha: str,
                    head_observations: Optional[Path] = None) -> Dict[str, Any]:
    """Evaluate one pull request and return a diff-independent machine verdict."""
    base, head = base.resolve(), head.resolve()
    if base == head or base != ROOT:
        raise PolicyError("driver_not_base")
    actual_base = verify_checkout(base, base_sha, "base")
    actual_head = verify_checkout(head, head_sha, "head")
    try:
        lander, evaluator = load_tool(base, "lane_land"), load_tool(base, "agent_eval")
        rows = changed_paths(base, actual_base, head, actual_head)
        with trusted_object_repo(base, head) as objects:
            _run_prechecks(lander, objects, rows, actual_head)
            base_selection, head_selection, required = _tier0_selection(
                lander, evaluator, objects, base, head,
                actual_base, actual_head, rows,
            )
        observations = _read_observations(
            head_observations, actual_base, actual_head,
        )
        if required - set(observations):
            raise PolicyError("tier0_unavailable")
        if not rows:
            return _verdict(actual_base, actual_head, PASS, ("no_changes",))
        if all(lander.matches(path, PRODUCT_PATHS) for _s, path, _o, _n in rows):
            return _verdict(actual_base, actual_head, NOOP, ("product_only",))
        _run_tier0(
            evaluator, base, head, base_selection, head_selection, observations,
        )
        changed_questions = any(
            lander.matches(path, (lander.JEV_QUESTIONS,))
            for _status, path, _old, _new in rows
        )
        if changed_questions:
            return _verdict(actual_base, actual_head, HOLD, ("tier1_required",))
        return _verdict(actual_base, actual_head, PASS, ("tier0_pass",))
    except PolicyError as exc:
        exc.base_sha = actual_base
        exc.head_sha = actual_head
        raise


def _write(path: Optional[str], verdict: Dict[str, Any]) -> None:
    text = json.dumps(verdict, sort_keys=True, separators=(",", ":"))
    print(text)
    if not path:
        return
    output = Path(path)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(text + "\n", encoding="utf-8")


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Base-trusted pull-request policy.")
    parser.add_argument("--base-checkout", "--base", dest="base", required=True, type=Path)
    parser.add_argument("--head-checkout", "--head", dest="head", required=True, type=Path)
    parser.add_argument("--base-sha", required=True)
    parser.add_argument("--head-sha", required=True)
    parser.add_argument("--head-observations", type=Path)
    parser.add_argument("--out", default="")
    args = parser.parse_args(argv)
    verdict: Dict[str, Any]
    try:
        verdict = evaluate_policy(
            args.base, args.head, args.base_sha, args.head_sha,
            args.head_observations,
        )
    except PolicyError as exc:
        base_sha, head_sha = exc.base_sha, exc.head_sha
        if not base_sha:
            try:
                base_sha = _checkout_sha(args.base.resolve(), "base")
            except PolicyError:
                base_sha = ""
        if not head_sha:
            try:
                head_sha = _checkout_sha(args.head.resolve(), "head")
            except PolicyError:
                head_sha = ""
        verdict = _verdict(base_sha, head_sha, FAIL, (exc.reason,))
    except Exception:
        print("pr_policy: internal policy failure", file=sys.stderr)
        verdict = _verdict("", "", FAIL, ("policy_internal",))
    _write(args.out or None, verdict)
    return 0 if verdict["outcome"] in (PASS, NOOP) else 1


if __name__ == "__main__":
    sys.exit(main())
