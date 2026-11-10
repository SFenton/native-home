"""``tools/hooks/deny_rules.py`` and ``tools/hooks/triage_deny.py``: the deny list of a T3-launched triage session as a hook.

The parity corpus is generated from every rule the runner hands a headless session (``agent.disallowed_tools`` of
``tools/triage/config.json`` plus the request-repo rules ``load_config`` appends), so a rule added there is tested here without edits.
"""

import io
import json
import os
import re
import subprocess
import sys
import unittest
from contextlib import redirect_stderr
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import mock

TOOLS = Path(__file__).resolve().parents[1]
REPO = TOOLS.parent
sys.path.insert(0, str(TOOLS / "hooks"))
sys.path.insert(0, str(TOOLS / "triage"))
import deny_rules  # noqa: E402
import triage_deny  # noqa: E402
import triage_session as ts  # noqa: E402

HOME = os.path.realpath(os.path.expanduser("~"))
PROJECT = "/work/tree"
PATH_TOOLS = {"Read": "Read", "Write": "Write", "Edit": "Edit"}


def effective_rules():
    """The deny list a runner session gets: config.json plus what ``load_config`` appends for a (fake) request repository."""
    import hass_triage
    with TemporaryDirectory() as home:
        local = Path(home) / ".config" / "hass-triage"
        local.mkdir(parents=True)
        (local / "config.json").write_text(json.dumps({"request_repo": "someone/private-requests"}))
        cfg = hass_triage.load_config(Path(home))
    return cfg["agent"]["disallowed_tools"]


RULES = effective_rules()


def sample(rule):
    """``(tool, tool_input)`` that the rule must refuse."""
    m = re.fullmatch(r"([^()]+)(?:\((.*)\))?", rule, re.S)
    tool, spec = m.group(1), m.group(2)
    if spec is None:
        return tool, {}
    if tool == "Bash":
        return "Bash", {"command": spec.replace("*", "0")}
    path = spec.replace("~/", HOME + "/", 1) if spec.startswith("~/") else spec[1:] if spec.startswith("//") else spec
    path = path.replace("**", "a/b").replace("*", "x")
    return tool, {"file_path": path}


def decide(tool, tool_input, rules=RULES, cwd=PROJECT):
    return deny_rules.decide(rules, tool, tool_input, PROJECT, cwd)


