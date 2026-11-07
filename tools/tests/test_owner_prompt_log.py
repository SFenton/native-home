"""``tools/hooks/owner_prompt_log.py`` and the lander's use of the log (``lane_land.logged_owner_prompt``)."""

import hashlib
import io
import json
import os
import stat
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest import mock

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS / "hooks"))
sys.path.insert(0, str(TOOLS))
import lane_land  # noqa: E402
import owner_prompt_guard as guard  # noqa: E402
import owner_prompt_log as hook  # noqa: E402

NOW = datetime(2026, 11, 4, 12, 0, 0, tzinfo=timezone.utc)
PROMPT = "Please make the Home chips taller, they are hard to hit on the Duo."


class HookTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = self.tmp.name

    def payload(self, **extra):
        return {"hook_event_name": "UserPromptSubmit", "prompt": PROMPT, "session_id": "s1", "cwd": "/w", **extra}

    def test_a_human_prompt_is_appended_mode_600_with_its_hash(self):
        path = hook.append(self.payload(), now=NOW, home=self.home)
        self.assertEqual(path, Path(self.home) / "hass-agents/owner-prompts/2026-11.jsonl")
        self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
        hook.append(self.payload(prompt="second"), now=NOW, home=self.home)
        rows = [json.loads(line) for line in path.read_text().splitlines()]
        self.assertEqual([r["prompt"] for r in rows], [PROMPT, "second"])
        self.assertEqual(rows[0]["sha256"], hashlib.sha256(PROMPT.encode()).hexdigest())
        self.assertEqual((rows[0]["ts"], rows[0]["session"], rows[0]["cwd"]), ("2026-11-04T12:00:00Z", "s1", "/w"))

    #: The main thread of the owner's desktop chat: agent_type from the settings' "agent": "orchestrator", no agent_id.
    MAIN = {"agent_type": "orchestrator"}
    #: A subagent or teammate carries agent_id as well.
    SUB = {"agent_type": "coder", "agent_id": "a1b2c3"}
    DESKTOP = {"CLAUDE_CODE_ENTRYPOINT": "claude-desktop", "CLAUDE_CODE_SESSION_ATTENDED": "1", "CLAUDECODE": "1"}

    def test_the_owners_main_thread_is_logged_by_agent_id_not_agent_type(self):
        self.assertTrue(hook.should_log(self.payload(**self.MAIN), env=self.DESKTOP, ancestors=1))
        self.assertTrue(hook.should_log(self.payload(), env={}, ancestors=1))
        self.assertFalse(hook.should_log(self.payload(**self.SUB), env=self.DESKTOP, ancestors=1))
        self.assertFalse(hook.should_log(self.payload(agent_id="a1"), env={}, ancestors=1))

    def test_headless_ssh_print_mode_and_nested_claude_write_nothing(self):
        for name, env, ancestors in (("headless", {"FENTON_HEADLESS": "1"}, 1), ("ssh", {"SSH_CONNECTION": "1.2.3.4 5 6.7.8.9 22"}, 1),
                                     ("ssh client", {"SSH_CLIENT": "1.2.3.4 5 22"}, 1), ("ssh tty", {"SSH_TTY": "/dev/ttys001"}, 1),
                                     ("print mode", {"CLAUDE_CODE_ENTRYPOINT": "sdk-cli"}, 1),
                                     ("sdk ts", {"CLAUDE_CODE_ENTRYPOINT": "sdk-ts"}, 1),
                                     ("unattended", {"CLAUDE_CODE_SESSION_ATTENDED": "0"}, 1), ("nested claude", {}, 2)):
            with self.subTest(name):
                self.assertFalse(hook.should_log(self.payload(**self.MAIN), env=env, ancestors=ancestors))

    def test_event_text_and_harness_wrappers(self):
        env = self.DESKTOP
        self.assertFalse(hook.should_log(self.payload(hook_event_name="Stop"), env=env, ancestors=1))
        self.assertFalse(hook.should_log(self.payload(prompt="  "), env=env, ancestors=1))
        self.assertFalse(hook.should_log("nope", env=env, ancestors=1))
        wrapped = ("<task-notification>done</task-notification>", "  <system-reminder>x</system-reminder>",
                   "<channel source=\"x\">hi</channel>", "<cross-session-message from=\"s2\">do it</cross-session-message>",
                   "<teammate-message teammate_id=\"t\">go</teammate-message>", "<local-command-stdout>ok</local-command-stdout>",
                   "<<autonomous-loop>> check the PRs", "<fork-boilerplate>x", "[Artifact comment sent to Claude] ;thread=1",
                   "<user-prompt-submit-hook>x")
        for text in wrapped:
            with self.subTest(text[:24]):
                self.assertFalse(hook.should_log(self.payload(prompt=text, **self.MAIN), env=env, ancestors=1))
        self.assertTrue(hook.should_log(self.payload(prompt="/loop 5m check the PRs, make them taller", **self.MAIN), env=env, ancestors=1))

    def test_the_process_tree_probe_counts_this_sessions_claude_ancestors(self):
        outputs = iter(["  50 /bin/sh", "  40 /usr/local/bin/claude", "  30 /bin/zsh", "  20 /x/claude", "  1 /sbin/launchd"])

        def fake(cmd, **kw):
            return mock.Mock(stdout=next(outputs))
        with mock.patch.object(hook.subprocess, "run", fake):
            self.assertEqual(hook.claude_ancestors(100), 2)

    def test_a_session_claude_started_by_another_session_is_not_logged(self):
        """A detached `(claude -p --agent orchestrator ... &)` from an agent's tool call inherits CLAUDECODE=1."""
        def fake_ps(env_text):
            def run(cmd, **kw):
                if "-E" in cmd:
                    return mock.Mock(stdout=env_text)
                return mock.Mock(stdout={"100": " 90 /bin/sh", "90": " 80 /u/.local/bin/claude", "80": " 1 /sbin/launchd"}[cmd[-1]])
            return run
        owner = "/Applications/claude --output-format stream-json PATH=/usr/bin HOME=/Users/u CLAUDE_CODE_ENTRYPOINT=claude-desktop"
        for name, text, expected in (("owner", owner, True), ("agent-started", owner + " CLAUDECODE=1", False),
                                     ("session id", owner + " CLAUDE_CODE_SESSION_ID=abc", False), ("unreadable", "  ", False),
                                     ("look-alike", owner + " NOTCLAUDECODE=1 X_CLAUDE_CODE_SESSION_ID=1", True)):
            with self.subTest(name), mock.patch.object(hook.subprocess, "run", fake_ps(text)):
                self.assertEqual(hook.session_env_clean(100), expected)
        with mock.patch.object(hook.subprocess, "run", lambda cmd, **kw: mock.Mock(stdout="")):
            self.assertFalse(hook.session_env_clean(100))  # no claude ancestor: fail closed
        self.assertFalse(hook.should_log(self.payload(**self.MAIN), env=self.DESKTOP, ancestors=1, clean=False))

    def test_a_launcher_not_named_claude_is_caught_by_its_own_environment(self):
        """`~/.local/share/claude/versions/<ver> -p ...` or node under npx: the parent is checked, not only the claude ancestor."""
        envs = {"90": "/Applications/claude PATH=/usr/bin", "55": "/x/versions/2.1 -p --agent orchestrator CLAUDECODE=1 PATH=/usr/bin"}

        def run(cmd, **kw):
            if "-E" in cmd:
                return mock.Mock(stdout=envs.get(cmd[-1], ""))
            return mock.Mock(stdout={"100": " 55 /bin/sh", "55": " 90 /x/versions/2.1", "90": " 80 /u/claude", "80": " 1 /sbin/launchd"}[cmd[-1]])
        with mock.patch.object(hook.subprocess, "run", run):
            self.assertFalse(hook.session_env_clean(100, parent=55))  # the launcher carries CLAUDECODE=1
            self.assertTrue(hook.session_env_clean(100, parent=90))  # the desktop session: the hook's parent is the claude itself
            self.assertFalse(hook.session_env_clean(100, parent=77))  # an unreadable parent fails closed

    def test_the_real_process_tree_probe_runs(self):
        self.assertIsInstance(hook.session_env_clean(), bool)
        self.assertIsInstance(hook.claude_ancestors(), int)


    def test_old_monthly_files_are_pruned_on_append(self):
        folder = hook.log_dir(self.home)
        folder.mkdir(parents=True)
        for month in ("2026-08", "2026-09", "2026-10"):
            (folder / f"{month}.jsonl").write_text("{}\n")
        hook.append(self.payload(), now=NOW, home=self.home)
        self.assertEqual(sorted(p.name for p in folder.iterdir()), ["2026-10.jsonl", "2026-11.jsonl"])

    def test_main_never_fails_and_a_headless_run_writes_no_file(self):
        with mock.patch.dict(os.environ, {"HOME": self.home, "FENTON_HEADLESS": "1"}):
            with mock.patch.object(sys, "stdin", io.StringIO(json.dumps(self.payload()))):
                self.assertEqual(hook.main(), 0)
        self.assertFalse((Path(self.home) / "hass-agents").exists())
        with mock.patch.object(sys, "stdin", io.StringIO("not json")):
            self.assertEqual(hook.main(), 0)
        with mock.patch.dict(os.environ, {"HOME": self.home, **self.DESKTOP}, clear=True), mock.patch.object(hook, "claude_ancestors", lambda: 1), \
                mock.patch.object(hook, "session_env_clean", lambda: True):
            with mock.patch.object(sys, "stdin", io.StringIO(json.dumps(self.payload(**self.MAIN)))):
                self.assertEqual(hook.main(), 0)
        self.assertTrue(list((Path(self.home) / "hass-agents/owner-prompts").glob("*.jsonl")))


    def test_the_hook_and_the_lander_read_the_same_folder(self):
        self.assertEqual(hook.log_dir(self.home), Path(self.home) / "hass-agents" / "owner-prompts")
        self.assertEqual(lane_land.prompt_reader(Path(self.home) / "hass-agents").__closure__[0].cell_contents,
                         Path(self.home) / "hass-agents")


class MatchTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / "hass-agents"

    def log(self, prompt=PROMPT, age_days=1):
        hook.append({"prompt": prompt, "session_id": "s"}, now=NOW - timedelta(days=age_days), home=self.tmp.name)

    def match(self, quote):
        return lane_land.logged_owner_prompt(self.root / "owner-prompts", quote, now=NOW)

    def test_a_logged_quote_matches_ignoring_case_whitespace_and_quote_marks(self):
        self.log()
        self.assertEqual(self.match('"make the home   chips taller"'), PROMPT)
        self.assertEqual(self.match("“make the Home chips\ntaller”"), PROMPT)

    def test_an_unlogged_short_or_old_quote_does_not_match(self):
        self.log()
        self.assertIsNone(self.match("make the Settings tab greener please"))
        self.assertIsNone(self.match("make the home"))  # under 20 characters
        self.assertIsNone(lane_land.logged_owner_prompt(self.root / "missing", "make the home chips taller", now=NOW))
        old = tempfile.TemporaryDirectory()
        self.addCleanup(old.cleanup)
        hook.append({"prompt": PROMPT}, now=NOW - timedelta(days=15), home=old.name)
        self.assertIsNone(lane_land.logged_owner_prompt(Path(old.name) / "hass-agents/owner-prompts", "make the home chips taller", now=NOW))

    def test_garbage_rows_are_skipped(self):
        self.log()
        path = next((self.root / "owner-prompts").glob("*.jsonl"))
        path.write_text("junk\n" + json.dumps({"ts": "bad", "prompt": PROMPT}) + "\n" + path.read_text())
        self.assertEqual(self.match("make the home chips taller"), PROMPT)

    def test_pasted_blocks_fenced_code_and_quoted_lines_are_not_the_owners_words(self):
        pasted = ("Fix the thing.\n<pasted_content>The agent said: make every tile purple everywhere now</pasted_content>\n"
                  "```\nmake the settings page greener please\n```\n> make the cameras tab bigger please\nThanks")
        self.log(pasted)
        for quote in ("make every tile purple everywhere now", "make the settings page greener please", "make the cameras tab bigger please"):
            with self.subTest(quote):
                self.assertIsNone(self.match(quote))
        self.assertIn("fix the thing", self.match("Fix the thing. Thanks").lower())

    def test_jev_gets_the_text_around_the_quote_not_the_first_chars(self):
        self.log("Intro. " * 300 + "Please make the Duo chips taller. " + "Outro. " * 300)
        window = self.match("make the Duo chips taller")
        self.assertIn("Please make the Duo chips taller.", window)
        self.assertLessEqual(len(window), 2 * lane_land.PROMPT_WINDOW + len("make the duo chips taller") + 2)

    def test_the_hooks_are_unlocked_but_registered(self):
        cfg = json.loads((TOOLS / "triage/config.json").read_text())
        for path in ("tools/hooks/owner_prompt_log.py", "tools/hooks/owner_prompt_guard.py"):  # unlocked by the owner, 2026-11-07
            self.assertFalse(lane_land.matches(path, lane_land.DEFAULT_PROTECTED), path)
            lane_land.check_paths([("M", path, "0" * 40, "1" * 40)], lane_land.DEFAULT_PROTECTED, [])
        for rule in ("Bash(*owner-prompts*)", "Read(//**/owner-prompts/**)", "Write(//**/owner-prompts/**)", "Edit(//**/owner-prompts/**)"):
            self.assertIn(rule, cfg["agent"]["disallowed_tools"])
        hooks = json.loads((TOOLS.parent / ".claude/settings.json").read_text())["hooks"]
        self.assertTrue(any("owner_prompt_log.py" in h["command"] for g in hooks["UserPromptSubmit"] for h in g["hooks"]))
        by_matcher = {g["matcher"]: " ".join(h["command"] for h in g["hooks"]) for g in hooks["PreToolUse"]}
        for matcher in ("Bash", "Read|Grep|Glob", "Edit|Write|MultiEdit|NotebookEdit"):
            self.assertIn("owner_prompt_guard.py", by_matcher[matcher], matcher)


