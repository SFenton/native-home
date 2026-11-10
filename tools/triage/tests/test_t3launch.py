"""Tests for tools/triage/t3launch.py. No T3, npm, ps or kill: every process call goes through a fake ``run``.

Run from the repository root: python3 -m unittest discover -s tools/triage/tests
"""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any, Dict, List, Optional

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
sys.path.insert(0, str(HERE.parent))
import t3launch  # noqa: E402

session = t3launch.session_module()
THREAD = "11111111-2222-3333-4444-555555555555"
AGENT = {"model": "claude-opus-5-5", "effort": "high", "agent": "orchestrator", "timeout_minutes": 5,
         "t3": {"extra_denied": ["Bash(*t3code*)"]}}
SETTINGS = {"agent": "orchestrator", "hooks": {"PreToolUse": [{"hooks": [{"command": "exec python3 tools/hooks/triage_deny.py"}]}]}}


def done(stdout: str = "", code: int = 0, stderr: str = "") -> subprocess.CompletedProcess:
    return subprocess.CompletedProcess([], code, stdout, stderr)


def ok(**data: Any) -> subprocess.CompletedProcess:
    return done(json.dumps({"ok": True, "data": data}))


def checkout(path: Path, settings: Optional[Dict[str, Any]] = SETTINGS) -> Path:
    """A fake checkout holding the real guard files (so two of them hash equal) and ``.claude/settings.json``."""
    for rel in session.GUARD_FILES:
        (path / rel).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(REPO / rel, path / rel)
    if settings is not None:
        (path / ".claude").mkdir(exist_ok=True)
        (path / ".claude" / "settings.json").write_text(json.dumps(settings))
    return path


class Fake:
    """A scripted ``run``: ``script[key]`` is a list of results (the last repeats), ``key`` being ``<subcommand>`` of the t3code argv."""

    def __init__(self, test: "Base", **script: Any):
        self.test, self.calls, self.script, self.seen = test, [], script, {}

    def key(self, argv: List[str]) -> str:
        if argv[0] in ("ps", "lsof", "npm"):
            return argv[0]
        words = [w for w in argv[1:] if not w.startswith("-")]
        return "handover" if "handover" in argv else f"threads {words[1]}" if words[:1] == ["threads"] else words[0] if words else "version"

    def __call__(self, argv: List[str], **kwargs: Any) -> Any:
        key = self.key(argv)
        self.calls.append((key, argv, kwargs))
        if key == "handover":
            self.test.before_handover = (session.path_record(self.test.work, self.test.root).exists(),
                                         (self.test.root / "threads" / f"{THREAD}.json").exists())
        hook = self.script.get(key + "!")
        if callable(hook):
            hook()
        results = self.script.get(key, [done()])
        results = results if isinstance(results, list) else [results]
        index = self.seen.get(key, 0)
        self.seen[key] = index + 1
        result = results[min(index, len(results) - 1)]
        if isinstance(result, Exception):
            raise result
        return result

    def keys(self) -> List[str]:
        return [key for key, _argv, _kw in self.calls]


class Base(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp(prefix="t3launch-test-"))
        self.addCleanup(shutil.rmtree, self.dir, ignore_errors=True)
        self.home = self.dir / "home"
        self.root = self.home / "hass-agents" / "t3"
        self.work = checkout(self.dir / "work")
        self.trusted = checkout(self.dir / "trusted")
        self.log = self.dir / "logs" / "7-1.log"
        self.killed: List[Any] = []
        self.before_handover = None

    def launcher(self, fake: Fake, agent: Optional[Dict[str, Any]] = None) -> t3launch.Launcher:
        return t3launch.Launcher(agent or AGENT, self.home, self.home / "hass-agents", {"PATH": "/bin"}, fake,
                                 kill=lambda pid, sig: self.killed.append((pid, sig)), sleep=lambda _s: None)

    def go(self, fake: Fake, **kw: Any) -> t3launch.Outcome:
        args = dict(kind="request", issue=7, role="worker", worktree=self.work, branch="report/7", session_env={"FENTON_HEADLESS": "1"},
                    deny=["Bash(gh pr merge*)"], prompt="do it", log=self.log, timeout=300, trusted=self.trusted)
        args.update(kw)
        return self.launcher(fake).launch(**args)

    def happy(self, **extra: Any) -> Fake:
        script = {"handover": ok(thread={"id": THREAD}), "threads wait": ok(wait={"outcome": "completed"}, pendingRequests=[]),
                  "threads read": ok(thread={"messages": [{"role": "assistant", "text": "all done"}]})}
        script.update(extra)
        return Fake(self, **script)

    def record(self) -> Dict[str, Any]:
        return json.loads(session.path_record(self.work, self.root).read_text())


