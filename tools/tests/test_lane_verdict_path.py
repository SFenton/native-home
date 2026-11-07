"""``tools/review/lane_verdict_path.py`` prints ``lane_land``'s own verdict path."""

import contextlib
import io
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "review"))
import lane_land  # noqa: E402
import lane_verdict_path  # noqa: E402

SHA = "0123456789abcdef0123456789abcdef01234567"
GENV = {"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t",
        "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_SYSTEM": "/dev/null"}


def git(cwd, *args):
    return subprocess.run(["git", "-C", str(cwd), *args], capture_output=True, text=True, check=True,
                          env={**os.environ, **GENV}).stdout.strip()


def run(argv, cwd=None):
    out, err = io.StringIO(), io.StringIO()
    old = Path.cwd()
    if cwd:
        os.chdir(cwd)
    try:
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = lane_verdict_path.main(argv)
    finally:
        os.chdir(old)
    return code, out.getvalue(), err.getvalue()


def expected(lane, sha):
    return str(lane_land.review_path(lane_verdict_path.REVIEWS_DIR, lane, sha))


class LaneVerdictPathTests(unittest.TestCase):
    def test_path_equals_lane_land(self):
        code, out, _ = run(["agents/x-1", "--sha", SHA])
        self.assertEqual(code, 0)
        self.assertEqual(out.strip(), expected("agents/x-1", SHA))

    def test_root_option(self):
        code, out, _ = run(["agents/x-1", "--sha", SHA, "--root", "/r"])
        self.assertEqual(code, 0)
        self.assertEqual(out.strip(), str(lane_land.review_path(Path("/r/reviews"), "agents/x-1", SHA)))

    def test_short_sha_rejected(self):
        code, out, err = run(["agents/x-1", "--sha", SHA[:12]])
        self.assertEqual(code, 2)
        self.assertEqual(out, "")
        self.assertIn("40-character", err)

    def test_non_hex_40_char_sha_rejected(self):
        code, out, _ = run(["agents/x-1", "--sha", "g" * 40])
        self.assertEqual(code, 2)
        self.assertEqual(out, "")

    def _repo_with_origin(self, d):
        origin, clone = Path(d) / "origin.git", Path(d) / "clone"
        subprocess.run(["git", "init", "-q", "--bare", str(origin)], check=True)
        subprocess.run(["git", "clone", "-q", str(origin), str(clone)], check=True, capture_output=True)
        git(clone, "commit", "-q", "--allow-empty", "-m", "base")
        return origin, clone

    def test_origin_head_wins_over_local(self):
        with tempfile.TemporaryDirectory() as d:
            _, clone = self._repo_with_origin(d)
            git(clone, "checkout", "-q", "-b", "agents/l")
            git(clone, "commit", "-q", "--allow-empty", "-m", "one")
            git(clone, "push", "-q", "origin", "agents/l")
            pushed = git(clone, "rev-parse", "HEAD")
            git(clone, "commit", "-q", "--allow-empty", "-m", "local only")
            self.assertNotEqual(git(clone, "rev-parse", "agents/l"), pushed)
            code, out, _ = run(["agents/l"], cwd=clone)
        self.assertEqual(code, 0)
        self.assertEqual(out.strip(), expected("agents/l", pushed))

    def test_slashed_lane_only_on_origin(self):
        with tempfile.TemporaryDirectory() as d:
            origin, clone = self._repo_with_origin(d)
            other = Path(d) / "other"
            subprocess.run(["git", "clone", "-q", str(origin), str(other)], check=True, capture_output=True)
            git(other, "checkout", "-q", "-b", "agents/deep/lane")
            git(other, "commit", "-q", "--allow-empty", "-m", "x")
            git(other, "push", "-q", "origin", "agents/deep/lane")
            sha = git(other, "rev-parse", "HEAD")
            code, out, _ = run(["agents/deep/lane"], cwd=clone)
        self.assertEqual(code, 0)
        self.assertEqual(out.strip(), expected("agents/deep/lane", sha))

    def test_unknown_lane_fails(self):
        with tempfile.TemporaryDirectory() as d:
            _, clone = self._repo_with_origin(d)
            code, out, _ = run(["nope"], cwd=clone)
        self.assertEqual(code, 2)
        self.assertEqual(out, "")


if __name__ == "__main__":
    unittest.main()