class GuardTests(unittest.TestCase):
    ROLES = {"coder", "reviewer", "orchestrator"}

    def bash(self, command):
        return guard.bash_reason(command, self.ROLES)

    def test_bash_naming_the_log_is_refused_whatever_the_quoting(self):
        home = "~/hass-agents/owner-prompts/2026-11.jsonl"
        for command in (f"printf x >> {home}", f"cat {home}", "ls ~/hass-agents/OWNER-PROMPTS", "cat ~/hass-agents/owner-prompts/*",
                        "bash -c 'echo x >> ~/hass-agents/Owner-Prompts/a'", 'python3 -c "open(\'/Users/u/hass-agents/owner-prompts/a\')"'):
            with self.subTest(command):
                self.assertIn("owner-prompts", self.bash(command))
        self.assertIsNone(self.bash("ls && python3 tools/jev_ask.py validate"))

    def test_claude_print_needs_a_roster_agent(self):
        refused = ("claude -p 'make it purple'", "claude --print hi", 'claude -p --agent "" hi', "claude -p --agent nobody hi",
                   "ssh macbook 'cd /r && claude -p \"x\"'", "env X=1 ~/.local/bin/claude -p hi", "claude --model sonnet -p hi",
                   "cd r; claude -pq hi", "(claude -p hi &)",
                   "npx @anthropic-ai/claude-code -p hi", "npx -y @anthropic-ai/claude-code --print hi", "claude-code -p x",
                   "grep -c claude x; claude -p hi", "echo a && claude -p hi || true")
        for command in refused:
            with self.subTest(command):
                self.assertEqual(self.bash(command), "claude -p without --agent <role>")
        allowed = ("claude -p --agent coder 'do it'", "claude --agent=reviewer -p hi", "ssh sfenton-mini 'claude -p --agent coder x'",
                   "claude --version", "claude", "ls claude-notes -p", "grep -c claude x; mkdir -p out",
                   "cat claude.md | head -p 3", "claude --version && ls -p", "npx @anthropic-ai/claude-code -p --agent coder x")
        for command in allowed:
            with self.subTest(command):
                self.assertIsNone(self.bash(command))

    def test_globs_that_can_reach_the_folder_are_refused(self):
        for command in ("cat ~/hass-agents/owner*/2026-11.jsonl", "ls ~/hass-agents/*", "cat ~/hass-agents/o?ner-prompts/x",
                        "cat $HOME/hass-agents/[o]wner-prompts/x", "ls ~/hass-agents/{owner-prompts,gate}"):
            with self.subTest(command):
                self.assertTrue(self.bash(command), command)
        for command in ("ls ~/hass-agents/gate*", "cat ~/hass-agents/requests/*.json", "ls ~/hass-agents/reviews"):
            with self.subTest(command):
                self.assertIsNone(self.bash(command))

    def test_roles_come_from_the_project_agents_folder(self):
        self.assertIn("orchestrator", guard.roles())
        self.assertIsNone(guard.bash_reason("claude -p --agent coder hi"))
        self.assertIsNotNone(guard.bash_reason("claude -p --agent nobody hi"))

    def test_path_tools_are_refused_inside_the_log_folder_and_searches_over_its_parent(self):
        with tempfile.TemporaryDirectory() as home:
            folder = Path(home) / "hass-agents" / "owner-prompts"
            folder.mkdir(parents=True)
            link = Path(home) / "innocent"
            link.symlink_to(folder)
            for key, value in (("file_path", str(folder / "2026-11.jsonl")), ("file_path", str(link / "2026-11.jsonl")),
                               ("path", str(folder)), ("path", str(Path(home) / "hass-agents")), ("path", home), ("path", "/"), ("path", "/Users"), ("path", os.path.dirname(home)),
                               ("pattern", str(Path(home) / "hass-agents" / "owner*")), ("glob", "hass-agents/*"),
                               ("file_path", str(folder).upper() + "/x"), ("pattern", "**/owner-prompts/*.jsonl"),
                               ("notebook_path", str(folder / "n.ipynb"))):
                with self.subTest(key=key, value=value):
                    self.assertIsNotNone(guard.path_reason({key: value}, home=home))
            for ok in ({"file_path": str(Path(home) / "hass-agents" / "gate.lock")}, {"file_path": "/etc/hosts"},
                       {"file_path": "x.md", "new_string": "docs mention owner-prompts", "content": "owner-prompts"}):
                with self.subTest(ok=ok):
                    self.assertIsNone(guard.path_reason(ok, home=home))

    def test_main_exit_codes(self):
        def run(payload):
            with mock.patch.object(sys, "stdin", io.StringIO(json.dumps(payload))), mock.patch("sys.stderr", io.StringIO()):
                return guard.main()
        self.assertEqual(run({"tool_name": "Bash", "tool_input": {"command": "cat ~/hass-agents/owner-prompts/x"}}), 2)
        self.assertEqual(run({"tool_name": "Write", "tool_input": {"file_path": os.path.expanduser("~/hass-agents/owner-prompts/x")}}), 2)
        self.assertEqual(run({"tool_name": "Bash", "tool_input": {"command": "ls"}}), 0)
        self.assertEqual(run({"tool_name": "WebFetch", "tool_input": {}}), 0)
        with mock.patch.object(sys, "stdin", io.StringIO("nope")):
            self.assertEqual(guard.main(), 0)


