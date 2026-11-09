"""``tools/prepush_review.py``: review before push, enforced by git's own pre-push hook against scratch bare repositories.

Real ``git push`` runs through a hook that calls the script; a fake ``ssh`` (GIT_SSH_COMMAND) receives into a scratch bare repository, so a
native-home-shaped URL really pushes somewhere harmless. The verdict store is moved by patching the copy of ``review_verdict.py`` the hook uses.
"""

import json
import os
import shutil
import stat
import subprocess
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import prepush_review  # noqa: E402

NATIVE = "ssh://git@github.com/SFenton/native-home.git"
OTHER = "ssh://git@github.com/SFenton/other-repo.git"
ENV = {**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t",
       "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_SYSTEM": "/dev/null"}
PATCH_FROM = "Path(pwd.getpwuid(os.getuid()).pw_dir)"


def run(cwd, *args, env=None, shell=False):
    cmd = args[0] if shell else list(args)
    return subprocess.run(cmd, cwd=cwd, env=env or ENV, capture_output=True, text=True, shell=shell)


def record(store, sha, verdict="pass"):
    store.mkdir(parents=True, exist_ok=True)
    (store / ("ci__x-%s.json" % sha[:12])).write_text(json.dumps({
        "verdict": verdict, "head": sha, "findings": [], "reviewer": {"agent_type": "reviewer", "session_id": "s"}}))


class Scratch(unittest.TestCase):
    def setUp(self):
        self.tmp = TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.home = root / "home"
        self.store = self.home / "hass-agents" / "reviews"
        tools = root / "tools"
        tools.mkdir()
        shutil.copy(TOOLS / "prepush_review.py", tools)
        text = (TOOLS / "review_verdict.py").read_text()
        assert PATCH_FROM in text
        (tools / "review_verdict.py").write_text(text.replace(PATCH_FROM, "Path(%r)" % str(self.home)))
        hooks = root / "hooks"
        hooks.mkdir()
        hook = hooks / "pre-push"
        # The wiring .githooks/pre-push uses: the arguments and the ref lines on stdin go to the script, isolated (-I).
        hook.write_text('#!/bin/sh\nexec python3 -I %s "$@"\n' % (tools / "prepush_review.py"))
        hook.chmod(hook.stat().st_mode | stat.S_IXUSR)
        self.bare = root / "scratch-remote"
        run(root, "git", "init", "-q", "--bare", "-b", "main", str(self.bare))
        fake = root / "fakessh"
        fake.write_text('#!/bin/sh\nexec git receive-pack %s\n' % self.bare)
        fake.chmod(0o755)
        self.env = {**ENV, "GIT_SSH_COMMAND": str(fake)}
        self.repo = root / "repo"
        self.repo.mkdir()
        self.git("init", "-q", "-b", "ci/x")
        self.git("config", "core.hooksPath", str(hooks))
        self.reviewed = self.commit("one")
        record(self.store, self.reviewed)
        self.git("remote", "add", "origin", NATIVE)

    def git(self, *args):
        return run(self.repo, "git", *args, env=self.env)

    def sh(self, line):
        return run(self.repo, line, env=self.env, shell=True)

    def commit(self, name):
        (self.repo / name).write_text(name)
        self.git("add", "-A")
        self.git("commit", "-q", "-m", name)
        return self.git("rev-parse", "HEAD").stdout.strip()

    def remote_refs(self):
        return run(self.bare, "git", "for-each-ref", "--format=%(refname)").stdout.split()

    def refused(self, done, ref="refs/heads/x"):
        self.assertNotEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertNotIn(ref, self.remote_refs())


