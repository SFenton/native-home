"""Agent-roster tooling: orchestrator_guard, research_write_guard, subagent_report, agent_model (new types), tasks.py."""

import io
import json
import re
import os
import subprocess
import sys
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import mock

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS / "hooks"))
sys.path.insert(0, str(TOOLS))
import agent_model  # noqa: E402
import orchestrator_guard  # noqa: E402
import research_write_guard  # noqa: E402
import subagent_report  # noqa: E402
import tasks  # noqa: E402


def run(module, payload):
    out, err = io.StringIO(), io.StringIO()
    with mock.patch.object(sys, "stdin", io.StringIO(json.dumps(payload))), redirect_stdout(out), redirect_stderr(err):
        status = module.main()
    return status, out.getvalue(), err.getvalue()


def bash(command, **extra):
    """A Bash payload as the orchestrator's main thread sends it (``agent_type`` overridable)."""
    return {"tool_name": "Bash", "tool_input": {"command": command}, "agent_type": "orchestrator", **extra}


class OrchestratorGuardTests(unittest.TestCase):
    def test_blocks_builds_tests_and_simulators(self):
        for command in ["xcodebuild -scheme X test", "cd apple && swift test --filter A", "swift build",
                        "tools/ios_uitest.sh --only iphone", "python3 tools/devcap.py run --sim U -- ls",
                        "tools/apple_coverage.sh", "xcrun simctl boot U", "xcrun simctl install booted a.app",
                        "xcrun simctl launch booted x", "tools/ios_scrollcost_perf.sh", "tools/uikit_build.sh",
                        "tools/uikit_shot.sh x", "bash tools/ios_uitest.sh", "bash -c 'swift test'",
                        "FOO=1 timeout 5 xcodebuild build", "ls && tools/uikit_build.sh", "env tools/apple_coverage.sh",
                        "tools/bg_run.py build -- xcodebuild -scheme X build",
                        "python3 tools/bg_run.py t --timeout 600 -- swift test",
                        "tools/bg_run.py ui -- tools/ios_uitest.sh --only ipad",
                        "tools/bg_run.py x --dir build/r -- bash -c 'swift build'",
                        "timeout 9 tools/bg_run.py x -- python3 tools/devcap.py run --sim U -- ls",
                        "echo a | xargs xcodebuild"]:
            with self.subTest(command=command):
                status, _, err = run(orchestrator_guard, bash(command))
                self.assertEqual(status, 2)
                self.assertIn("Verifier", err)

    def test_allows_planning_commands(self):
        for command in ["git status", "tools/tasks.py check T", "tools/pr_land.sh 12", "grep -n swift test.md",
                        "xcrun simctl list", "swift --version", "echo 'xcodebuild' > note.txt",
                        "tools/bg_run.py x -- true", "tools/bg_run.py x --timeout 5 -- git status",
                        "tools/bg_run.py x", "python3 tools/bg_run.py rev -- python3 -m unittest discover", "cat <<'EOF'\nxcodebuild\nEOF"]:
            with self.subTest(command=command):
                self.assertEqual(run(orchestrator_guard, bash(command))[0], 0)

    def test_override_comment_only_when_real(self):
        self.assertEqual(run(orchestrator_guard, bash("swift build  # orch-ok: one-off compile check"))[0], 0)
        self.assertEqual(run(orchestrator_guard, bash("swift build 'x # orch-ok: no'"))[0], 2)
        self.assertEqual(run(orchestrator_guard, bash("swift build  # orch-ok:"))[0], 2)

    def test_other_agents_tools_and_bad_input_pass(self):
        self.assertEqual(run(orchestrator_guard, bash("swift build", agent_type="verifier"))[0], 0)
        self.assertEqual(run(orchestrator_guard, bash("swift build", agent_type="orchestrator"))[0], 2)
        self.assertEqual(run(orchestrator_guard, bash("xcodebuild -version", agent_type="orchestrator", agent_id="a1"))[0], 2)
        for kind in (None, "coder", ""):
            self.assertEqual(run(orchestrator_guard, bash("xcodebuild -version", agent_type=kind))[0], 0)
        self.assertEqual(run(orchestrator_guard, {"tool_name": "Bash", "tool_input": {"command": "xcodebuild -version"}})[0], 0)
        self.assertEqual(run(orchestrator_guard, {"tool_name": "Read", "tool_input": {}})[0], 0)
        with mock.patch.object(sys, "stdin", io.StringIO("no")):
            self.assertEqual(orchestrator_guard.main(), 0)


