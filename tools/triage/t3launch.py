#!/usr/bin/env python3
"""The T3 launcher of the triage runner (``agent.launcher: "t3code"``): start a worker session as a T3 Code thread.

The runner keeps creating a git worktree per issue (``prepare_worktree``) and hands it to ``t3code handover --checkout current``; T3 only
runs the session. The deny list, headless markers and timeout that ``claude -p`` takes from the runner's process come from the registry
instead (``tools/hooks/triage_session.py``: the record is written *before* the handover, so the first tool call is already covered).
The reviewer never comes through here; it stays ``claude -p --agent reviewer``.

One launch, in order: guard check (worktree hooks equal the trusted checkout's) -> write the record -> ``handover`` -> write the thread-keyed
record -> one blocking ``threads wait`` -> (timeout: ``interrupt``; needs a person: decline / answer, at most N times) -> transcript into the
log -> ``settle``, ``archive``, kill what still carries the thread id or sits in the worktree -> end-of-session hash check.

Third-party CLI, verified against ``@bvdm/t3code-cli`` **0.3.0** (npm gitHead ``a92548e798225439ab4934110302b9958f69ad7b``, tag ``v0.3.0``;
README and ``src/cli.ts``, ``src/service.ts``, ``src/doctor.ts``, ``src/cliShared.ts`` at that commit, read 2026-11-10):

* ``handover`` (alias ``threads create``) flags (``cli.ts`` ``addThreadOptions``): ``--stdin``, ``--cwd``, ``--workspace-mode repo|folder``,
  ``--project-policy create|existing``, ``--open auto|desktop|browser|none``, ``--provider``, ``--model``, ``--thinking-effort``,
  ``--checkout t3|local|current|worktree``, ``--permission approval-required|auto-accept-edits|full-access``, ``--mode default|build|plan``,
  ``--wait``, ``--dry-run``. ``--json`` is global: ``{"ok": true, "data": ...}`` on stdout.
* **There is no ``--no-start-desktop`` on ``handover``** (it exists on ``threads send`` only; README "Idempotent sends"). ``createHandoverThread``
  calls ``discoverRuntime(startDesktopIfNeeded: true)``, so a handover may open T3 Code when it is not running; ``--open none`` only stops
  it from revealing the thread. The note's argv had the flag; it would be a usage error, so it is left out.
* **The note's ``--workspace-mode folder`` cannot work with a fresh worktree**: ``folder`` makes the worktree itself the project root, and no
  project exists for it. In ``repo`` mode a linked worktree resolves to the main checkout's project (``workspace.ts`` ``mainWorktreeRootOf``,
  ``service.ts`` ``projectRootFor``) and ``--checkout current`` launches the thread in that worktree (``existing_worktree`` strategy,
  ``service.ts`` ``createHandoverThread``). So the project is the runner's one clone; ``project_policy`` defaults to ``create`` so the first
  launch makes that project (set ``existing`` after ``projects ensure --cwd <clone>`` to forbid creating one).
* The thread id is ``data.thread.id`` of the handover JSON (``service.ts``, the ``thread: {id: createdThreadId, ...}`` of the result).
  ``threads list --status active --cwd W --json`` (``data.threads[].id``, newest first) is the fallback.
* ``threads wait --thread ID --timeout S`` returns ``data.wait.outcome`` in ``completed|interrupted|error|needs-attention|queue-held|ended|
  idle`` and ``data.pendingRequests`` (``kind: "approval"`` or a question); exit code 6 is a timed-out wait. Exit codes: 0 ok, 1 general,
  2 usage, 3 missing target, 4 refused (``T3_PROTOCOL_UNSUPPORTED``, ``THREAD_NOT_RUNNING``), 5 dispatched but not shown in time, 6 wait timeout.
* ``threads interrupt|decline|answer (--answer TEXT | --dismiss)|settle|archive|read --detail full|inspect`` take ``--thread ID``;
  ``doctor`` reports ``checks.orchestrationProtocol.ok`` and ``checks.t3Cli.ok`` (false on a known version mismatch with the server).

Standard library only; every process call goes through the injectable ``run``.
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import shlex
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Callable, Dict, List, Mapping, NamedTuple, Optional, Tuple

#: The version ``install-t3code`` pins and ``ready`` demands (owner, 2026-11-10).
PINNED_VERSION = "0.3.0"
PACKAGE = "@bvdm/t3code-cli"
#: Where ``install-t3code`` puts the CLI, relative to the agent root (``~/hass-agents``).
INSTALL_DIR = ("tools", "t3code")
DEFAULTS: Dict[str, Any] = {
    "command": "", "version": PINNED_VERSION, "provider": "claudeAgent", "model": "", "effort": "", "checkout": "current",
    "permission": "full-access", "mode": "build", "workspace_mode": "repo", "project_policy": "create", "extra_denied": [],
    "interrupt_grace_seconds": 60, "needs_attention_retries": 3,
}
#: What a session that waits for a person is told (T3 would wait for a human; the unattended runner never answers one).
UNATTENDED = "Nobody is here to answer. Decide yourself and carry on; this run is unattended."
#: Slack on the single blocking ``threads wait`` before the subprocess itself is given up on (the CLI times out first).
WAIT_SLACK = 180


class LaunchError(Exception):
    """The launch cannot start or cannot be made safe; nothing is running (or the thread was interrupted). ``stray`` is true when
    reaping a thread the failed handover may have left found a process it could not kill."""

    def __init__(self, message: str, stray: bool = False):
        super().__init__(message)
        self.stray = stray


class Outcome(NamedTuple):
    """The result of one T3 launch: the code the runner's callers expect (``-9`` = stopped at the timeout), the thread id, whether
    something survived the cleanup (``stray``) and whether the guard hooks changed during the session (``tampered``)."""
    code: int
    thread: Optional[str]
    stray: bool = False
    tampered: bool = False


def session_module() -> Any:
    """``tools/hooks/triage_session.py`` loaded by path (the registry API: ``build_record``, ``write_record``, ``forget``, ``resolve``)."""
    if "triage_session" in sys.modules:
        return sys.modules["triage_session"]
    path = Path(__file__).resolve().parents[1] / "hooks" / "triage_session.py"
    spec = importlib.util.spec_from_file_location("triage_session", path)
    module = importlib.util.module_from_spec(spec)
    sys.modules["triage_session"] = module  # its dataclass looks the module up while it loads
    try:
        spec.loader.exec_module(module)
    except BaseException:
        sys.modules.pop("triage_session", None)
        raise
    return module


def registry_root(home: Path) -> Path:
    """``<home>/hass-agents/t3``, the registry the hooks read."""
    return session_module().registry_root(str(home))


def forget(worktree: Path, home: Path) -> None:
    """Drop the registry records of ``worktree``: called wherever the runner removes a worktree. Never raises."""
    try:
        session_module().forget(worktree, registry_root(home))
    except Exception as exc:  # noqa: BLE001 - a stale record only keeps guarding a path that no longer exists
        print(f"could not forget the triage records of {worktree}: {type(exc).__name__}")


def thread_tail(log_text: str, messages: int = 3) -> Optional[str]:
    """For a T3 log: the last ``messages`` assistant messages of its final ``t3_thread`` line (or the launch failure reason); ``None``
    for a log that is not a T3 one (the caller then shows the raw last lines)."""
    last: Optional[Dict[str, Any]] = None
    for line in log_text.splitlines():
        if line.startswith('{"type": "t3_'):
            try:
                event = json.loads(line)
            except ValueError:
                continue
            if isinstance(event, dict) and (event.get("type") == "t3_thread" or last is None):
                last = event
    if last is None:
        return None
    if last.get("type") != "t3_thread":
        return str(last.get("reason") or last.get("type"))
    thread = (last.get("data") or {}).get("thread")
    thread = thread if isinstance(thread, dict) else (last.get("data") or {})
    texts = [str(m.get("text") or "").strip() for m in thread.get("messages") or [] if isinstance(m, dict) and m.get("role") == "assistant"]
    return "\n\n".join([t for t in texts if t][-messages:])


# MARK: - Configuration and the argv

def t3_config(agent: Mapping[str, Any]) -> Dict[str, Any]:
    """``agent.t3`` over :data:`DEFAULTS`, with ``model`` and ``effort`` taken from the agent's own. Raises ``LaunchError`` for a value
    outside the closed set the design allows (``checkout`` is only ``current``: the runner makes the worktree)."""
    cfg = {**DEFAULTS, **dict(agent.get("t3") or {})}
    cfg["model"] = cfg["model"] or agent.get("model") or ""
    cfg["effort"] = cfg["effort"] or agent.get("effort") or ""
    if cfg["checkout"] != "current":
        raise LaunchError(f"agent.t3.checkout must be \"current\" (the runner creates the worktree), not {cfg['checkout']!r}")
    if cfg["project_policy"] not in ("create", "existing") or cfg["workspace_mode"] not in ("repo", "folder"):
        raise LaunchError("agent.t3.project_policy is create|existing and workspace_mode is repo|folder")
    return cfg


def executable(cfg: Mapping[str, Any], root: Path) -> str:
    """The pinned binary: ``agent.t3.command``, else ``<root>/tools/t3code/node_modules/.bin/t3code``."""
    return os.path.expanduser(str(cfg.get("command") or "")) or str(root.joinpath(*INSTALL_DIR, "node_modules", ".bin", "t3code"))


def handover_argv(exe: str, cfg: Mapping[str, Any], worktree: Path) -> List[str]:
    """The handover command (the prompt goes on stdin)."""
    return [exe, "--json", "handover", "--stdin", "--cwd", str(worktree), "--workspace-mode", cfg["workspace_mode"],
            "--project-policy", cfg["project_policy"], "--checkout", cfg["checkout"], "--provider", cfg["provider"],
            "--model", cfg["model"], "--thinking-effort", cfg["effort"], "--permission", cfg["permission"],
            "--mode", cfg["mode"], "--open", "none"]


def thread_argv(exe: str, *words: str, thread: str, extra: Tuple[str, ...] = ()) -> List[str]:
    """``t3code --json threads <words...> --thread ID [extra...]``."""
    return [exe, "--json", "threads", *words, "--thread", thread, *extra]


def data_of(proc: Any) -> Dict[str, Any]:
    """``data`` of a ``--json`` success envelope on ``proc.stdout``, or ``{}``."""
    try:
        value = json.loads(proc.stdout or "")
    except ValueError:
        return {}
    data = value.get("data") if isinstance(value, dict) else None
    return data if isinstance(data, dict) else {}


def install(root: Path, env: Mapping[str, str], run: Callable[..., Any] = subprocess.run) -> int:
    """``hass_triage.py install-t3code``: ``npm install --prefix <root>/tools/t3code --save-exact @bvdm/t3code-cli@0.3.0 --ignore-scripts``,
    then check ``--version`` and record the lockfile's sha256 in ``<prefix>/LOCK.sha256``. Nothing global; an upgrade is a change to
    :data:`PINNED_VERSION`. Returns an exit code."""
    prefix = root.joinpath(*INSTALL_DIR)
    prefix.mkdir(parents=True, exist_ok=True)
    spec = f"{PACKAGE}@{PINNED_VERSION}"
    proc = run(["npm", "install", "--prefix", str(prefix), "--save-exact", spec, "--ignore-scripts"], env=dict(env), capture_output=True, text=True)
    if proc.returncode != 0:
        print(f"npm install {spec} failed: {(proc.stderr or '')[-300:].strip()}", file=sys.stderr)
        return 1
    exe = prefix / "node_modules" / ".bin" / "t3code"
    version = (run([str(exe), "--version"], env=dict(env), capture_output=True, text=True).stdout or "").strip()
    if version != PINNED_VERSION:
        print(f"installed t3code reports {version or 'nothing'}, not {PINNED_VERSION}", file=sys.stderr)
        return 1
    (prefix / "LOCK.sha256").write_text(hashlib.sha256((prefix / "package-lock.json").read_bytes()).hexdigest() + "\n")
    print(f"installed {spec} at {exe}")
    return 0


# MARK: - Guards

def settings_agree(worktree: Path, agent_name: Optional[str]) -> bool:
    """Does the worktree's ``.claude/settings.json`` register ``triage_deny`` and carry the agent (``"agent": "orchestrator"``) that
    ``claude -p --agent`` would have chosen? A worktree cut before the hooks existed answers no, and the runner uses the claude path."""
    try:
        settings = json.loads((worktree / ".claude" / "settings.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return False
    if not isinstance(settings, dict) or "triage_deny" not in json.dumps((settings.get("hooks") or {}).get("PreToolUse") or []):
        return False
    return not agent_name or settings.get("agent") == agent_name


def trusted_hashes(trusted: Path) -> Dict[str, str]:
    """The guard files' hashes in the trusted checkout; raises ``LaunchError`` when one is missing there."""
    session = session_module()
    found = session.hash_hooks(trusted)
    if set(found) != set(session.GUARD_FILES):
        raise LaunchError(f"the trusted checkout {trusted} lacks guard files: {sorted(set(session.GUARD_FILES) - set(found))}")
    return found