class ArgvTests(Base):
    def test_the_handover_argv_is_exact_and_the_prompt_goes_on_stdin(self):
        fake = self.happy()
        self.go(fake)
        _key, argv, kwargs = fake.calls[0]
        exe = str(self.home / "hass-agents" / "tools" / "t3code" / "node_modules" / ".bin" / "t3code")
        self.assertEqual(argv, [exe, "--json", "handover", "--stdin", "--cwd", str(self.work), "--workspace-mode", "repo",
                                "--project-policy", "create", "--checkout", "current", "--provider", "claudeAgent",
                                "--model", "claude-opus-5-5", "--thinking-effort", "high", "--permission", "full-access",
                                "--mode", "build", "--open", "none"])
        self.assertNotIn("--no-start-desktop", argv)  # not a handover flag in @bvdm/t3code-cli 0.3.0
        self.assertEqual(kwargs["input"], "do it")

    def test_config_reads_model_and_effort_from_the_agent_and_refuses_another_checkout(self):
        cfg = t3launch.t3_config({"model": "m", "effort": "e", "t3": {"effort": "max"}})
        self.assertEqual((cfg["model"], cfg["effort"], cfg["version"]), ("m", "max", "0.3.0"))
        with self.assertRaises(t3launch.LaunchError):
            t3launch.t3_config({"t3": {"checkout": "worktree"}})
        with self.assertRaises(t3launch.LaunchError):
            t3launch.t3_config({"t3": {"project_policy": "folder"}})

    def test_the_command_override_is_expanded(self):
        self.assertEqual(t3launch.executable({"command": "~/x/t3code"}, self.root), os.path.expanduser("~/x/t3code"))