class ResearchWriteGuardTests(unittest.TestCase):
    def setUp(self):
        self.tmp = TemporaryDirectory()
        self.root = os.path.realpath(self.tmp.name)
        subprocess.run(["git", "init", "-q", self.root], check=True)

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, path, tool="Write", **extra):
        return run(research_write_guard, {"tool_name": tool, "cwd": self.root, "tool_input": {"file_path": path}, **extra})

    def test_allows_notes_and_memory(self):
        for path in ["build/research/x.md", f"{self.root}/build/research/sub/y.md",
                     ".claude/agent-memory/researcher/MEMORY.md"]:
            with self.subTest(path=path):
                self.assertEqual(self.write(path)[0], 0)

    def test_blocks_everything_else(self):
        for path in ["apple/Sources/A.swift", ".agents/README.md", "build/research", "build/research/../../x.md",
                     ".claude/agent-memory/coder/x.md", "/tmp/x.md", "build/researchers/x.md"]:
            with self.subTest(path=path):
                status, _, err = self.write(path, tool="Edit", agent_type="researcher")
                self.assertEqual(status, 2)
                self.assertIn("build/research", err)

    def test_other_agents_and_tools_pass(self):
        self.assertEqual(self.write("apple/A.swift", agent_type="coder")[0], 0)
        self.assertEqual(self.write("apple/A.swift")[0], 0)
        self.assertEqual(self.write("apple/A.swift", agent_type=None)[0], 0)
        self.assertEqual(self.write("apple/A.swift", agent_type="researcher")[0], 2)
        self.assertEqual(self.write("apple/A.swift", agent_type="researcher", agent_id="a1")[0], 2)
        self.assertEqual(run(research_write_guard, {"tool_name": "Bash", "tool_input": {}})[0], 0)
        self.assertEqual(run(research_write_guard, {"tool_name": "Write", "tool_input": {}})[0], 0)
        with mock.patch.object(sys, "stdin", io.StringIO("no")):
            self.assertEqual(research_write_guard.main(), 0)


class RoleGuardWiringTests(unittest.TestCase):
    ROOT = TOOLS.parent

    def test_settings_registers_both_guards(self):
        hooks = json.loads((self.ROOT / ".claude/settings.json").read_text())["hooks"]["PreToolUse"]
        by = {h["matcher"]: json.dumps(h) for h in hooks}
        self.assertIn("orchestrator_guard.py", by["Bash"])
        self.assertIn("research_write_guard.py", by["Edit|Write|MultiEdit|NotebookEdit"])

    def test_every_session_starts_as_the_orchestrator(self):
        # Owner, 2026-11-03: sessions in this repo run through the orchestrator without `--agent`; an explicit `--agent` still
        # wins (the runner's reviewer). The allow-list is the planning set plus what an interactive main thread needs; it never
        # holds Monitor (a shell path the Bash hooks do not see) or MCP tools, and the headless worker is denied Artifact.
        settings = json.loads((self.ROOT / ".claude/settings.json").read_text())
        self.assertEqual(settings.get("agent"), "orchestrator")
        head = (self.ROOT / ".claude/agents/orchestrator.md").read_text().split("---")[1]
        line = re.search(r"(?m)^tools: (.*)$", head)
        self.assertIsNotNone(line)
        tools = {t.strip() for t in line.group(1).split(",")}
        self.assertTrue({"Agent", "Bash", "Artifact", "AskUserQuestion", "ToolSearch"} <= tools)
        self.assertFalse({t for t in tools if t == "Monitor" or t.startswith("mcp__") or "*" in t})
        triage = json.loads((self.ROOT / "tools/triage/config.json").read_text())["agent"]
        self.assertTrue({"Artifact", "ArtifactComments", "ArtifactData"} <= set(triage["disallowed_tools"]))

    def test_frontmatter_has_no_hooks(self):
        for name in ("orchestrator", "researcher"):
            head = (self.ROOT / f".claude/agents/{name}.md").read_text().split("---")[1]
            self.assertNotIn("hooks:", head)


GOOD = 'Done.\n```status\n{"status": "done", "task": "T", "summary": "ok", "acceptance": {"a1": "pass"}}\n```\n'


def stop(message, active=False, kind="coder"):
    return run(subagent_report, {"agent_type": kind, "last_assistant_message": message, "stop_hook_active": active})


