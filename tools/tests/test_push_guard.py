"""``tools/review_verdict.py`` (the verdict reader) and ``tools/hooks/push_guard.py`` (the token scan that keeps commands from going around git's pre-push hook)."""

import contextlib
import io
import json
import os
import subprocess
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import mock

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS / "hooks"))
sys.path.insert(0, str(TOOLS))
import push_guard  # noqa: E402
import review_verdict  # noqa: E402

ENV = {**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t",
       "GIT_COMMITTER_EMAIL": "t@t", "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_SYSTEM": "/dev/null"}
NATIVE = "git@github.com:SFenton/native-home.git"


def git(cwd, *args):
    return subprocess.run(["git", *args], cwd=cwd, env=ENV, capture_output=True, text=True, check=True).stdout.strip()


def record(folder, sha, verdict="pass", branch="ci__x", head=None, findings=(), reviewer=True):
    """Write a verdict record the way ``record.py --lane`` does."""
    data = {"verdict": verdict, "head": head or sha, "branch": "ci/x", "findings": list(findings)}
    if reviewer:
        data["reviewer"] = {"agent_type": "reviewer", "session_id": "s1"}
    folder.mkdir(parents=True, exist_ok=True)
    (folder / ("%s-%s.json" % (branch, sha[:12]))).write_text(json.dumps(data))


class VerdictTests(unittest.TestCase):
    SHA = "a" * 40

    def setUp(self):
        self.tmp = TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name) / "reviews"

    def test_a_pass_for_the_exact_head_counts(self):
        record(self.dir, self.SHA)
        self.assertTrue(review_verdict.has_pass(self.SHA, self.dir))

    def test_everything_else_is_a_no(self):
        self.assertFalse(review_verdict.has_pass(self.SHA, self.dir))  # no store
        record(self.dir, self.SHA, verdict="changes")
        self.assertFalse(review_verdict.has_pass(self.SHA, self.dir))
        record(self.dir, self.SHA, head="b" * 40)  # record names another head
        self.assertFalse(review_verdict.has_pass(self.SHA, self.dir))
        other = "a" * 12 + "c" * 28  # same sha12, different commit
        record(self.dir, other)
        self.assertFalse(review_verdict.has_pass(self.SHA, self.dir))
        self.assertTrue(review_verdict.has_pass(other, self.dir))

    def test_identity_findings_and_shape_are_checked(self):
        record(self.dir, self.SHA, reviewer=False)
        self.assertFalse(review_verdict.has_pass(self.SHA, self.dir))
        record(self.dir, self.SHA, findings=[{"severity": "major"}])
        self.assertFalse(review_verdict.has_pass(self.SHA, self.dir))
        record(self.dir, self.SHA, findings=["x"])
        self.assertFalse(review_verdict.has_pass(self.SHA, self.dir))
        record(self.dir, self.SHA, findings=[{"severity": "minor"}])
        self.assertTrue(review_verdict.has_pass(self.SHA, self.dir))
        (self.dir / ("ci__x-%s.json" % self.SHA[:12])).write_text("[1]")
        self.assertFalse(review_verdict.has_pass(self.SHA, self.dir))
        (self.dir / ("ci__x-%s.json" % self.SHA[:12])).write_text("{not json")
        self.assertFalse(review_verdict.has_pass(self.SHA, self.dir))

    def test_malformed_shas_never_pass(self):
        record(self.dir, self.SHA)
        for sha in ("", "a" * 12, "A" * 40, "a" * 41, "../" + "a" * 37, None, 5):
            self.assertFalse(review_verdict.has_pass(sha, self.dir), sha)

    def test_remote_kinds(self):
        native = ("git@github.com:SFenton/native-home.git", "https://github.com/SFenton/native-home", "https://github.com/sfenton/Native-Home.git/",
                  "ssh://git@github.com/SFenton/native-home.git", "https://user@github.com/SFenton/native-home.git", "gh-alias:SFenton/native-home")
        for url in native:
            self.assertEqual(review_verdict.remote_kind(url), "native-home", url)
        for url in ("https://github.com/SFenton/Fenton-HASS-Native.git", "git@github.com:other/native-home.git", "https://github.com/SFenton/native-home-x"):
            self.assertEqual(review_verdict.remote_kind(url), "other", url)
        for url in ("/srv/git/x.git", "./x", "~/x", "file:///x"):
            self.assertEqual(review_verdict.remote_kind(url), "local", url)
        for url in ("", "   ", "origin", "https://github.com/SFenton", "git@github.com:native-home", "https://x/ a/b", "a\nb"):
            self.assertEqual(review_verdict.remote_kind(url), "unknown", repr(url))

    def test_cli(self):
        record(self.dir, self.SHA)
        with mock.patch.object(review_verdict, "reviews_dir", return_value=self.dir):
            self.assertEqual(review_verdict.main(["pass", self.SHA]), 0)
            err = io.StringIO()
            with contextlib.redirect_stderr(err):
                self.assertEqual(review_verdict.main(["pass", "b" * 40]), 1)
                self.assertEqual(review_verdict.main([]), 2)
            self.assertIn("no independent pass", err.getvalue())
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            review_verdict.main(["remote", NATIVE])
        self.assertEqual(out.getvalue().strip(), "native-home")


