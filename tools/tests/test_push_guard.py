"""``tools/hooks/push_guard.py`` and ``tools/review_verdict.py``: review-before-push for SFenton/native-home."""

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
        env = {**ENV, "HOME": self.tmp.name}
        (Path(self.tmp.name) / "hass-agents").mkdir()
        os.replace(self.dir, Path(self.tmp.name) / "hass-agents" / "reviews")
        run = lambda *a: subprocess.run([sys.executable, str(TOOLS / "review_verdict.py"), *a], env=env, capture_output=True, text=True)
        self.assertEqual(run("pass", self.SHA).returncode, 0)
        self.assertEqual(run("pass", "b" * 40).returncode, 1)
        self.assertIn("no independent pass", run("pass", "b" * 40).stderr)
        self.assertEqual(run("remote", NATIVE).stdout.strip(), "native-home")
        self.assertEqual(run().returncode, 2)


class PushGuardTests(unittest.TestCase):
    """Real throwaway repositories; the store is replaced by a set of passed shas."""

    def setUp(self):
        self.tmp = TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.repo = Path(self.tmp.name) / "repo"
        self.repo.mkdir()
        git(self.repo, "init", "-q", "-b", "ci/x")
        (self.repo / "a").write_text("1")
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-q", "-m", "one")
        self.head = git(self.repo, "rev-parse", "HEAD")
        (self.repo / "a").write_text("2")
        git(self.repo, "commit", "-qam", "two")
        self.tip = git(self.repo, "rev-parse", "HEAD")
        git(self.repo, "remote", "add", "origin", NATIVE)
        git(self.repo, "remote", "add", "fest", "https://github.com/SFenton/Fenton-HASS-Native.git")
        git(self.repo, "remote", "add", "disk", "/srv/git/x.git")
        git(self.repo, "remote", "add", "weird", "nonsense")
        self.passed = {self.tip}

    def why(self, command, passed=None, cwd=None):
        shas = self.passed if passed is None else passed
        return push_guard.command_reason(command, str(cwd or self.repo), verdict=lambda sha: sha in shas)

    def test_a_pass_for_the_pushed_head_is_allowed(self):
        for command in ("git push", "git push -u origin ci/x", "git push origin HEAD", "git push origin ci/x:ci/x", "git push -q origin HEAD:refs/heads/ci/y",
                        "git push --force-with-lease origin +HEAD:ci/x", f"git push origin {self.tip}:refs/heads/ci/z", "git push --set-upstream origin ci/x",
                        "cd %s && git push" % self.repo, "git -C %s push origin ci/x" % self.repo, "bash -c 'git push origin ci/x'",
                        "git push --repo=%s HEAD" % NATIVE, "git push git@github.com:SFenton/native-home.git ci/x"):
            with self.subTest(command=command):
                self.assertIsNone(self.why(command, cwd="/" if "-C" in command or "cd " in command else None))

    def test_no_record_a_changes_verdict_or_another_sha_is_refused(self):
        for passed in (set(), {self.head}):
            for command in ("git push", "git push origin HEAD", "git push -u origin ci/x", "git push origin ci/x:ci/y", "bash -c 'sh -c \"git push\"'"):
                with self.subTest(command=command, passed=passed):
                    self.assertIn(self.tip[:12], self.why(command, passed) or "")
        self.assertIsNone(self.why("git push origin %s:ci/old" % self.head, passed={self.head}))
        self.assertIsNotNone(self.why("git push origin HEAD~1:ci/old"))

    def test_other_remotes_and_non_push_commands_are_allowed(self):
        for command in ("git push fest ci/x", "git push https://github.com/SFenton/Fenton-HASS-Native.git HEAD", "git status", "git fetch origin",
                        "echo git push origin", "git commit -m 'git push origin'", "ls"):
            with self.subTest(command=command):
                self.assertIsNone(self.why(command, passed=set()))

    def test_unreadable_remotes_are_refused(self):
        for command in ("git push disk ci/x", "git push weird ci/x", "git push nosuch ci/x", "git push /srv/git/x.git", "git push ssh://host"):
            with self.subTest(command=command):
                self.assertIsNotNone(self.why(command))

    def test_deleting_a_branch_is_allowed_but_main_is_not(self):
        self.assertIsNone(self.why("git push origin :ci/old", passed=set()))
        self.assertIsNone(self.why("git push origin --delete ci/old", passed=set()))
        self.assertIsNone(self.why("git push -d origin ci/old", passed=set()))
        for command in ("git push origin :main", "git push origin --delete main", "git push origin HEAD:main", "git push origin HEAD:refs/heads/master",
                        "git push origin main", "git push origin --delete"):
            with self.subTest(command=command):
                self.assertIsNotNone(self.why(command))

    def test_pushes_that_name_no_single_commit_are_refused(self):
        for command in ("git push --all origin", "git push --mirror origin", "git push origin --tags", "git push --prune origin", "git push origin 'refs/heads/*:refs/heads/*'",
                        "git push origin $BRANCH", "git push origin `git rev-parse HEAD`", "git push origin nosuchref", "git push origin ..",
                        "git -c url.x.insteadOf=y push origin HEAD", "git --git-dir=/x push origin HEAD", "git push origin tag v1", "$G push origin HEAD"):
            with self.subTest(command=command):
                self.assertIsNotNone(self.why(command), command)

    def test_bare_push_uses_the_branch_remote_and_a_detached_head_is_refused(self):
        git(self.repo, "config", "branch.ci/x.pushRemote", "fest")
        self.assertIsNone(self.why("git push", passed=set()))
        git(self.repo, "config", "--unset", "branch.ci/x.pushRemote")
        git(self.repo, "config", "remote.pushDefault", "fest")
        self.assertIsNone(self.why("git push", passed=set()))
        git(self.repo, "config", "--unset", "remote.pushDefault")
        self.assertIsNotNone(self.why("git push", passed=set()))
        git(self.repo, "checkout", "-q", "--detach")
        self.assertIn("detached", self.why("git push", passed={self.tip}))

    def test_a_pushurl_to_native_home_is_gated(self):
        git(self.repo, "remote", "set-url", "--push", "fest", NATIVE)
        self.assertIsNotNone(self.why("git push fest ci/x", passed=set()))

    def test_deep_nesting_and_ship_with_a_moved_home_are_refused(self):
        deep = "git push origin ci/x"
        for _ in range(5):
            deep = "bash -c %s" % json.dumps(deep)
        self.assertIn("nested", self.why(deep))
        self.assertIn("HOME", self.why("HOME=/tmp/x tools/ship.sh 'Add a' --pr"))
        self.assertIsNone(self.why("tools/ship.sh 'Add a' --pr"))

    def test_outside_a_repository_a_gated_push_is_refused(self):
        outside = Path(self.tmp.name) / "outside"
        outside.mkdir()
        self.assertIsNotNone(self.why("git push origin HEAD", cwd=outside))
        self.assertIsNone(self.why("git push https://github.com/SFenton/Fenton-HASS-Native.git HEAD", cwd=outside))