class SubagentReportTests(unittest.TestCase):
    def test_good_block_passes(self):
        status, out, _ = stop(GOOD)
        self.assertEqual((status, out), (0, ""))

    def test_missing_or_bad_block_blocks_once(self):
        for message in ["all done", "```status\nnot json\n```", '```status\n{"status": "weird"}\n```', "", "```json\n{}\n```"]:
            with self.subTest(message=message[:20]):
                _, out, _ = stop(message)
                self.assertEqual(json.loads(out)["decision"], "block")
                _, out, err = stop(message, active=True)
                self.assertEqual(out, "")
                self.assertIn("allowing the stop", err)

    def test_done_with_a_failing_check_blocks_once(self):
        bad = GOOD.replace('"pass"', '"fail"')
        self.assertIn("fail", json.loads(stop(bad)[1])["reason"])
        self.assertEqual(stop(bad, active=True)[1], "")

    def test_blocked_with_failures_and_last_block_wins(self):
        blocked = '```status\n{"status": "blocked", "acceptance": {"a1": "fail"}}\n```'
        self.assertEqual(stop(blocked)[1], "")
        self.assertEqual(stop(GOOD.replace('"pass"', '"fail"') + "\n" + GOOD)[1], "")

    def _blocked(self, reason=None, dirty=25, kind="coder", active=False):
        body = {"status": "blocked", "task": "T", "summary": "s"}
        if reason:
            body["blocked_reason"] = reason
        message = "```status\n" + json.dumps(body) + "\n```"
        with mock.patch.object(subagent_report, "dirty_count", return_value=dirty):
            return run(subagent_report, {"agent_type": kind, "cwd": "/wt", "stop_hook_active": active,
                                         "last_assistant_message": message})

    def test_blocked_and_dirty_without_reason_is_sent_back_once(self):
        out = self._blocked()[1]
        self.assertIn("commit your work (WIP) before handing back", json.loads(out)["reason"])
        self.assertEqual(self._blocked(active=True)[1], "")

    def test_dirty_send_back_names_the_waiting_bg_option_and_the_reprint(self):
        reason = json.loads(self._blocked()[1])["reason"]
        self.assertIn("waiting_bg:", reason)
        self.assertIn("Then print the status block again", reason)

    def test_payload_cwd_reaches_the_dirty_count(self):
        with mock.patch.object(subagent_report, "dirty_count", return_value=25) as count:
            run(subagent_report, {"agent_type": "coder", "cwd": "/the/worktree",
                                  "last_assistant_message": '```status\n{"status": "blocked"}\n```'})
        count.assert_called_once_with("/the/worktree")

    def test_blocked_and_dirty_waiting_bg_passes(self):
        self.assertEqual(self._blocked("waiting_bg: unit")[1], "")

    def test_blocked_and_clean_passes(self):
        self.assertEqual(self._blocked(dirty=3)[1], "")
        self.assertEqual(self._blocked(dirty=20)[1], "")

    def test_done_and_dirty_passes(self):
        with mock.patch.object(subagent_report, "dirty_count", return_value=99):
            self.assertEqual(run(subagent_report, {"agent_type": "coder", "cwd": "/wt",
                                                   "last_assistant_message": GOOD})[1], "")

    def test_dirty_check_is_for_coders_only(self):
        self.assertEqual(self._blocked(kind="verifier")[1], "")

    def test_a_directory_that_is_not_a_repo_counts_zero(self):
        with TemporaryDirectory() as d:
            self.assertEqual(subagent_report.dirty_count(d), 0)

    def test_dirty_count_counts_status_lines(self):
        with TemporaryDirectory() as d:
            subprocess.run(["git", "init", "-q", d], check=True)
            for n in range(3):
                open(os.path.join(d, f"f{n}"), "w").close()
            self.assertEqual(subagent_report.dirty_count(d), 3)
            self.assertEqual(subagent_report.dirty_count(""), 0)
            self.assertEqual(subagent_report.dirty_count(os.path.join(d, "missing")), 0)

    def test_only_roster_agents_are_judged(self):
        for kind in ("Explore", "", "claude", "general-purpose", "web-fetch", "some-plugin:agent"):
            with self.subTest(kind=kind):
                self.assertEqual(stop("nothing", kind=kind)[1], "")
        for kind in sorted(subagent_report.ROSTER):
            with self.subTest(kind=kind):
                self.assertEqual(json.loads(stop("nothing", kind=kind)[1])["decision"], "block")
                self.assertEqual(stop(GOOD, kind=kind)[1], "")

    def test_every_roster_agent_file_ends_with_the_status_block(self):
        agents = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".claude", "agents")
        for kind in sorted(subagent_report.ROSTER):
            with self.subTest(kind=kind), open(os.path.join(agents, f"{kind}.md")) as f:
                self.assertIn("status", f.read().split("## Ending")[-1])

    def test_bad_input_passes(self):
        with mock.patch.object(sys, "stdin", io.StringIO("no")):
            self.assertEqual(subagent_report.main(), 0)