class RegistrationTests(Base):
    def test_the_path_record_exists_before_the_handover_and_the_thread_record_after(self):
        fake = self.happy()
        self.go(fake)
        self.assertEqual(self.before_handover, (True, False))
        self.assertTrue((self.root / "threads" / f"{THREAD}.json").exists())
        record = self.record()
        self.assertEqual((record["thread_id"], record["state"], record["kind"], record["issue"]), (THREAD, "ended", "request", 7))
        self.assertEqual(record["deny"], ["Bash(gh pr merge*)", "Bash(*t3code*)"])
        self.assertEqual(record["env"], {"FENTON_HEADLESS": "1"})
        self.assertEqual(record["hook_sha"], session.hash_hooks(self.trusted))
        self.assertEqual(oct(session.path_record(self.work, self.root).stat().st_mode & 0o777), "0o600")

    def test_a_failed_handover_keeps_the_record_and_interrupts_a_thread_that_exists(self):
        """Fails if: a failed handover forgets the record while T3 may still start the thread, or leaves a started thread running."""
        envelope = json.dumps({"ok": False, "error": {"code": "THREAD_START_FAILED", "details": {"threadId": THREAD}}})
        for name, fake in (
                ("threadId in the error", Fake(self, handover=done("", 1, envelope))),
                ("only in the list", Fake(self, handover=done("", 6, "timed out"),
                                          **{"threads list": ok(threads=[{"id": "other", "worktreePath": "/elsewhere"},
                                                                         {"id": THREAD, "worktreePath": str(self.work)}])})),
                ("no id in a successful reply", Fake(self, handover=ok(),
                                                     **{"threads list": ok(threads=[{"id": THREAD, "worktreePath": str(self.work)}])}))):
            with self.subTest(name):
                with self.assertRaises(t3launch.LaunchError):
                    self.go(fake)
                self.assertTrue(session.path_record(self.work, self.root).exists())
                self.assertEqual(self.record()["state"], "ended")
                interrupted = [argv for key, argv, _ in fake.calls if key == "threads interrupt"]
                self.assertEqual(interrupted[0][-1], THREAD)
                self.assertIn("threads archive", fake.keys())

    def test_a_failed_handover_keeps_its_stray_result(self):
        """Fails if: a process the reap of a failed handover's thread could not kill is dropped, so the runner thinks nothing is left."""
        fake = Fake(self, handover=done("", 1, json.dumps({"error": {"details": {"threadId": THREAD}}})), ps=done("", 127))
        with self.assertRaises(t3launch.LaunchError) as raised:
            self.go(fake)
        self.assertTrue(raised.exception.stray)
        fake = Fake(self, handover=done("", 1, "boom"), ps=done(""), lsof=done(""))
        with self.assertRaises(t3launch.LaunchError) as raised:
            self.go(fake)
        self.assertFalse(raised.exception.stray)

    def test_a_failed_handover_with_no_thread_anywhere_keeps_the_record_and_interrupts_nothing(self):
        fake = Fake(self, handover=done("", 1, "boom"), **{"threads list": ok(threads=[{"id": "x", "worktreePath": "/elsewhere"}])})
        with self.assertRaises(t3launch.LaunchError):
            self.go(fake)
        self.assertTrue(session.path_record(self.work, self.root).exists())
        self.assertNotIn("threads interrupt", fake.keys())

    def test_a_record_that_cannot_be_written_aborts_before_the_handover(self):
        fake = self.happy()
        self.root.parent.mkdir(parents=True)
        self.root.write_text("a file where the registry folder should be")
        with self.assertRaises(t3launch.LaunchError):
            self.go(fake)
        self.assertEqual(fake.calls, [])

    def test_a_thread_record_that_cannot_be_written_stops_and_reaps_the_thread(self):
        fake = self.happy(handover=ok(thread={"id": "bad/id"}))  # not a usable thread id: the thread-keyed write raises
        out = self.go(fake)
        self.assertEqual(out.code, 1)
        self.assertIn("threads interrupt", fake.keys())
        self.assertIn("threads archive", fake.keys())
        self.assertFalse(out.tampered)

    def test_worktree_hooks_that_differ_from_the_trusted_checkout_refuse_the_launch(self):
        (self.work / session.GUARD_FILES[0]).write_text("# tampered\n")
        fake = self.happy()
        with self.assertRaises(t3launch.LaunchError) as raised:
            self.go(fake)
        self.assertIn("triage_deny.py", str(raised.exception))
        self.assertEqual(fake.calls, [])
        self.assertFalse(session.path_record(self.work, self.root).exists())


