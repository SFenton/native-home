"""tools/base_drift.py: local-only commits on the workflow base, without flagging lanes."""

import json
import os
import subprocess
import sys
import unittest
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path
from tempfile import TemporaryDirectory

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import base_drift as b  # noqa: E402

BASE = "claude/uikit-port"
ENV = {**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"}


def git(cwd, *args):
    return subprocess.run(["git", *args], cwd=cwd, env=ENV, capture_output=True, text=True, check=True).stdout.strip()


def commit(cwd, name):
    Path(cwd, name).write_text(name)
    git(cwd, "add", name)
    git(cwd, "commit", "-q", "-m", "add " + name)
    return git(cwd, "rev-parse", "--short", "HEAD")


class BaseDriftTests(unittest.TestCase):
    def repo(self, tmp, remote=True):
        clone = Path(tmp) / "clone"
        clone.mkdir()
        git(clone, "init", "-q", "-b", BASE)
        commit(clone, "seed")
        if remote:
            origin = Path(tmp) / "origin.git"
            git(tmp, "init", "-q", "--bare", str(origin))
            git(clone, "remote", "add", "origin", str(origin))
            git(clone, "push", "-q", "-u", "origin", BASE)
        return clone

    def run_drift(self, clone, *branches, exclude=()):
        out = StringIO()
        with redirect_stdout(out):
            code = b.report(BASE, list(branches), list(exclude), Path(clone))
        return code, out.getvalue()

    def test_local_base_ahead_is_reported_with_exit_3(self):
        with TemporaryDirectory() as tmp:
            clone = self.repo(tmp)
            sha = commit(clone, "local")
            code, out = self.run_drift(clone)
            self.assertEqual(code, 3)
            self.assertIn(sha, out)

    def test_equal_only_origin_ahead_and_no_remote_are_clean(self):
        with TemporaryDirectory() as tmp:
            clone = self.repo(tmp)
            self.assertEqual(self.run_drift(clone)[0], 0)
            commit(clone, "remote")
            git(clone, "push", "-q", "origin", BASE)
            git(clone, "reset", "-q", "--hard", "HEAD~1")
            self.assertEqual(self.run_drift(clone)[0], 0)
        with TemporaryDirectory() as tmp:
            clone = self.repo(tmp, remote=False)
            commit(clone, "local")
            self.assertEqual(self.run_drift(clone)[0], 0)

    def test_missing_local_base_is_clean(self):
        with TemporaryDirectory() as tmp:
            clone = self.repo(tmp)
            git(clone, "switch", "-q", "-c", "other")
            git(clone, "branch", "-q", "-D", BASE)
            self.assertEqual(self.run_drift(clone)[0], 0)

    def test_unlanded_lane_tracking_the_base_is_not_reported(self):
        with TemporaryDirectory() as tmp:
            clone = self.repo(tmp)
            git(clone, "switch", "-q", "-c", "agents/topic-2026-11-05", "origin/" + BASE)
            commit(clone, "lane")
            self.assertEqual(self.run_drift(clone)[0], 0)

    def test_non_lane_branch_tracking_the_base_with_local_commits_is_reported(self):
        with TemporaryDirectory() as tmp:
            clone = self.repo(tmp)
            git(clone, "switch", "-q", "-c", "uikit-port-root", "origin/" + BASE)
            sha = commit(clone, "merged-locally")
            git(clone, "switch", "-q", BASE)
            code, out = self.run_drift(clone)
            self.assertEqual(code, 3)
            self.assertIn("uikit-port-root has 1", out)
            self.assertIn(sha, out)

    def test_non_lane_branch_already_pushed_is_clean(self):
        with TemporaryDirectory() as tmp:
            clone = self.repo(tmp)
            git(clone, "switch", "-q", "-c", "root", "origin/" + BASE)
            commit(clone, "pushed")
            git(clone, "push", "-q", "origin", "root")
            self.assertEqual(self.run_drift(clone)[0], 0)

    def test_lane_named_with_branch_and_local_only_is_reported(self):
        with TemporaryDirectory() as tmp:
            clone = self.repo(tmp)
            git(clone, "switch", "-q", "-c", "agents/topic-2026-11-05", "origin/" + BASE)
            sha = commit(clone, "lane")
            code, out = self.run_drift(clone, "agents/topic-2026-11-05")
            self.assertEqual(code, 3)
            self.assertIn(sha, out)

    def test_excluded_branch_is_skipped_but_the_base_never_is(self):
        with TemporaryDirectory() as tmp:
            clone = self.repo(tmp)
            git(clone, "switch", "-q", "-c", "root", "origin/" + BASE)
            commit(clone, "x")
            self.assertEqual(self.run_drift(clone, exclude=["root"])[0], 0)
            git(clone, "switch", "-q", BASE)
            commit(clone, "base-local")
            self.assertEqual(self.run_drift(clone, exclude=[BASE])[0], 3)

    def test_default_base_comes_from_the_triage_config(self):
        with TemporaryDirectory() as tmp:
            (Path(tmp) / "tools" / "triage").mkdir(parents=True)
            (Path(tmp) / "tools" / "triage" / "config.json").write_text(json.dumps({"workflow_base": "claude/other"}))
            self.assertEqual(b.workflow_base(Path(tmp)), "claude/other")
            self.assertEqual(b.workflow_base(Path(tmp) / "none"), b.FALLBACK_BASE)

    def test_main_uses_the_config_base_and_exits_3(self):
        with TemporaryDirectory() as tmp:
            clone = self.repo(tmp)
            commit(clone, "local")
            out = StringIO()
            old = b.ROOT
            b.ROOT = clone
            try:
                with redirect_stdout(out):
                    self.assertEqual(b.main(["--base", BASE]), 3)
            finally:
                b.ROOT = old


if __name__ == "__main__":
    unittest.main()