def tree_digests(repo: Path) -> Dict[str, str]:
    """``{relative path: sha256}`` of every file under ``tools/hooks/`` (symlinks recorded by target, caches skipped) and of
    ``.claude/settings.json``. A file added next to the hooks counts: a sibling ``json.py`` shadows the stdlib for a hook."""
    out: Dict[str, str] = {}
    base = Path(repo)

    def add(path: Path) -> None:
        rel = str(path.relative_to(base))
        try:
            out[rel] = "link:" + os.readlink(path) if path.is_symlink() else hashlib.sha256(path.read_bytes()).hexdigest()
        except OSError:
            out[rel] = "unreadable"

    for folder, dirs, files in os.walk(base / "tools" / "hooks"):
        dirs[:] = sorted(d for d in dirs if d != "__pycache__")  # only a __pycache__ folder is skipped: a bare json.pyc shadows json too
        for name in sorted(files) + [d for d in dirs if (Path(folder) / d).is_symlink()]:
            add(Path(folder) / name)
    if (base / ".claude" / "settings.json").exists():
        add(base / ".claude" / "settings.json")
    return out


def tree_diff(worktree: Path, expected: Mapping[str, str]) -> List[str]:
    """The paths where ``worktree`` differs from ``expected`` (:func:`tree_digests` of the trusted checkout): changed, missing or extra."""
    now = tree_digests(worktree)
    return sorted(rel for rel in set(now) | set(expected) if now.get(rel) != expected.get(rel))