SETTINGS = json.loads((TOOLS.parent / ".claude" / "settings.json").read_text())


class TokenScanTests(unittest.TestCase):
    """push_guard is a token scan: a match anywhere in the command text is a refusal."""

    def why(self, command):
        return push_guard.command_reason(command)

    def test_each_way_around_the_hook_is_refused(self):
        for command in ("git push --no-verify origin x", "git push --no-verif", "git push --no-v origin", "git push origin x --no-verify",
                        "echo 'git push --no-verify'", "git -c core.hooksPath=/dev/null push", "git -c core.hookspath=/x push", "git config core.hooksPath /x",
                        "git config --global core.hooksPath /x", "git config --unset core.hooksPath",
                        "GIT_CONFIG_PARAMETERS=\"'core.hookspath=/x'\" git push", "GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath git push",
                        "GIT_CONFIG_GLOBAL=/tmp/c git push", "git --config-env=core.hooksPath=V push", "git send-pack /x HEAD", "git-send-pack /x", "git http-push x",
                        "GIT_DIR=/x git push", "git --git-dir=/x push origin", "git --git-dir /x push origin", "FOO=1 GIT_DIR=/x git push",
                        "gh api -X PUT repos/o/r/git/refs/heads/x", "gh api repos/o/r/git/refs -f ref=refs/heads/x -f sha=1", "gh api --method POST repos/o/r/merges -f base=x",
                        "gh api repos/o/r/contents/a.txt -X PUT -f message=m", "gh api repos/o/r/contents/a -F content=@f", "gh api repos/o/r/git/refs/heads/x --method=DELETE",
                        "gh api repos/o/r/git/refs/heads/x --input body.json", "gh -R o/r api repos/o/r/merges -X POST", "gh repo sync", "gh repo sync o/r --force", "gh -R o/r repo sync"):
            with self.subTest(command=command):
                self.assertTrue(self.why(command), command)

    def test_every_form_that_sets_the_owner_escape_is_refused(self):
        """SH_OWNER_PUSH skips the review step in the pre-push hook; no agent command may name it, git or not."""
        for command in ("SH_OWNER_PUSH=1 git push origin x", "export SH_OWNER_PUSH=1", "export SH_OWNER_PUSH=1; git push", "env SH_OWNER_PUSH=1 git push",
                        "env -i SH_OWNER_PUSH=1 git push", "bash -c 'SH_OWNER_PUSH=1 git push'", "sh -c \"export SH_OWNER_PUSH=1 && git push\"",
                        "sh_owner_push=1 git push", "SH_OWNER_PUSH=0 git push", "declare -x SH_OWNER_PUSH=1", "echo SH_OWNER_PUSH=1 >> ~/.zshenv",
                        "python3 -c \"import os; os.environ['SH_OWNER_PUSH']='1'\"", "cat <<EOF > x\nSH_OWNER_PUSH=1\nEOF"):
            with self.subTest(command=command):
                self.assertIn("SH_OWNER_PUSH", self.why(command))

    def test_every_way_of_unsetting_an_agent_marker_is_refused(self):
        """The pre-push hook ignores the escape while a marker is set, so an agent command may not clear one, git or not."""
        for command in ("unset CLAUDECODE", "unset CLAUDECODE; git push", "unset FOO CLAUDE_CODE_ENTRYPOINT", "env -u CLAUDECODE git push",
                        "env -u FENTON_HEADLESS -u CLAUDECODE git push", "env --unset=FENTON_HEADLESS git push", "env --unset CLAUDECODE true",
                        "env -i PATH=/usr/bin git push", "env -i git push", "env -ik git push", "env --ignore-environment git push", "env - git push",
                        "exec -c git push", "CLAUDECODE= git push", "CLAUDECODE='' git push", 'CLAUDECODE="" git push', "FENTON_HEADLESS= git push",
                        "export CLAUDE_CODE_ENTRYPOINT=", "export CLAUDECODE=; git push", "bash -c 'CLAUDECODE= git push'", "env CLAUDECODE= git push",
                        "env CLAUDE_CODE_ENTRYPOINT='' git push", "claudecode= git push", "python3 -c \"import os; os.environ['CLAUDECODE']=''\""):
            with self.subTest(command=command):
                self.assertIn("agent-session marker", self.why(command))

    def test_setting_or_reading_a_marker_is_not_clearing_it(self):
        for command in ("CLAUDECODE=1 git push origin x", "echo $CLAUDECODE", "grep CLAUDECODE tools/hooks/x.py", "git grep FENTON_HEADLESS",
                        "env FENTON_HEADLESS=1 git status", "git log --grep=CLAUDECODE"):
            with self.subTest(command=command):
                self.assertEqual(self.why(command), "", command)

    def test_read_only_searches_for_the_guarded_names_pass(self):
        for command in ("grep SH_OWNER_PUSH tools/hooks/push_guard.py", "grep -rn SH_OWNER_PUSH .", "git grep SH_OWNER_PUSH", "git log -S SH_OWNER_PUSH --oneline",
                        "git grep include.path", "git grep -n includeIf tools", "git log -S include.path", "git log --grep include.path --oneline"):
            with self.subTest(command=command):
                self.assertEqual(self.why(command), "", command)

    def test_writes_of_the_guarded_names_are_still_refused(self):
        for command in ("git config include.path /tmp/c", "git config --add include.path /tmp/c", "git -c include.path=/tmp/c status",
                        "git grep x; git config include.path /tmp/c", "grep x f; export SH_OWNER_PUSH", "grep x f && SH_OWNER_PUSH=1 git push",
                        "git log -S x; env SH_OWNER_PUSH=1 true"):
            with self.subTest(command=command):
                self.assertTrue(self.why(command), command)

    def test_include_paths_are_refused_like_hooks_path(self):
        for command in ("git config include.path /tmp/c", "git -c include.path=/tmp/c push", "git config --global includeIf.gitdir:/x/.path /tmp/c",
                        "git config includeif.gitdir:/x/.path /tmp/c"):
            with self.subTest(command=command):
                self.assertIn("include.path", self.why(command))

    def test_ordinary_commands_pass(self):
        for command in ("git push origin HEAD", "git push -u origin ci/x", "git status", "git commit -m 'Add x'", "ls -la", "python3 tools/run_tool_tests.sh",
                        "gh api repos/o/r/git/refs/heads/x", "gh api repos/o/r/contents/a.txt", "gh api repos/o/r/pulls/1", "gh api repos/o/r/issues -f title=x",
                        "gh pr view 1", "gh repo view o/r", "git diff --no-index a b", "git log --no-merges", "echo hi", "GIT_DIR=/x git status", "git --git-dir=/x log"):
            with self.subTest(command=command):
                self.assertEqual(self.why(command), "", command)

    def test_the_push_is_not_parsed_here(self):
        """No refspec, remote or sha logic: the pre-push hook decides (tools/prepush_review.py)."""
        for name in ("check_push", "operands", "remote_url", "default_remote", "run_git", "review_verdict"):
            self.assertFalse(hasattr(push_guard, name), name)


