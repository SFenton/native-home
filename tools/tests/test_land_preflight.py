"""Tests for tools/land_preflight.py against a temporary git repo."""
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import land_preflight  # noqa: E402

GATE = list(land_preflight.GATE_FILES)


def git(repo, *a):
    subprocess.run(["git", "-C", str(repo), "-c", "user.email=t@t", "-c", "user.name=t", *a], check=True, capture_output=True)


def put(repo, rel, text="x\n"):
    p = repo / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text)


class PreflightTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.repo = Path(self._tmp.name)
        git(self.repo, "init", "-q", "-b", "main")

    def tearDown(self):
        self._tmp.cleanup()

    def base(self, files):
        put(self.repo, "README", "r\n")
        for f in files:
            put(self.repo, f)
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-qm", "base")
        git(self.repo, "checkout", "-q", "-b", "agents/x")

    def commit(self, rel, msg="c"):
        put(self.repo, rel, msg + "\n")
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-qm", msg)

    def run_pf(self, capsys_lines):
        import io, contextlib
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = land_preflight.main(["--head", "agents/x", "--repo", str(self.repo), "--no-fetch"])
        capsys_lines.append(buf.getvalue())
        return rc

    def test_missing_gate_file_exits_3(self):
        self.base([f for f in GATE if f != "tools/lane_land.py"])
        self.commit("a.txt")
        out = []
        self.assertEqual(self.run_pf(out), 3)
        self.assertIn("owner-only:", out[0])
        self.assertIn("tools/lane_land.py", out[0])

    def test_present_exits_0(self):
        self.base(GATE)
        self.commit("a.txt")
        out = []
        self.assertEqual(self.run_pf(out), 0)
        self.assertIn("1 commit(s) ahead", out[0])
        self.assertIn("review recorded: no", out[0])

    def test_app_ui_needs_jev_gate(self):
        self.base(GATE)
        self.commit("apple/Sources/HassUI/A.swift")
        out = []
        self.assertEqual(self.run_pf(out), 3)
        self.assertIn("tools/jev_gate.py", out[0])

    def test_review_file_detected(self):
        self.base(GATE)
        self.commit("a.txt")
        put(self.repo, "build/review/agents__x.json", "{}")
        out = []
        self.run_pf(out)
        self.assertIn("review recorded: yes", out[0])

    def test_many_commits_warn(self):
        self.base(GATE)
        for i in range(land_preflight.AHEAD_WARN + 1):
            self.commit(f"f{i}.txt", f"c{i}")
        out = []
        self.assertEqual(self.run_pf(out), 0)
        self.assertIn("warning: head is 51 commits ahead", out[0])


if __name__ == "__main__":
    unittest.main()