class RefusedTests(Scratch):
    """Each way of pushing an unreviewed sha to a native-home url is refused by git itself."""

    def setUp(self):
        super().setUp()
        self.unreviewed = self.commit("two")

    def test_plain_and_refspec_pushes(self):
        for spec in ("HEAD:refs/heads/x", "+HEAD:refs/heads/x", "ci/x:refs/heads/x", "%s:refs/heads/x" % self.unreviewed, "HEAD:x"):
            with self.subTest(spec=spec):
                done = self.git("push", "origin", spec)
                self.refused(done)
                self.assertIn("no independent pass", done.stderr)

    def test_the_reviewed_parent_does_not_cover_the_new_head(self):
        self.refused(self.git("push", "origin", "HEAD:refs/heads/x"))
        self.assertEqual(self.git("push", "origin", "%s:refs/heads/x" % self.reviewed).returncode, 0)  # the reviewed one alone passes

    def test_commit_then_push_in_one_line(self):
        done = self.sh("git commit -q --allow-empty -m three && git push origin HEAD:refs/heads/x")
        self.refused(done)

    def test_a_wildcard_refspec_and_a_default_push_config(self):
        self.refused(self.git("push", "origin", "refs/heads/*:refs/heads/*"), ref="refs/heads/ci/x")
        self.git("config", "remote.origin.push", "HEAD:refs/heads/x")
        self.refused(self.git("push", "origin"))
        self.refused(self.git("push"))

    def test_multiple_pushurls_and_insteadof(self):
        local = str(self.bare)
        self.git("remote", "add", "multi", local)
        self.git("remote", "set-url", "--push", "multi", local)
        self.git("remote", "set-url", "--add", "--push", "multi", NATIVE)
        self.refused(self.git("push", "multi", "HEAD:refs/heads/x"))
        self.git("remote", "add", "innocent", "https://example.org/foo.git")
        self.git("config", "url.%s.insteadOf" % NATIVE.replace(".git", ""), "https://example.org/foo")
        self.refused(self.git("push", "innocent", "HEAD:refs/heads/x"))

    def test_alias_and_eval_and_a_bare_url(self):
        self.git("config", "alias.p", "push origin HEAD:refs/heads/x")
        self.refused(self.git("p"))
        self.refused(self.sh('eval "git push origin HEAD:refs/heads/x"'))
        self.refused(self.git("push", NATIVE, "HEAD:refs/heads/x"))
        self.refused(self.git("push", "git@github.com:sfenton/Native-Home", "HEAD:refs/heads/x"))

    def test_an_annotated_tag_of_an_unreviewed_commit_and_main(self):
        self.git("tag", "-a", "v1", "-m", "t")
        self.refused(self.git("push", "origin", "v1"), ref="refs/tags/v1")
        record(self.store, self.unreviewed)
        self.refused(self.git("push", "origin", "HEAD:refs/heads/main"), ref="refs/heads/main")
        self.refused(self.git("push", "origin", ":refs/heads/main"), ref="refs/heads/none")

    def test_a_changes_verdict_or_a_record_for_another_head_is_not_a_pass(self):
        other = self.commit("three")
        record(self.store, other, verdict="changes")
        self.refused(self.git("push", "origin", "HEAD:refs/heads/x"))


class AllowedTests(Scratch):
    def test_a_reviewed_sha_passes_and_the_remote_receives_it(self):
        done = self.git("push", "origin", "HEAD:refs/heads/x")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn("refs/heads/x", self.remote_refs())

    def test_a_reviewed_annotated_tag_passes(self):
        self.git("tag", "-a", "v1", "-m", "t")
        self.assertEqual(self.git("push", "origin", "v1").returncode, 0)

    def test_deleting_a_branch_passes_without_a_record(self):
        self.assertEqual(self.git("push", "origin", "HEAD:refs/heads/x").returncode, 0)
        self.commit("unreviewed")
        done = self.git("push", "origin", ":refs/heads/x")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertNotIn("refs/heads/x", self.remote_refs())

    def test_another_remote_passes_unreviewed(self):
        self.commit("unreviewed")
        self.git("remote", "add", "other", OTHER)
        done = self.git("push", "other", "HEAD:refs/heads/x")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.git("remote", "add", "disk", str(self.bare))
        self.assertEqual(self.git("push", "disk", "HEAD:refs/heads/y").returncode, 0)


class RealHookTests(Scratch):
    """The repository's own ``.githooks/pre-push``, with a stub denylist script that records the ref lines it was fed."""

    def setUp(self):
        super().setUp()
        root = Path(self.tmp.name) / "wired"
        (root / ".githooks").mkdir(parents=True)
        (root / "tools").mkdir()
        shutil.copy(TOOLS.parent / ".githooks" / "pre-push", root / ".githooks" / "pre-push")
        for name in ("prepush_review.py", "review_verdict.py"):
            shutil.copy(Path(self.tmp.name) / "tools" / name, root / "tools" / name)  # the copies with the fake account home
        self.seen = root / "denylist-saw.txt"
        (root / "tools" / "prepush_denylist.py").write_text(
            "import sys\nopen(%r, 'w').write(sys.stdin.read())\n" % str(self.seen))
        self.git("config", "core.hooksPath", str(root / ".githooks"))

    def test_the_review_runs_first_and_a_failure_stops_the_push(self):
        self.commit("unreviewed")
        done = self.git("push", "origin", "HEAD:refs/heads/x")
        self.refused(done)
        self.assertIn("no independent pass", done.stderr)
        self.assertFalse(self.seen.exists(), "the denylist ran although the review refused")

    def test_a_reviewed_push_reaches_the_denylist_with_the_same_stdin(self):
        done = self.git("push", "origin", "HEAD:refs/heads/x")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn("refs/heads/x", self.seen.read_text())
        self.assertIn(self.reviewed, self.seen.read_text())

    def owner_push(self, value="1"):
        self.env = {**self.env, "SH_OWNER_PUSH": value}
        return self.git("push", "origin", "HEAD:refs/heads/x")

    def test_the_owner_escape_skips_the_review_but_the_denylist_still_runs(self):
        unreviewed = self.commit("unreviewed")
        done = self.owner_push()
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn(unreviewed, self.seen.read_text(), "the denylist did not run on the owner's push")
        self.assertIn("refs/heads/x", self.remote_refs())

    def test_the_owner_escape_still_refuses_on_a_denylist_hit(self):
        self.commit("unreviewed")
        (self.seen.parent / "tools" / "prepush_denylist.py").write_text("import sys\nsys.stdin.read()\nsys.exit(1)\n")
        self.refused(self.owner_push())

    def test_without_the_exact_escape_value_behaviour_is_unchanged(self):
        self.commit("unreviewed")
        for value in ("", "0", "true", "yes"):
            with self.subTest(value=value):
                done = self.owner_push(value)
                self.refused(done)
                self.assertIn("no independent pass", done.stderr)
                self.assertFalse(self.seen.exists())