class HookProcessTests(unittest.TestCase):
    """The hook as Claude runs it: a JSON payload on stdin, exit 0 to allow and 2 to refuse, never 1."""

    def run_hook(self, stdin, script=None):
        return subprocess.run([sys.executable, str(script or TOOLS / "hooks" / "push_guard.py")], input=stdin, capture_output=True, text=True)

    def payload(self, command, tool="Bash"):
        return json.dumps({"tool_name": tool, "tool_input": {"command": command}})

    def test_allow_and_refuse(self):
        self.assertEqual(self.run_hook(self.payload("git push origin HEAD")).returncode, 0)
        self.assertEqual(self.run_hook(self.payload("git push --no-verify")).returncode, 2)
        self.assertEqual(self.run_hook(self.payload("git push --no-verify", tool="Read")).returncode, 0)
        refused = self.run_hook(self.payload("git -c core.hooksPath=/x push"))
        self.assertEqual(refused.returncode, 2)
        self.assertIn("pre-push hook", refused.stderr)

    def test_malformed_input_is_refused_never_exit_one(self):
        for stdin in ("", "not json", "[]", "null", "5", json.dumps({"tool_name": "Bash"}), json.dumps({"tool_name": "Bash", "tool_input": []}),
                      json.dumps({"tool_name": "Bash", "tool_input": {"command": ["git", "push"]}}), json.dumps({"tool_name": "Bash", "tool_input": {"command": 5}})):
            with self.subTest(stdin=stdin[:30]):
                done = self.run_hook(stdin)
                self.assertEqual(done.returncode, 2)
                self.assertNotIn("Traceback", done.stderr)

    def test_huge_and_odd_commands_do_not_crash(self):
        for command in ("git push " + "x " * 20000, "git push \x00 origin", "git " * 5000 + "push --no-verify"):
            with self.subTest(command=command[:30]):
                done = self.run_hook(self.payload(command))
                self.assertIn(done.returncode, (0, 2))
                self.assertNotIn("Traceback", done.stderr)

    def test_main_reports_an_internal_error_as_a_refusal(self):
        err = io.StringIO()
        with mock.patch.object(push_guard, "command_reason", side_effect=RuntimeError("x")), mock.patch.object(sys, "stdin", io.StringIO(self.payload("git push"))), \
                contextlib.redirect_stderr(err):
            self.assertEqual(push_guard.main(), 2)
        self.assertIn("could not be checked", err.getvalue())