class HookProcessTests(unittest.TestCase):
    """The hook as Claude runs it: a JSON payload on stdin, exit 0 to allow and 2 to refuse, never 1."""

    def setUp(self):
        self.tmp = TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name) / "home"
        self.home.mkdir()
        self.repo = Path(self.tmp.name) / "repo"
        self.repo.mkdir()
        git(self.repo, "init", "-q", "-b", "ci/x")
        (self.repo / "a").write_text("1")
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-q", "-m", "one")
        git(self.repo, "remote", "add", "origin", NATIVE)
        self.head = git(self.repo, "rev-parse", "HEAD")

    def run_hook(self, stdin):
        env = {**ENV, "HOME": str(self.home)}
        return subprocess.run([sys.executable, str(TOOLS / "hooks" / "push_guard.py")], input=stdin, env=env, capture_output=True, text=True)

    def payload(self, command, tool="Bash"):
        return json.dumps({"tool_name": tool, "tool_input": {"command": command}, "cwd": str(self.repo)})

    def test_end_to_end_with_the_real_store(self):
        refused = self.run_hook(self.payload("git push origin HEAD"))
        self.assertEqual(refused.returncode, 2)
        self.assertIn("independent `pass`", refused.stderr)
        record(self.home / "hass-agents" / "reviews", self.head)
        self.assertEqual(self.run_hook(self.payload("git push origin HEAD")).returncode, 0)
        self.assertEqual(self.run_hook(self.payload("git push origin HEAD", tool="Read")).returncode, 0)
        self.assertEqual(self.run_hook(self.payload("ls")).returncode, 0)

    def test_malformed_input_is_refused_never_exit_one(self):
        for stdin in ("", "not json", "[]", "null", "5", json.dumps({"tool_name": "Bash"}), json.dumps({"tool_name": "Bash", "tool_input": []}),
                      json.dumps({"tool_name": "Bash", "tool_input": {"command": ["git", "push"]}}), json.dumps({"tool_name": "Bash", "tool_input": {"command": 5}})):
            with self.subTest(stdin=stdin[:30]):
                done = self.run_hook(stdin)
                self.assertEqual(done.returncode, 2)
                self.assertNotIn("Traceback", done.stderr)

    def test_deep_and_odd_commands_are_refused_without_a_traceback(self):
        deep = "git push origin HEAD"
        for _ in range(8):  # each level doubles the escaping
            deep = "bash -c %s" % json.dumps(deep)
        for command in (deep, "git push origin 'HEAD", "git push " + "x " * 5000, "git push \x00 origin"):
            with self.subTest(command=command[:30]):
                done = self.run_hook(self.payload(command))
                self.assertIn(done.returncode, (0, 2))
                self.assertNotIn("Traceback", done.stderr)
        self.assertEqual(self.run_hook(self.payload(deep)).returncode, 2)

    def test_main_reports_an_internal_error_as_a_refusal(self):
        err = io.StringIO()
        with mock.patch.object(push_guard, "command_reason", side_effect=RuntimeError("x")), mock.patch.object(sys, "stdin", io.StringIO(self.payload("git push"))), \
                contextlib.redirect_stderr(err):
            self.assertEqual(push_guard.main(), 2)
        self.assertIn("could not be checked", err.getvalue())


if __name__ == "__main__":
    unittest.main()