class ParityTests(unittest.TestCase):
    def test_the_corpus_is_what_the_runner_hands_a_session(self):
        """Fails if: the generator reads nothing, or no longer sees the request-repo rules load_config appends."""
        self.assertGreater(len(RULES), 100)
        self.assertIn("Bash(gh issue edit*private-requests*)", RULES)
        self.assertIn("Bash(*GH_REPO=*private-requests*)", RULES)

    def test_every_rule_refuses_its_own_sample(self):
        """Fails if: a rule of agent.disallowed_tools (or a request-repo rule) is not enforced by the hook form."""
        failing = []
        for rule in RULES:
            tool, tool_input = sample(rule)
            if decide(tool, tool_input) is None:
                failing.append((rule, tool, tool_input))
        self.assertEqual(failing, [], f"deny_parity_cases_failing = {len(failing)}")

    def test_every_bash_rule_survives_common_wrapping(self):
        """Fails if: a prefix rule is evaded by a leading `cd`, a VAR= prefix, env, a pipe, bash -c, xargs or an absolute program path."""
        failing = []
        for rule in RULES:
            tool, tool_input = sample(rule)
            if tool != "Bash":
                continue
            cmd = tool_input["command"]
            for wrapped in (f"cd /tmp && {cmd}", f"X=1 {cmd}", f"env A=1 {cmd}", f"true | {cmd}", f"echo hi; {cmd}\necho done",
                            f"bash -c '{cmd}'" if "'" not in cmd else f'bash -c "{cmd}"', f"echo $({cmd})", f"nohup {cmd}"):
                if decide("Bash", {"command": wrapped}) is None:
                    failing.append((rule, wrapped))
        self.assertEqual(failing, [])

    def test_path_rules_cover_the_tools_the_runner_covers(self):
        """Fails if: a Read rule misses Grep or Glob, or a Write/Edit rule misses MultiEdit or NotebookEdit."""
        self.assertIsNotNone(decide("Grep", {"path": "/a/b/x.pem"}))
        self.assertIsNotNone(decide("Glob", {"path": "/a/b/x.pem", "pattern": "*"}))
        self.assertIsNotNone(decide("MultiEdit", {"file_path": "/a/b/x.pem"}))
        self.assertIsNotNone(decide("NotebookEdit", {"notebook_path": "/a/b/x.pem"}))
        self.assertIsNotNone(decide("Read", {"file_path": f"{HOME}/.config/fenton-hass/token"}))
        self.assertIsNotNone(decide("Read", {"file_path": "/Users/someone/.config/fenton-hass/token"}))
        self.assertIsNotNone(decide("Read", {"file_path": "/x/AuthKey_ABC.p8"}))

    def test_a_search_rooted_above_a_protected_folder_is_refused(self):
        """Fails if: a Grep or Glob over the home folder or the config folder can read the secrets the CLI form excluded."""
        self.assertIsNotNone(decide("Grep", {"path": HOME}))
        self.assertIsNotNone(decide("Glob", {"pattern": "**/*", "path": f"{HOME}/.config"}))
        self.assertIsNotNone(decide("Grep", {"path": "/"}))
        self.assertIsNone(decide("Grep", {"path": f"{HOME}/hass-agents/worktrees/42"}))

    def test_case_and_dot_dot_do_not_escape_a_path_rule(self):
        """Fails if: `..` segments or a different case reach a denied file."""
        self.assertIsNotNone(decide("Read", {"file_path": "/work/tree/../../a/b/KEY.PEM"}))
        self.assertIsNotNone(decide("Read", {"file_path": f"{HOME}/.CONFIG/Fenton-Hass/x"}))

    def test_a_relative_path_is_resolved_from_the_cwd(self):
        """Fails if: a relative path dodges an absolute rule."""
        self.assertIsNotNone(decide("Read", {"file_path": "secret.pem"}))
        self.assertIsNotNone(decide("Read", {"file_path": "../fenton-hass/x"}, cwd=f"{HOME}/.config/other"))

    def test_symlinks_are_followed(self):
        """Fails if: a symlink to a protected file reads it."""
        with TemporaryDirectory() as tmp:
            real = Path(os.path.realpath(tmp))
            link = real / "innocent.txt"
            link.symlink_to(real / "secret.pem")
            self.assertIsNotNone(decide("Read", {"file_path": str(link)}))


class NegativeCorpusTests(unittest.TestCase):
    def test_ordinary_agent_work_passes(self):
        """Fails if: the hook form blocks the commands and paths the runner's sessions need (over-blocking that breaks the work)."""
        commands = [
            'tools/ship.sh -m "mentions gh pr merge"',
            "tools/ship.sh --note 'Release-Note: none'",
            "tools/pr_land.sh 12",
            "python3 tools/triage/hass_triage.py comment 12 --body 'done'",
            "python3 tools/tasks.py list",
            "git push origin agents/t3-guards-261110",
            "git push -u origin HEAD",
            "git status && git diff --stat",
            "git commit -m \"mention git push --force and gh pr merge in prose\"",
            "cat <<'EOF' > notes.md\nrun gh pr merge 5 yourself\nEOF",
            "gh pr view 12 --json state",
            "gh pr create --title t --body-file b.md",
            "gh issue comment 12 --body 'thanks'",
            "gh api repos/SFenton/native-home/pulls/12",
            "xcrun simctl list devices",
            "python3 tools/devcap.py run --sim ABC -- xcodebuild -version",
            "swift test --filter HassCoreTests",
            "# gh pr merge 5\nls",
            "grep -rn 'xcodebuild test' tools | head",
            "python3 -m unittest tools.tests.test_triage_deny",
        ]
        for command in commands:
            with self.subTest(command):
                self.assertIsNone(decide("Bash", {"command": command}))

    def test_ordinary_paths_and_tools_pass(self):
        """Fails if: normal reads, writes and tool calls are refused."""
        cases = [("Read", {"file_path": "/work/tree/AGENTS.md"}), ("Edit", {"file_path": "/work/tree/tools/x.py"}),
                 ("Write", {"file_path": "/work/tree/build/out.json"}), ("Grep", {"pattern": "x"}), ("Glob", {"pattern": "**/*.swift"}),
                 ("Read", {"file_path": f"{HOME}/hass-agents/worktrees/42/a.swift"}), ("Read", {"file_path": f"{HOME}/.claude/settings.json"}),
                 ("WebFetch", {"url": "https://example.com"}), ("Task", {"prompt": "x"}), ("Skill", {"skill": "x"}),
                 ("Bash", {"command": ""}), ("Bash", {})]
        for tool, tool_input in cases:
            with self.subTest(tool=tool, input=tool_input):
                self.assertIsNone(decide(tool, tool_input))