class SettingsWiringTests(unittest.TestCase):
    """The command .claude/settings.json runs: a missing or broken push_guard.py is exit 2, never a silent pass or exit 1."""

    def command(self):
        for group in SETTINGS["hooks"]["PreToolUse"]:
            for hook in group["hooks"]:
                if "push_guard.py" in hook["command"]:
                    return hook["command"]
        self.fail("push_guard is not wired")

    def run_wired(self, project):
        env = {**os.environ, "CLAUDE_PROJECT_DIR": str(project)}
        payload = json.dumps({"tool_name": "Bash", "tool_input": {"command": "git push --no-verify"}})
        return subprocess.run(["sh", "-c", self.command()], input=payload, env=env, capture_output=True, text=True)

    def test_wired_to_the_real_script_and_refuses(self):
        done = self.run_wired(TOOLS.parent)
        self.assertEqual(done.returncode, 2, done.stderr)

    def test_a_missing_script_fails_closed(self):
        with TemporaryDirectory() as tmp:
            done = self.run_wired(tmp)
            self.assertEqual(done.returncode, 2)
            self.assertIn("missing", done.stderr)

    def test_an_import_or_syntax_error_in_the_script_fails_closed(self):
        with TemporaryDirectory() as tmp:
            (Path(tmp) / "tools" / "hooks").mkdir(parents=True)
            (Path(tmp) / "tools" / "hooks" / "push_guard.py").write_text("import nonexistent_module_x\n")
            self.assertEqual(self.run_wired(tmp).returncode, 2)
            (Path(tmp) / "tools" / "hooks" / "push_guard.py").write_text("def broken(:\n")
            self.assertEqual(self.run_wired(tmp).returncode, 2)

    def test_the_script_itself_imports_only_the_standard_library(self):
        text = (TOOLS / "hooks" / "push_guard.py").read_text()
        for line in text.splitlines():
            if line.startswith(("import ", "from ")) and "__future__" not in line:
                self.assertEqual(line.split()[1], "sys", line)


if __name__ == "__main__":
    unittest.main()