class AgentModelRosterTests(unittest.TestCase):
    def spawn(self, kind, prompt="go"):
        return run(agent_model, {"tool_name": "Agent", "tool_input": {"subagent_type": kind, "prompt": prompt}})[0]

    def test_reviewer_needs_opus_ok(self):
        self.assertEqual(self.spawn("reviewer"), 2)
        self.assertEqual(self.spawn("reviewer", "opus-ok: final review"), 0)

    def test_cheap_and_fable_roles_pass(self):
        for kind in ("researcher", "verifier", "steward", "coder", "menial", "designer"):
            self.assertEqual(self.spawn(kind), 0)


class TasksTests(unittest.TestCase):
    def setUp(self):
        self.tmp = TemporaryDirectory()
        patch = mock.patch.dict(os.environ, {"TASKS_DIR": str(Path(self.tmp.name) / "tasks")})
        patch.start()
        self.addCleanup(patch.stop)
        self.addCleanup(self.tmp.cleanup)
        self.evidence = Path(self.tmp.name) / "shot.png"
        self.evidence.write_text("x")

    def cli(self, *argv):
        out = io.StringIO()
        with redirect_stdout(out):
            code = tasks.main(list(argv))
        return code, out.getvalue()

    def make(self):
        self.cli("new", "T-1", "--intake", "issue 1", "--level", "L1", "--brief", "b.md", "--check", "one", "--check", "two")

    def test_new_creates_a_schema_shaped_entry(self):
        self.make()
        entry = json.loads(self.cli("show", "T-1")[1])
        schema = json.loads((TOOLS.parent / "contracts" / "task-ledger.schema.json").read_text())
        self.assertEqual(set(entry), set(schema["required"]))
        self.assertEqual([c["id"] for c in entry["acceptance"]], ["a1", "a2"])
        self.assertEqual(entry["status"], "new")
        self.assertFalse(any(c["passes"] for c in entry["acceptance"]))

    def test_new_records_the_route_when_given(self):
        self.cli("new", "T-2", "--intake", "i", "--level", "L0", "--brief", "b", "--route-rule", "coder", "--route-jev", "designer")
        entry = json.loads(self.cli("show", "T-2")[1])
        self.assertEqual(entry["route"], {"rule": "coder", "jev": "designer"})
        schema = json.loads((TOOLS.parent / "contracts" / "task-ledger.schema.json").read_text())
        self.assertIn("route", schema["properties"])
        self.assertFalse(schema["properties"]["route"]["additionalProperties"])
        self.cli("new", "T-3", "--intake", "i", "--level", "L0", "--brief", "b", "--route-rule", "coder")
        self.assertIsNone(json.loads(self.cli("show", "T-3")[1])["route"]["jev"])

    def test_set_level_raise_is_recorded(self):
        self.make()
        code, _ = self.cli("set-level", "T-1", "L2", "--reason", "needs the owner's pick")
        self.assertEqual(code, 0)
        entry = json.loads(self.cli("show", "T-1")[1])
        self.assertEqual(entry["level"], "L2")
        (event,) = entry["level_history"]
        self.assertEqual((event["from"], event["to"], event["reason"]), ("L1", "L2", "needs the owner's pick"))
        self.assertRegex(event["at"], r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$")
        schema = json.loads((TOOLS.parent / "contracts" / "task-ledger.schema.json").read_text())
        self.assertIn("level_history", schema["properties"])
        self.assertLessEqual(set(entry), set(schema["properties"]))
        self.assertNotIn("level_history", schema["required"])

    def test_set_level_refuses_to_lower(self):
        self.make()
        with self.assertRaises(SystemExit) as ctx:
            self.cli("set-level", "T-1", "L0", "--reason", "x")
        self.assertIn("never lowered", str(ctx.exception))
        entry = json.loads(self.cli("show", "T-1")[1])
        self.assertEqual(entry["level"], "L1")
        self.assertNotIn("level_history", entry)

    def test_set_level_same_level_is_a_no_op(self):
        self.make()
        code, out = self.cli("set-level", "T-1", "L1", "--reason", "x")
        self.assertEqual(code, 0)
        self.assertIn("already L1", out)
        self.assertNotIn("level_history", json.loads(self.cli("show", "T-1")[1]))

    def test_new_twice_and_bad_ids_fail(self):
        self.make()
        with self.assertRaises(SystemExit):
            self.make()
        with self.assertRaises(SystemExit):
            self.cli("show", "../x")
        with self.assertRaises(SystemExit):
            self.cli("show", "missing")

    def test_flip_needs_existing_evidence(self):
        self.make()
        with self.assertRaises(SystemExit):
            self.cli("flip", "T-1", "a1")
        with self.assertRaises(SystemExit):
            self.cli("flip", "T-1", "a1", "--evidence", str(self.evidence) + ".nope")
        with self.assertRaises(SystemExit):
            self.cli("flip", "T-1", "a9", "--evidence", str(self.evidence))
        self.cli("flip", "T-1", "a1", "--evidence", str(self.evidence))
        entry = json.loads(self.cli("show", "T-1")[1])
        self.assertTrue(entry["acceptance"][0]["passes"])
        self.assertEqual(entry["acceptance"][0]["evidence"], str(self.evidence))

    def test_flip_changes_nothing_but_passes_and_evidence(self):
        self.make()
        before = json.loads(self.cli("show", "T-1")[1])
        self.cli("flip", "T-1", "a2", "--evidence", str(self.evidence))
        after = json.loads(self.cli("show", "T-1")[1])
        after["acceptance"][1].update(passes=False, evidence=None)
        self.assertEqual(before, after)

    def test_check_exits_zero_only_when_all_pass(self):
        self.make()
        self.assertEqual(self.cli("check", "T-1")[0], 1)
        self.cli("flip", "T-1", "a1", "--evidence", str(self.evidence))
        code, out = self.cli("check", "T-1")
        self.assertEqual(code, 1)
        self.assertIn("a2", out)
        self.cli("flip", "T-1", "a2", "--evidence", str(self.evidence))
        self.assertEqual(self.cli("check", "T-1")[0], 0)
        self.cli("flip", "T-1", "a2", "--fail")
        self.assertEqual(self.cli("check", "T-1")[0], 1)

    def test_add_check_and_empty_ledger(self):
        self.cli("new", "T-2", "--intake", "i", "--level", "L0", "--brief", "b")
        self.assertEqual(self.cli("check", "T-2")[0], 1)
        self.assertEqual(self.cli("add-check", "T-2", "x")[1].strip(), "added a1: x")
        self.assertEqual(self.cli("add-check", "T-2", "y")[1].strip(), "added a2: y")

    def test_list(self):
        self.make()
        self.cli("flip", "T-1", "a1", "--evidence", str(self.evidence))
        self.assertIn("T-1\tL1\tnew\t1/2", self.cli("list")[1])
        self.assertEqual(self.cli("list")[0], 0)

    @unittest.skipUnless(sys.platform == "darwin", "Linux baseline: FileNotFoundError xcodebuild (the test shells out to it)")
    def test_ledger_dir_is_git_ignored(self):
        out = subprocess.run(["git", "check-ignore", "build/tasks/T-1.json"], cwd=TOOLS.parent, capture_output=True)
        self.assertEqual(out.returncode, 0)


class AgentFilesTests(unittest.TestCase):
    def test_frontmatter_and_status_block(self):
        agents = TOOLS.parent / ".claude" / "agents"
        expected = {"orchestrator": "claude-fable-5-2", "researcher": "sonnet", "designer": "claude-fable-5-2", "verifier": "sonnet",
                    "steward": "sonnet", "coder": "sonnet", "menial": "haiku", "reviewer": "opus"}
        for name, model in expected.items():
            text = (agents / f"{name}.md").read_text()
            head = text.split("---")[1]
            with self.subTest(agent=name):
                self.assertIn(f"name: {name}\n", head)
                self.assertIn(f"model: {model}\n", head)
                effort = {"orchestrator": "medium", "designer": "medium", "coder": "medium", "researcher": "high",
                          "verifier": "medium", "steward": "medium", "menial": "low"}.get(name)
                if effort:
                    self.assertIn(f"effort: {effort}\n", head)
                if name != "reviewer":
                    self.assertIn("status block", text)
                self.assertLess(len(text.splitlines()), 90)


if __name__ == "__main__":
    unittest.main()