def ready(agent: Mapping[str, Any], root: Path, trusted: Optional[Path] = None, env: Optional[Mapping[str, str]] = None,
          run: Callable[..., Any] = subprocess.run) -> Tuple[Optional[bool], str]:
    """The preflight: ``(True, "")`` when T3 can take a launch, ``(False, why)`` when it cannot (the tick is refused), ``(None, why)`` when
    it cannot be said (then the runner launches, as for a ``claude`` that cannot report). Checks the pinned binary and its ``--version``, then
    ``doctor`` (orchestrator protocol 2 and a CLI that matches the server), then the trusted checkout's guard files."""
    try:
        cfg = t3_config(agent)
    except LaunchError as exc:
        return False, str(exc)
    exe = executable(cfg, root)
    if not (os.path.isfile(exe) and os.access(exe, os.X_OK)):
        return False, f"t3code is not installed at {exe}; run: python3 tools/triage/hass_triage.py install-t3code"
    prefix = root.joinpath(*INSTALL_DIR)
    try:  # the install recorded its lockfile's hash; a missing record or a changed lockfile means the install is not the audited one
        if (prefix / "LOCK.sha256").read_text().strip() != hashlib.sha256((prefix / "package-lock.json").read_bytes()).hexdigest():
            return False, "the t3code lockfile changed since install-t3code; run it again"
    except OSError:
        return False, "the t3code install has no recorded lockfile hash; run: python3 tools/triage/hass_triage.py install-t3code"
    try:
        version = (run([exe, "--version"], capture_output=True, text=True, env=dict(env) if env else None).stdout or "").strip()
        report = data_of(run([exe, "--json", "doctor"], capture_output=True, text=True, env=dict(env) if env else None))
    except (OSError, subprocess.SubprocessError) as exc:
        return None, f"t3code could not be run ({type(exc).__name__})"
    if version != cfg["version"]:
        return False, f"t3code is {version or 'unknown'}, not the pinned {cfg['version']}; run install-t3code"
    checks = report.get("checks") if isinstance(report.get("checks"), dict) else {}
    if not checks:
        return None, "t3code doctor gave no report"
    if not (checks.get("orchestrationProtocol") or {}).get("ok"):
        return False, "T3 does not speak orchestration protocol 2 (t3code doctor)"
    if not (checks.get("t3Cli") or {}).get("ok"):
        return False, "the t3code CLI does not match the T3 server (t3code doctor)"
    if trusted is not None:
        try:
            trusted_hashes(trusted)
        except LaunchError as exc:
            return False, str(exc)
        if not settings_agree(trusted, agent.get("agent")):
            return False, "the trusted checkout's .claude/settings.json does not register triage_deny"
    return True, ""