class RuleSyntaxTests(unittest.TestCase):
    def test_parse(self):
        """Fails if: the rule grammar changes."""
        self.assertEqual(deny_rules.parse("Artifact"), (False, "Artifact", None))
        self.assertEqual(deny_rules.parse("Bash(gh pr merge*)"), (False, "Bash", "gh pr merge*"))
        self.assertEqual(deny_rules.parse("!mcp__t3-code__device_open"), (True, "mcp__t3-code__device_open", None))
        self.assertEqual(deny_rules.parse("Bash(echo (x))"), (False, "Bash", "echo (x)"))
        self.assertIsNone(deny_rules.parse(""))

    def test_an_unparseable_rule_denies_everything(self):
        """Fails if: a broken record entry lets a call through."""
        self.assertIn("unparseable", deny_rules.decide(["Bash(gh pr merge*)", ""], "Read", {"file_path": "/x"}, PROJECT))

    def test_bare_tool_and_wildcard_tool_names(self):
        """Fails if: a tool-only rule matches the wrong tools."""
        self.assertIsNotNone(decide("Artifact", {}, ["Artifact"]))
        self.assertIsNone(decide("ArtifactData", {}, ["Artifact"]))
        self.assertIsNotNone(decide("mcp__t3-code__threads_send", {}, ["mcp__t3-code__*"]))
        self.assertIsNone(decide("mcp__other__x", {}, ["mcp__t3-code__*"]))
        self.assertIsNotNone(decide("Bash", {"command": "ls"}, ["Bash"]))

    def test_exceptions_allow_what_a_deny_rule_covers(self):
        """Fails if: the `!` exception list does not carve the device tools out of the T3 toolkit."""
        rules = ["mcp__t3-code__*", "!mcp__t3-code__device_open"]
        self.assertIsNone(decide("mcp__t3-code__device_open", {}, rules))
        self.assertIsNotNone(decide("mcp__t3-code__threads_send", {}, rules))

    def test_bash_pattern_is_anchored_and_star_crosses_words(self):
        """Fails if: `*` stops at a space or a pattern matches in the middle of a command it should not."""
        self.assertIsNotNone(decide("Bash", {"command": "git push origin main"}, ["Bash(git push * main)"]))
        self.assertIsNone(decide("Bash", {"command": "git push origin mainline"}, ["Bash(git push * main)"]))
        self.assertIsNone(decide("Bash", {"command": "echo git push origin main"}, ["Bash(git push * main)"]))

    def test_shell_wrappers_are_looked_through(self):
        """Fails if: eval, bash -c, xargs and nesting hide a denied command."""
        rules = ["Bash(gh pr merge*)"]
        for command in ("eval gh pr merge 5", "sh -c 'gh pr merge 5'", "echo 5 | xargs gh pr merge", "bash -c \"bash -c 'gh pr merge 5'\"",
                        "/opt/homebrew/bin/gh pr merge 5", "timeout 5 gh pr merge 5", "(gh pr merge 5)", "`gh pr merge 5`"):
            with self.subTest(command):
                self.assertIsNotNone(decide("Bash", {"command": command}, rules))

    def test_home_relative_and_project_relative_patterns(self):
        """Fails if: `~/`, `/x` and `x` patterns anchor in the wrong place."""
        self.assertIsNotNone(decide("Read", {"file_path": f"{HOME}/.ssh/id"}, ["Read(~/.ssh/**)"]))
        self.assertIsNotNone(decide("Read", {"file_path": f"{PROJECT}/secrets/a"}, ["Read(/secrets/**)"]))
        self.assertIsNotNone(decide("Read", {"file_path": f"{PROJECT}/secrets/a"}, ["Read(secrets/**)"]))
        self.assertIsNone(decide("Read", {"file_path": "/other/secrets/a"}, ["Read(secrets/**)"]))
        self.assertIsNotNone(decide("Read", {"file_path": "/a/b/c.txt"}, ["Read(//a/*/c.txt)"]))
        self.assertIsNone(decide("Read", {"file_path": "/a/b/d/c.txt"}, ["Read(//a/*/c.txt)"]))