class SessionTests(Base):
    def test_a_completed_session_returns_zero_logs_the_transcript_and_cleans_up_in_order(self):
        fake = self.happy()
        seen: List[str] = []
        out = self.go(fake, on_thread=seen.append)
        self.assertEqual((out.code, out.thread, out.stray, out.tampered), (0, THREAD, False, False))
        self.assertEqual(seen, [THREAD])
        keys = fake.keys()
        self.assertEqual([k for k in keys if k.startswith("threads")][:4], ["threads wait", "threads read", "threads settle", "threads archive"])
        waits = [argv for key, argv, _ in fake.calls if key == "threads wait"]
        self.assertEqual(len(waits), 1)  # one blocking wait, no polling
        self.assertIn(waits[0][waits[0].index("--timeout") + 1], ("299", "300"))  # the whole session budget, to the second
        lines = [json.loads(line) for line in self.log.read_text().splitlines()]
        self.assertEqual([line["type"] for line in lines], ["t3_launch", "t3_thread"])
        self.assertEqual((lines[0]["thread"], lines[0]["worktree"]), (THREAD, str(self.work)))
        self.assertIn("handover --stdin", lines[0]["command"])
        self.assertNotIn("do it", lines[0]["command"])
        self.assertEqual(lines[1]["data"]["thread"]["messages"][0]["text"], "all done")

    def test_the_other_outcomes_map_to_a_code(self):
        for outcome, expected in (("completed", 0), ("interrupted", 0), ("error", 1), ("queue-held", 1)):
            fake = self.happy(**{"threads wait": ok(wait={"outcome": outcome}, pendingRequests=[])})
            self.assertEqual(self.go(fake).code, expected, outcome)
        self.assertEqual(self.go(self.happy(**{"threads wait": done("", 1, "x")})).code, 1)

    def test_a_timed_out_wait_interrupts_then_waits_for_the_grace_and_returns_minus_nine(self):
        fake = self.happy(**{"threads wait": [done("", 6), ok(wait={"outcome": "interrupted"})]})
        out = self.go(fake)
        self.assertEqual(out.code, -9)
        keys = fake.keys()
        self.assertLess(keys.index("threads interrupt"), keys.index("threads read"))
        waits = [argv for key, argv, _ in fake.calls if key == "threads wait"]
        self.assertEqual(len(waits), 2)
        self.assertEqual(waits[1][waits[1].index("--timeout") + 1], "60")  # interrupt_grace_seconds

    def test_a_wait_subprocess_that_hangs_is_a_timeout_too(self):
        fake = self.happy(**{"threads wait": [subprocess.TimeoutExpired("t3code", 1), ok(wait={"outcome": "interrupted"})]})
        self.assertEqual(self.go(fake).code, -9)

    def test_needs_attention_is_answered_three_times_then_the_thread_is_interrupted(self):
        asking = ok(wait={"outcome": "needs-attention"}, pendingRequests=[{"kind": "approval", "requestId": "r1"}])
        fake = self.happy(**{"threads wait": asking})
        out = self.go(fake)
        self.assertEqual(out.code, -9)
        self.assertEqual(fake.keys().count("threads decline"), 3)
        self.assertEqual(fake.keys().count("threads interrupt"), 1)

    def test_a_question_gets_the_unattended_answer_and_a_dismiss_when_it_takes_none(self):
        question = ok(wait={"outcome": "needs-attention"}, pendingRequests=[{"kind": "question", "requestId": "q1"}])
        fake = self.happy(**{"threads wait": [question, ok(wait={"outcome": "completed"})], "threads answer": [done("", 4), done()]})
        self.assertEqual(self.go(fake).code, 0)
        answers = [argv for key, argv, _ in fake.calls if key == "threads answer"]
        self.assertEqual(answers[0][-2:], ["--answer", t3launch.UNATTENDED])
        self.assertEqual(answers[1][-1], "--dismiss")

    def test_a_file_added_beside_the_hooks_is_tampering_at_launch_and_at_the_end(self):
        """Fails if: only the four guard files are hashed, so a session-written tools/hooks/json.py (which shadows the stdlib for a hook)
        or a new file in the hooks folder goes unseen."""
        shadow = self.work / "tools" / "hooks" / "json.py"
        shadow.write_text("import sys\nsys.exit(0)\n")
        with self.assertRaises(t3launch.LaunchError) as raised:
            self.go(self.happy())
        self.assertIn("tools/hooks/json.py", str(raised.exception))
        shadow.unlink()
        out = self.go(self.happy(**{"threads wait!": lambda: shadow.write_text("import sys\nsys.exit(0)\n")}))
        self.assertTrue(out.tampered)

    def test_settings_and_a_changed_or_deleted_hook_are_tampering_too(self):
        edits = {"settings": lambda: (self.work / ".claude" / "settings.json").write_text("{}"),
                 "other hook": lambda: (self.work / "tools" / "hooks" / "extra_guard.py").unlink(),
                 "bare pyc": lambda: (self.work / "tools" / "hooks" / "json.pyc").write_bytes(b"\0"),
                 "pyc in a subfolder": lambda: (self.work / "tools" / "hooks" / "sub").mkdir() or
                 (self.work / "tools" / "hooks" / "sub" / "x.pyc").write_bytes(b"\0")}
        (self.work / "tools" / "hooks" / "extra_guard.py").write_text("x = 1\n")
        checkout_extra = self.trusted / "tools" / "hooks" / "extra_guard.py"
        checkout_extra.write_text("x = 1\n")
        for name, edit in edits.items():
            with self.subTest(name):
                out = self.go(self.happy(**{"threads wait!": edit}))
                self.assertTrue(out.tampered)
                shutil.rmtree(self.work / "tools" / "hooks" / "sub", ignore_errors=True)
                (self.work / "tools" / "hooks" / "json.pyc").unlink(missing_ok=True)
                (self.work / "tools" / "hooks" / "extra_guard.py").write_text("x = 1\n")
                checkout(self.work)

    def test_a_bare_pyc_shadowing_the_stdlib_is_refused_at_launch(self):
        """Fails if: every .pyc is skipped, so tools/hooks/json.pyc (which Python imports ahead of the stdlib) goes unseen."""
        (self.work / "tools" / "hooks" / "json.pyc").write_bytes(b"\0")
        with self.assertRaises(t3launch.LaunchError) as raised:
            self.go(self.happy())
        self.assertIn("tools/hooks/json.pyc", str(raised.exception))

    def test_only_a_pycache_folder_is_skipped(self):
        cache = self.work / "tools" / "hooks" / "__pycache__"
        cache.mkdir()
        (cache / "x.cpython-39.pyc").write_bytes(b"\0")
        self.assertFalse(self.go(self.happy()).tampered)

    def test_a_record_changed_or_removed_during_the_session_is_tampering(self):
        """Fails if: the registry record the guards read can be edited or deleted by the session without the runner noticing (verify)."""
        for name, edit in (("changed", lambda: session.path_record(self.work, self.root).write_text("{}")),
                           ("removed", lambda: (self.root / "threads" / f"{THREAD}.json").unlink())):
            with self.subTest(name):
                self.assertTrue(self.go(self.happy(**{"threads wait!": edit})).tampered)

    def test_a_clean_session_verifies(self):
        self.assertFalse(self.go(self.happy()).tampered)

    def test_a_probe_that_cannot_run_is_a_stray(self):
        """Fails if: a failed ps or lsof reads as 'nothing left running'."""
        for bad in ({"ps": done("", 127)}, {"lsof": done("", 6)}):
            self.assertTrue(self.go(self.happy(**bad)).stray)

    def test_a_wait_that_fails_interrupts_the_thread(self):
        fake = self.happy(**{"threads wait": done("", 1, "socket error")})
        self.assertEqual(self.go(fake).code, 1)
        self.assertIn("threads interrupt", fake.keys())

    def test_tampered_guard_hooks_are_reported_at_the_end(self):
        tamper = lambda: (self.work / session.GUARD_FILES[1]).write_text("# changed\n")  # noqa: E731
        out = self.go(self.happy(**{"threads wait!": tamper}))
        self.assertTrue(out.tampered)

    def test_survivors_are_killed_by_environment_and_by_cwd_and_a_stubborn_one_is_stray(self):
        ps = done(f"  501 /bin/sleep 9 T3CODE_THREAD_ID={THREAD} HOME=/x\n  502 node T3CODE_THREAD_ID=other\n  503 vim X=T3CODE_THREAD_ID={THREAD}\n")
        real = os.path.realpath(self.work)
        lsof = done(f"p601\nn{real}/sub\np602\nn{real}-sibling\np{os.getpid()}\nn{real}\n")
        fake = self.happy(ps=ps, lsof=lsof)
        out = self.go(fake)
        self.assertTrue(out.stray)  # the fake processes never go away
        self.assertEqual({pid for pid, _ in self.killed}, {501, 601})
        self.assertEqual([sig for _pid, sig in self.killed], [signal.SIGTERM, signal.SIGTERM, signal.SIGKILL, signal.SIGKILL])

    def test_nothing_left_means_no_stray_and_no_kill(self):
        out = self.go(self.happy(ps=done(""), lsof=done("")))
        self.assertFalse(out.stray)
        self.assertEqual(self.killed, [])