class MockupDrawnFormTests(unittest.TestCase):
    PAGE = """<!doctype html><html><head><title>A</title></head><body>
<!-- cite: ha-sfenton-react-dash@abc:Foo.tsx:10 -->
<a href="../x.html" data-cite="ha-sfenton-react-dash@abc:Foo.tsx:10">link</a>
<script>
// a note
Mock.mount({
  kind: 'page', id: 'chores', title: 'Chores', area: 'chores', status: 'in flight',
  source: ['apple/Sources/HassUI/Features/Chores/ChoresScreen.swift', 'b.swift'],
  spec: ['.agents/pages/chores/spec.md'],
  patterns: ['module-list'],
  reviews: { date: '2026-10-01', hig: [{ rule: 'x', verdict: 'pass', note: 'a { brace' }] },
  states: { 'default': { title: 'Signed in', render: function (d) { return h('div', {}, 'Chores'); } } },
  motion: [{ id: 'm', source: 'HassUI/Features/Chores/TodoPageView.swift', play: function () {} }]
});
</script></body></html>"""

    def form(self, text, path=".agents/design/mockups/pages/chores/chores/chores.html"):
        return lane_land.mockup_drawn_form(path, text.encode())

    def test_citation_and_metadata_rewrites_draw_the_same(self):
        edited = (self.PAGE.replace("ha-sfenton-react-dash@abc:Foo.tsx:10", "ha-sfenton-react-dash@def:Foo.tsx:99")
                  .replace("ChoresScreen.swift', 'b.swift'", "UKChoresEntry.swift', 'c.swift'").replace("'in flight'", "'shipped'")
                  .replace("['module-list']", "['module-list', 'motion']").replace("2026-10-01", "2026-11-04")
                  .replace("<!-- cite", "<!--  cite")
                  .replace("../x.html", "../y.html").replace("TodoPageView.swift'", "UKTodo.swift'"))
        self.assertNotEqual(edited, self.PAGE)
        self.assertEqual(self.form(edited), self.form(self.PAGE))

    def test_a_drawn_change_differs(self):
        for old, new in (("'Chores'); } }", "'Chores!'); } }"), ("title: 'Signed in'", "title: 'Signed out'"),
                         ("<body>", "<body><p>x</p>")):
            with self.subTest(old=old):
                self.assertNotEqual(self.form(self.PAGE.replace(old, new)), self.form(self.PAGE))

    def test_a_script_inside_an_html_comment_goes_with_the_comment(self):
        base = self.PAGE
        commented = base.replace("<body>", "<body><!-- old: <script>var a = 'x';</script> -->")
        self.assertEqual(self.form(commented), self.form(base))
        # the real script after it keeps its place and its text, so a drawn change in it is still seen
        self.assertNotEqual(self.form(commented.replace("Signed in", "Signed out")), self.form(commented))
        # ...and a comment marker inside a real script is not stripped, so the script body after it is not eaten
        tricky = base.replace("// a note", "var t = '<!--'; var u = 1;") + "<p>after</p><!-- end -->"
        self.assertNotEqual(self.form(tricky.replace("var u = 1", "var u = 2")), self.form(tricky))

    def test_stylesheet_icon_href_and_text_inside_script_strings_are_drawn(self):
        sheet = '<link rel="stylesheet" href="../kit.css">'
        base = self.PAGE.replace("<body>", "<body>" + sheet + '<svg><use href="#a"></use></svg>')
        for old, new in (("../kit.css", "../other.css"), ('href="#a"', 'href="#b"'),
                         ("// a note", "// a note\nvar t = `<!-- drawn -->`;"),
                         ("render: function (d) { return h('div', {}, 'Chores'); }", "render: function (d) { return h('div', {}, '<!-- x -->Chores'); }")):
            with self.subTest(old=old):
                self.assertNotEqual(self.form(base.replace(old, new)), self.form(base))
        # a script-string comment edit counts; an anchor href edit and an HTML comment outside script do not
        self.assertNotEqual(self.form(base.replace("// a note", "// other")), self.form(base))
        self.assertEqual(self.form(base.replace("../x.html", "../z.html").replace("<!-- cite:", "<!-- seen:")), self.form(base))

    def test_markdown_and_catalog_metadata(self):
        self.assertEqual(lane_land.mockup_drawn_form("a/README.md", b"x"), lane_land.mockup_drawn_form("a/README.md", b"y"))
        a = json.dumps({"items": [{"id": "h", "title": "Home", "sources": ["a"], "status": "shipped"}]}).encode()
        b = json.dumps({"items": [{"id": "h", "title": "Home", "sources": ["b", "c"], "status": "decided"}]}).encode()
        c = json.dumps({"items": [{"id": "h", "title": "Home!", "sources": ["a"], "status": "shipped"}]}).encode()
        cat = ".agents/design/mockups/catalog.json"
        self.assertEqual(lane_land.mockup_drawn_form(cat, a), lane_land.mockup_drawn_form(cat, b))
        self.assertNotEqual(lane_land.mockup_drawn_form(cat, a), lane_land.mockup_drawn_form(cat, c))


if __name__ == "__main__":
    unittest.main()