# MARK: - The launch

class Launcher:
    """One T3 launch. ``run`` runs a process (``subprocess.run`` signature), ``kill`` signals one, ``sleep`` waits."""

    def __init__(self, agent: Mapping[str, Any], home: Path, root: Path, env: Mapping[str, str], run: Callable[..., Any] = subprocess.run,
                 kill: Callable[[int, int], None] = os.kill, sleep: Callable[[float], None] = time.sleep):
        self.cfg = t3_config(agent)
        self.home, self.root, self.env = home, root, dict(env)
        self.run, self.kill, self.sleep = run, kill, sleep
        self.exe = executable(self.cfg, root)

    def call(self, argv: List[str], prompt: Optional[str] = None, timeout: Optional[float] = None) -> Any:
        """Run ``argv``; a process that cannot start or runs past ``timeout`` is reported as exit 127 / 6, never raised."""
        try:
            return self.run(argv, input=prompt, capture_output=True, text=True, env=self.env, timeout=timeout)
        except subprocess.TimeoutExpired:
            return subprocess.CompletedProcess(argv, 6, "", "timed out")
        except (OSError, subprocess.SubprocessError) as exc:
            return subprocess.CompletedProcess(argv, 127, "", type(exc).__name__)

    def launch(self, *, kind: str, issue: Optional[int], role: str, worktree: Path, branch: str, session_env: Mapping[str, str],
               deny: List[str], prompt: str, log: Path, timeout: float, trusted: Path,
               on_thread: Callable[[str], None] = lambda _id: None) -> Outcome:
        """Run the session to its end. Raises ``LaunchError`` when it could not be started (a thread that may exist is interrupted and
        reaped first, and its record stays armed until the runner removes the worktree)."""
        session = session_module()
        guard_sha = trusted_hashes(trusted)
        expected = tree_digests(trusted)
        changed = tree_diff(worktree, expected)
        if changed:
            raise LaunchError(f"hooks or settings differ from the trusted checkout: {', '.join(changed[:6])}")
        record = session.build_record(kind, issue, role, worktree, branch, session_env, deny + list(self.cfg["extra_denied"]),
                                      ttl_hours=timeout / 3600 + 1, hook_sha=guard_sha)
        root = registry_root(self.home)
        try:
            written = session.write_record(record, root)  # before the handover: the first tool call is already covered
        except (OSError, ValueError) as exc:
            raise LaunchError(f"could not write the triage record: {type(exc).__name__}") from exc
        argv = handover_argv(self.exe, self.cfg, worktree)
        proc = self.call(argv, prompt=prompt, timeout=120)
        thread = (data_of(proc).get("thread") or {}).get("id") if proc.returncode == 0 else None
        if not isinstance(thread, str) or not thread:
            # T3 may still start the thread (a timed-out CLI, THREAD_START_FAILED "server-managed"): the record stays, and any thread
            # at this worktree is interrupted and reaped. Only the runner's worktree cleanup removes the record.
            found, stray = self.failed_thread(proc, worktree), False
            if found:
                self.stop(found)
                stray = self.reap(found, worktree)
            session.set_state(worktree, "ended", root)
            raise LaunchError(f"t3code handover failed (exit {proc.returncode}): {(proc.stderr or '')[:200].strip()}", stray)
        digest, with_thread, code, problem = written.digest, False, 1, ""
        try:
            log.parent.mkdir(parents=True, exist_ok=True)
            with open(log, "ab") as handle:
                handle.write((json.dumps({"type": "t3_launch", "thread": thread, "worktree": str(worktree),
                                          "command": shlex.join(argv)}) + "\n").encode())
            digest = session.write_record({**record, "thread_id": thread, "state": "running"}, root).digest
            with_thread = True
            on_thread(thread)
            code = self.supervise(thread, worktree, timeout, log)
        except Exception as exc:  # noqa: BLE001 (whatever went wrong, the thread is stopped and reaped below)
            problem = f"{type(exc).__name__}: {str(exc)[:200]}"
            self.stop(thread)
        stray = self.reap(thread, worktree)
        verdict = session.verify(worktree, thread if with_thread else None, digest, root)  # before set_state rewrites the file
        session.set_state(worktree, "ended", root)
        tampered = verdict != "ok" or bool(tree_diff(worktree, expected))
        if problem:
            print(f"t3 session {thread}: {problem}")
        return Outcome(code, thread, stray, tampered)

    def failed_thread(self, proc: Any, worktree: Path) -> Optional[str]:
        """The thread a failed handover may have left: ``error.details.threadId`` of the stderr envelope, else the newest active
        thread whose ``worktreePath`` is this worktree."""
        try:
            details = ((json.loads(proc.stderr or "") or {}).get("error") or {}).get("details") or {}
        except (ValueError, AttributeError):
            details = {}
        if isinstance(details, dict) and isinstance(details.get("threadId"), str) and details["threadId"]:
            return details["threadId"]
        return self.newest_thread(worktree)

    def newest_thread(self, worktree: Path) -> Optional[str]:
        """The newest active thread whose ``worktreePath`` is ``worktree`` (``threads list`` filters by project, not by worktree)."""
        proc = self.call([self.exe, "--json", "threads", "list", "--status", "active", "--cwd", str(worktree)], timeout=60)
        here = os.path.realpath(str(worktree))
        for thread in data_of(proc).get("threads") or []:
            if isinstance(thread, dict) and isinstance(thread.get("id"), str) and isinstance(thread.get("worktreePath"), str) \
                    and os.path.realpath(thread["worktreePath"]) == here:
                return thread["id"]
        return None

    def supervise(self, thread: str, worktree: Path, timeout: float, log: Path) -> int:
        """One blocking ``threads wait`` for the whole session. A person-needed pause is answered (a few times at most), a timeout
        interrupts. Returns the code the runner's callers expect: 0 / 1, or -9 for the timeout."""
        deadline = time.monotonic() + timeout
        answered = 0
        while True:
            left = max(1, int(deadline - time.monotonic()))
            proc = self.call(thread_argv(self.exe, "wait", thread=thread, extra=("--timeout", str(left))), timeout=left + WAIT_SLACK)
            data = data_of(proc)
            outcome = (data.get("wait") or {}).get("outcome")
            if proc.returncode == 6:
                code = self.stop(thread, -9)
                break
            if proc.returncode == 0 and outcome == "needs-attention":
                if answered >= int(self.cfg["needs_attention_retries"]):
                    code = self.stop(thread, -9)
                    break
                answered += 1
                self.answer(thread, data.get("pendingRequests"))
                continue
            code = 0 if proc.returncode == 0 and outcome in ("completed", "interrupted", "ended", "idle") else 1
            if proc.returncode != 0:  # the wait itself failed (T3 restart, socket): the turn may still run
                self.stop(thread)
            break
        self.transcript(thread, log)
        return code

    def answer(self, thread: str, pending: Any) -> None:
        """Decline an approval, answer a question with :data:`UNATTENDED` (dismissed when it takes no answer)."""
        first = pending[0] if isinstance(pending, list) and pending and isinstance(pending[0], dict) else {}
        if first.get("kind") == "approval":
            self.call(thread_argv(self.exe, "decline", thread=thread), timeout=120)
        elif self.call(thread_argv(self.exe, "answer", thread=thread, extra=("--answer", UNATTENDED)), timeout=120).returncode != 0:
            self.call(thread_argv(self.exe, "answer", thread=thread, extra=("--dismiss",)), timeout=120)

    def stop(self, thread: str, code: int = 1) -> int:
        """Interrupt the running turn (this stops the whole Claude session), then wait up to the grace for it to go idle. Returns ``code``."""
        self.call(thread_argv(self.exe, "interrupt", thread=thread), timeout=120)
        grace = int(self.cfg["interrupt_grace_seconds"])
        self.call(thread_argv(self.exe, "wait", thread=thread, extra=("--timeout", str(grace))), timeout=grace + WAIT_SLACK)
        return code

    def transcript(self, thread: str, log: Path) -> None:
        """Append the thread's full transcript to the log as one ``{"type": "t3_thread", "data": ...}`` line."""
        data = data_of(self.call(thread_argv(self.exe, "read", thread=thread, extra=("--detail", "full")), timeout=120))
        with open(log, "ab") as handle:
            handle.write((json.dumps({"type": "t3_thread", "thread": thread, "data": data}) + "\n").encode())

    # -- process cleanup: the runner cannot kill a T3 session's process group, so it finds what is left by environment and cwd

    def survivors(self, thread: str, worktree: Path) -> Optional[List[int]]:
        """Pids (other than ours) whose environment holds ``T3CODE_THREAD_ID=<thread>`` or whose cwd is inside the worktree; ``None``
        when a probe could not run (then nothing is known and the caller treats it as a survivor)."""
        found = set()
        needle = f"T3CODE_THREAD_ID={thread}"
        ps = self.call(["ps", "-A", "-E", "-ww", "-o", "pid=,command="], timeout=30)
        lsof = self.call(["lsof", "-d", "cwd", "-Fpn"], timeout=30)
        if any(p.returncode in (127, 6) or (p.returncode != 0 and not p.stdout) for p in (ps, lsof)):
            return None
        for line in (ps.stdout or "").splitlines():
            pid, _, rest = line.strip().partition(" ")
            if pid.isdigit() and any(word == needle for word in rest.split()):
                found.add(int(pid))
        base, pid = os.path.realpath(str(worktree)), None
        for line in (lsof.stdout or "").splitlines():
            if line.startswith("p") and line[1:].isdigit():
                pid = int(line[1:])
            elif line.startswith("n") and pid and (line[1:] == base or line[1:].startswith(base + os.sep)):
                found.add(pid)
        found.discard(os.getpid())
        return sorted(found)

    def reap(self, thread: str, worktree: Path) -> bool:
        """Settle and archive the thread, then terminate and confirm gone whatever carries its id or sits in the worktree.
        True when something survived SIGKILL: no landing (``stray``)."""
        self.call(thread_argv(self.exe, "settle", thread=thread), timeout=120)
        self.call(thread_argv(self.exe, "archive", thread=thread), timeout=120)
        for sig in (signal.SIGTERM, signal.SIGKILL):
            left = self.survivors(thread, worktree)
            if left is None:
                return True  # cannot look: nothing lands
            if not left:
                return False
            for pid in left:
                try:
                    self.kill(pid, sig)
                except OSError:
                    pass
            self.sleep(2)
        return self.survivors(thread, worktree) != []