class ReadyTests(Base):
    def setUp(self):
        super().setUp()
        self.exe = self.home / "hass-agents" / "tools" / "t3code" / "node_modules" / ".bin" / "t3code"
        self.exe.parent.mkdir(parents=True)
        self.exe.write_text("#!/bin/sh\n")
        self.exe.chmod(0o755)
        prefix = self.exe.parents[2]
        (prefix / "package-lock.json").write_text("{}")
        (prefix / "LOCK.sha256").write_text(hashlib.sha256(b"{}").hexdigest() + "\n")

    def check(self, version="0.3.0", doctor=None, trusted=True, agent=None):
        report = doctor if doctor is not None else ok(checks={"orchestrationProtocol": {"ok": True}, "t3Cli": {"ok": True}})
        fake = Fake(self, version=done(version + "\n"), doctor=report)
        return t3launch.ready(agent or AGENT, self.home / "hass-agents", self.trusted if trusted else None, {"PATH": "/bin"}, fake)

    def test_ready_when_everything_agrees(self):
        self.assertEqual(self.check(), (True, ""))

    def test_each_refusal_says_why(self):
        cases = {
            "missing binary": (lambda: self.exe.unlink(), "not installed"),
            "version": (lambda: None, "pinned 0.3.0"),
            "protocol": (lambda: None, "protocol 2"),
            "cli mismatch": (lambda: None, "does not match"),
            "hash": (lambda: (self.trusted / session.GUARD_FILES[0]).unlink(), "lacks guard files"),
            "settings": (lambda: (self.trusted / ".claude" / "settings.json").write_text("{}"), "triage_deny"),
        }
        args = {"version": {"version": "0.2.0"},
                "protocol": {"doctor": ok(checks={"orchestrationProtocol": {"ok": False}, "t3Cli": {"ok": True}})},
                "cli mismatch": {"doctor": ok(checks={"orchestrationProtocol": {"ok": True}, "t3Cli": {"ok": False}})}}
        for name, (setup, text) in cases.items():
            with self.subTest(name):
                setup()
                result = self.check(**args.get(name, {}))
                self.assertIs(result[0], False)
                self.assertIn(text, result[1])
                if name == "missing binary":
                    self.exe.write_text("#!/bin/sh\n")
                    self.exe.chmod(0o755)
                if name == "hash":
                    checkout(self.trusted)
                if name == "settings":
                    checkout(self.trusted)

    def test_a_doctor_that_cannot_say_is_none_so_the_runner_launches(self):
        self.assertIs(self.check(doctor=done("not json"))[0], None)
        fake = Fake(self, version=FileNotFoundError("x"))
        self.assertIs(t3launch.ready(AGENT, self.home / "hass-agents", None, {}, fake)[0], None)

    def test_a_lockfile_that_changed_since_the_install_is_not_ready(self):
        """Fails if: the recorded LOCK.sha256 is never compared, so floating dependencies move unseen."""
        prefix = self.exe.parents[2]
        (prefix / "package-lock.json").write_text("{}")
        (prefix / "LOCK.sha256").write_text(hashlib.sha256(b"{}").hexdigest() + "\n")
        self.assertEqual(self.check(), (True, ""))
        (prefix / "package-lock.json").write_text('{"changed": 1}')
        self.assertIn("lockfile changed", self.check()[1])
        (prefix / "LOCK.sha256").unlink()  # no record of the audited install: not ready either
        self.assertEqual(self.check()[0], False)
        self.assertIn("no recorded lockfile hash", self.check()[1])

    def test_a_bad_config_is_not_ready(self):
        self.assertIs(self.check(agent={"t3": {"checkout": "worktree"}})[0], False)