class HookTextTests(unittest.TestCase):
    def test_the_real_hook_feeds_stdin_to_the_review_before_the_denylist_and_fails_closed(self):
        text = (TOOLS.parent / ".githooks" / "pre-push").read_text()
        review = text.index("tools/prepush_review.py")
        denylist = text.index("tools/prepush_denylist.py", text.index("python3 -I"))
        self.assertLess(review, denylist)
        self.assertRegex(text, r'cat > "\$refs"')
        self.assertRegex(text, r'prepush_review\.py" "\$@" < "\$refs" \|\| exit 1')
        self.assertRegex(text, r'prepush_denylist\.py" "\$@" < "\$refs"')
        self.assertIn("python3 -I", text)


class UnitTests(unittest.TestCase):
    def setUp(self):
        self.tmp = TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.store = Path(self.tmp.name)
        self.sha = "a" * 40
        self.resolve = lambda sha: sha if len(sha) == 40 else None

    def why(self, url, lines, **kw):
        return prepush_review.refusal(url, url, lines, store=self.store, resolve=self.resolve, urls=[url], **kw)

    def line(self, sha=None, ref="refs/heads/x"):
        return "refs/heads/ci/x %s %s %s" % (sha or self.sha, ref, "0" * 40)

    def test_url_forms_are_normalised(self):
        for url in ("git@github.com:SFenton/native-home.git", "https://github.com/sfenton/NATIVE-HOME", "https://u@github.com/SFenton/native-home.git/",
                    "ssh://git@github.com:22/SFenton/native-home.git", "alias:SFenton/native-home"):
            with self.subTest(url=url):
                self.assertIn("no independent pass", self.why(url, [self.line()]))
        record(self.store, self.sha)
        self.assertIsNone(self.why("git@github.com:SFenton/native-home.git", [self.line()]))

    def test_other_and_local_are_not_gated_and_unknown_fails_closed(self):
        self.assertIsNone(self.why("git@github.com:SFenton/other.git", [self.line()]))
        self.assertIsNone(self.why("/srv/git/x.git", [self.line()]))
        self.assertIn("not a form", self.why("nonsense", [self.line()]))

    def test_malformed_input_is_a_refusal_never_a_crash(self):
        url = NATIVE
        self.assertIn("unreadable", self.why(url, ["only three fields"]))
        self.assertIn("not a commit", self.why(url, ["r short x " + "0" * 40]))
        self.assertIsNone(self.why(url, ["", "  "]))
        err = subprocess.run([sys.executable, "-I", str(TOOLS / "prepush_review.py")], input="x", capture_output=True, text=True)
        self.assertEqual(err.returncode, 1)  # wrong arguments
        err = subprocess.run([sys.executable, "-I", str(TOOLS / "prepush_review.py"), "origin", NATIVE], input="garbage line\n", capture_output=True, text=True)
        self.assertEqual(err.returncode, 1)
        self.assertNotIn("Traceback", err.stderr)

    def test_deleting_main_is_refused_and_deleting_another_is_not(self):
        zero = "refs/heads/x %s refs/heads/%s %s" % ("0" * 40, "%s", "1" * 40)
        self.assertIn("main", self.why(NATIVE, [zero % "main"]))
        self.assertIn("master", self.why(NATIVE, [zero % "master"]))
        self.assertIsNone(self.why(NATIVE, [zero % "feature"]))

    def test_the_store_is_the_password_database_home_not_home_env(self):
        text = (TOOLS / "review_verdict.py").read_text()
        self.assertIn("pwd.getpwuid(os.getuid()).pw_dir", text)
        self.assertNotIn("Path.home()", text)
        self.assertNotIn("expanduser", text)


if __name__ == "__main__":
    unittest.main()