def run_hook(payload, env, root):
    """Run ``triage_deny.main`` with ``payload`` on stdin, ``env`` as the environment and ``root`` as the registry."""
    err = io.StringIO()
    stdin = io.StringIO(payload if isinstance(payload, str) else json.dumps(payload))
    with mock.patch.dict(os.environ, env, clear=True), mock.patch.object(sys, "stdin", stdin), redirect_stderr(err), \
            mock.patch.object(ts, "registry_root", return_value=root):
        code = triage_deny.main()
    return code, err.getvalue()


class HookTests(unittest.TestCase):
    def setUp(self):
        tmp = TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = Path(os.path.realpath(tmp.name))
        self.root = self.tmp / "t3"
        self.work = self.tmp / "wt"
        self.work.mkdir()
        self.env = {"CLAUDE_PROJECT_DIR": str(self.work), "T3CODE_THREAD_ID": "thr-1", "PATH": os.environ.get("PATH", "")}

    def register(self, deny=("Bash(gh pr merge*)", "Artifact"), **over):
        rec = ts.build_record("request", 7, "orchestrator", self.work, "report/7", {"FENTON_HEADLESS": "1"}, list(deny))
        rec.update(over)
        ts.write_record(rec, self.root)

    def call(self, tool, tool_input, env=None, **extra):
        return run_hook({"tool_name": tool, "tool_input": tool_input, "cwd": str(self.work), **extra}, env or self.env, self.root)

    def test_no_record_means_every_call_passes(self):
        """Fails if: an owner session (even one with a T3 thread id) is blocked by the deny hook."""
        for tool, tool_input in (("Bash", {"command": "gh pr merge 5"}), ("Artifact", {}), ("mcp__t3-code__threads_send", {}),
                                 ("Read", {"file_path": "/x/key.pem"})):
            self.assertEqual(self.call(tool, tool_input), (0, ""))

    def test_a_registered_session_is_denied_by_its_record(self):
        """Fails if: the record's deny list is not enforced, by either key."""
        self.register()
        code, err = self.call("Bash", {"command": "cd /tmp && gh pr merge 5"})
        self.assertEqual(code, 2)
        self.assertIn("gh pr merge*", err)
        self.assertEqual(self.call("Artifact", {})[0], 2)
        self.assertEqual(self.call("Bash", {"command": "git status"}), (0, ""))
        # by the path key alone, before the thread exists, and after `cd /tmp`
        only_path = {"CLAUDE_PROJECT_DIR": str(self.work)}
        self.assertEqual(run_hook({"tool_name": "Artifact", "tool_input": {}, "cwd": "/tmp"}, only_path, self.root)[0], 2)

    def test_the_t3_toolkit_is_denied_except_the_device_tools(self):
        """Fails if: a session can start or message another thread (which would have no record), or loses its device tools."""
        self.register(deny=())
        self.assertEqual(self.call("mcp__t3-code__threads_send", {})[0], 2)
        self.assertEqual(self.call("mcp__t3-code__handover", {})[0], 2)
        for name in ("device_list", "device_open", "device_screenshot", "device_close"):
            self.assertEqual(self.call(f"mcp__t3-code__{name}", {}), (0, ""))

    def test_the_registry_protects_itself(self):
        """Fails if: a session can read, edit or script the records that guard it."""
        self.register(deny=())
        for tool, tool_input in (("Bash", {"command": "cat ~/hass-agents/t3/worktrees/x.json"}),
                                 ("Bash", {"command": "rm -f $HOME/hass-agents/t3/threads/*"}),
                                 ("Read", {"file_path": f"{HOME}/hass-agents/t3/worktrees/x.json"}),
                                 ("Write", {"file_path": f"{HOME}/hass-agents/t3/threads/x.json"}),
                                 ("Edit", {"file_path": f"{HOME}/hass-agents/t3/threads/x.json"})):
            self.assertEqual(self.call(tool, tool_input)[0], 2, (tool, tool_input))

    def test_extras_a_launcher_may_add_are_enforced(self):
        """Fails if: the T3-only extra rules of the note (`agent.t3.extra_denied`) do not work as record entries."""
        extras = ["Bash(*t3code*)", "Bash(*npx*t3*)", "Bash(*CLAUDE_ENV_FILE*)", "Write(~/.claude/**)", "Edit(~/.claude/**)",
                  "Bash(*.claude/settings*)", "AskUserQuestion"]
        self.register(deny=extras)
        for tool, tool_input in (("Bash", {"command": "t3code threads list"}), ("Bash", {"command": "npx t3 x"}),
                                 ("Bash", {"command": "echo hi >> $CLAUDE_ENV_FILE"}), ("Write", {"file_path": f"{HOME}/.claude/x"}),
                                 ("Edit", {"file_path": f"{HOME}/.claude/settings.json"}), ("AskUserQuestion", {}),
                                 ("Bash", {"command": "sed -i '' s/a/b/ .claude/settings.json"})):
            self.assertEqual(self.call(tool, tool_input)[0], 2, (tool, tool_input))

    def test_strict_mode_blocks_every_call(self):
        """Fails if: a record that cannot be trusted lets any tool through."""
        path = self.root / "worktrees" / f"{ts.worktree_key(self.work)}.json"
        path.parent.mkdir(parents=True)
        for text in ("{oops", json.dumps({"v": 9})):
            path.write_text(text)
            for tool, tool_input in (("Bash", {"command": "ls"}), ("Read", {"file_path": "/work/x"}), ("Grep", {}), ("mcp__x__y", {}),
                                     ("Artifact", {})):
                code, err = self.call(tool, tool_input)
                self.assertEqual(code, 2, tool)
                self.assertIn("cannot be trusted", err)

    def test_every_failure_is_a_refusal(self):
        """Fails if: a hook error lets a call through."""
        self.register()
        self.assertEqual(run_hook("not json", self.env, self.root)[0], 2)
        self.assertEqual(run_hook("[1]", self.env, self.root)[0], 2)
        self.assertEqual(run_hook({"tool_name": "Bash"}, self.env, self.root)[0], 2)
        self.assertEqual(run_hook({"tool_name": 5, "tool_input": {}}, self.env, self.root)[0], 2)
        self.register(deny=("",))
        self.assertEqual(self.call("Read", {"file_path": "/x"})[0], 2)

    def test_the_hook_runs_as_a_script_and_fails_closed_without_its_modules(self):
        """Fails if: the settings entry's command (python3 triage_deny.py) breaks, or an import error becomes a pass."""
        hooks = TOOLS / "hooks"
        out = subprocess.run([sys.executable, str(hooks / "triage_deny.py")], input=json.dumps({"tool_name": "Bash",
                             "tool_input": {"command": "ls"}, "cwd": "/"}), capture_output=True, text=True,
                             env={"PATH": os.environ.get("PATH", ""), "HOME": str(self.tmp)})
        self.assertEqual((out.returncode, out.stderr), (0, ""))
        with TemporaryDirectory() as lone:
            copy = Path(lone) / "triage_deny.py"
            copy.write_text((hooks / "triage_deny.py").read_text())
            out = subprocess.run([sys.executable, str(copy)], input="{}", capture_output=True, text=True)
            self.assertEqual(out.returncode, 2)
            self.assertIn("fails closed", out.stderr)

    def test_settings_register_the_hook_with_a_fail_closed_wrapper(self):
        """Fails if: the PreToolUse entry loses its matcher, or the wrapper lets a missing hook through in a registered session."""
        settings = json.loads((REPO / ".claude" / "settings.json").read_text())
        entries = [e for e in settings["hooks"]["PreToolUse"] if any("triage_deny.py" in h["command"] for h in e["hooks"])]
        self.assertEqual(len(entries), 1)
        matcher = entries[0]["matcher"]
        for tool in ("Bash", "Read", "Write", "Edit", "MultiEdit", "NotebookEdit", "Grep", "Glob", "Artifact", "ArtifactComments",
                     "ArtifactData", "AskUserQuestion", "mcp__t3-code__threads_send", "mcp__claude_ai_X__y"):
            self.assertRegex(tool, f"^(?:{matcher})$")
        command = entries[0]["hooks"][0]["command"]
        # wrapper behaviour: file missing + registered => exit 2; file missing + not registered => exit 0
        fake_home = self.tmp / "home"
        project = self.tmp / "proj"
        project.mkdir()
        env = {"PATH": os.environ.get("PATH", ""), "HOME": str(fake_home), "CLAUDE_PROJECT_DIR": str(project)}
        quiet = subprocess.run(["bash", "-c", command], capture_output=True, text=True, env=env)
        self.assertEqual(quiet.returncode, 0)
        rec = ts.build_record("request", 7, "orchestrator", project, "report/7", {"FENTON_HEADLESS": "1"}, [])
        ts.write_record(rec, fake_home / "hass-agents" / "t3")
        loud = subprocess.run(["bash", "-c", command], capture_output=True, text=True, env=env)
        self.assertEqual(loud.returncode, 2)
        self.assertIn("fails closed", loud.stderr)
        by_thread = subprocess.run(["bash", "-c", command], capture_output=True, text=True,
                                   env={**env, "CLAUDE_PROJECT_DIR": str(self.tmp), "T3CODE_THREAD_ID": "x"})
        self.assertEqual(by_thread.returncode, 0)
        rec = ts.build_record("request", 8, "orchestrator", self.work, "report/8", {"FENTON_HEADLESS": "1"}, [])
        rec["thread_id"] = "x"
        ts.write_record(rec, fake_home / "hass-agents" / "t3")
        by_thread = subprocess.run(["bash", "-c", command], capture_output=True, text=True,
                                   env={**env, "CLAUDE_PROJECT_DIR": str(self.tmp), "T3CODE_THREAD_ID": "x"})
        self.assertEqual(by_thread.returncode, 2)
        # the real hook file is present in this checkout, so the wrapper runs it
        present = subprocess.run(["bash", "-c", command], capture_output=True, text=True, input=json.dumps(
            {"tool_name": "Bash", "tool_input": {"command": "ls"}}), env={**env, "CLAUDE_PROJECT_DIR": str(REPO)})
        self.assertEqual(present.returncode, 0, present.stderr)

    def test_session_start_is_registered(self):
        """Fails if: the SessionStart env export loses its registration."""
        settings = json.loads((REPO / ".claude" / "settings.json").read_text())
        commands = [h["command"] for e in settings["hooks"]["SessionStart"] for h in e["hooks"]]
        self.assertTrue(any("triage_session.py" in c and "--session-start" in c for c in commands))


if __name__ == "__main__":
    unittest.main()