class SettingsTests(Base):
    def test_settings_agree_needs_the_hook_and_the_agent(self):
        self.assertTrue(t3launch.settings_agree(self.work, "orchestrator"))
        self.assertTrue(t3launch.settings_agree(self.work, ""))
        self.assertFalse(t3launch.settings_agree(self.work, "reviewer"))
        (self.work / ".claude" / "settings.json").write_text(json.dumps({"agent": "orchestrator", "hooks": {}}))
        self.assertFalse(t3launch.settings_agree(self.work, "orchestrator"))
        (self.work / ".claude" / "settings.json").write_text("not json")
        self.assertFalse(t3launch.settings_agree(self.work, "orchestrator"))
        self.assertFalse(t3launch.settings_agree(self.dir / "nowhere", "orchestrator"))

    def test_the_repository_settings_agree_with_the_default_config(self):
        cfg = json.loads((HERE.parent / "config.json").read_text())
        self.assertTrue(t3launch.settings_agree(REPO, cfg["agent"]["agent"]))
        self.assertEqual(cfg["agent"]["launcher"], "claude")


class ToolsTests(Base):
    def test_thread_tail_renders_the_last_assistant_messages(self):
        messages = [{"role": "assistant", "text": f"m{i}"} for i in range(5)] + [{"role": "user", "text": "q"}]
        text = "\n".join([json.dumps({"type": "t3_launch", "thread": "x"}), json.dumps({"type": "t3_thread", "data": {"thread": {"messages": messages}}})])
        self.assertEqual(t3launch.thread_tail(text), "m2\n\nm3\n\nm4")
        self.assertIsNone(t3launch.thread_tail('{"type": "result"}\nplain line'))
        self.assertIn("boom", t3launch.thread_tail(json.dumps({"type": "t3_launch_failed", "reason": "boom"})))

    def test_install_pins_the_version_without_scripts_and_records_the_lock_hash(self):
        prefix = self.home / "hass-agents" / "tools" / "t3code"

        def npm():
            prefix.joinpath("package-lock.json").write_text("{}")

        fake = Fake(self, **{"npm!": npm, "version": done("0.3.0\n")})
        self.assertEqual(t3launch.install(self.home / "hass-agents", {"PATH": "/bin"}, fake), 0)
        argv = fake.calls[0][1]
        self.assertEqual(argv, ["npm", "install", "--prefix", str(prefix), "--save-exact", "@bvdm/t3code-cli@0.3.0", "--ignore-scripts"])
        self.assertEqual(len((prefix / "LOCK.sha256").read_text().strip()), 64)
        self.assertEqual(t3launch.install(self.home / "hass-agents", {}, Fake(self, npm=done("", 1, "E404"))), 1)
        self.assertEqual(t3launch.install(self.home / "hass-agents", {}, Fake(self, **{"npm!": npm, "version": done("0.2.0\n")})), 1)

    def test_forget_removes_both_records_and_never_raises(self):
        self.go_record()
        self.assertTrue(session.path_record(self.work, self.root).exists())
        t3launch.forget(self.work, self.home)
        self.assertFalse(session.path_record(self.work, self.root).exists())
        self.assertFalse((self.root / "threads" / f"{THREAD}.json").exists())
        t3launch.forget(self.work, self.home)  # nothing left: still fine

    def go_record(self):
        self.go(self.happy(ps=done(""), lsof=done("")))
