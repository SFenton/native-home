"""Hub provenance in ``tools/mockups_hub.py``: the built/published stamps and the refusal to replace a newer hub."""

import io
import json
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import mockups_hub as hub  # noqa: E402


class HubStampTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name)
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.email", "t@example.com")
        self.git("config", "user.name", "t")
        self.main_sha = self.commit("one")
        page = self.root / "build/mockups-hub/a/x.html"
        page.parent.mkdir(parents=True)
        page.write_text("<!doctype html>")
        (self.root / "build/mockups-hub/index.html").write_text("<!doctype html>")
        self.files = {"a/x.html": page}
        patches = [mock.patch.object(hub, "ROOT", self.root), mock.patch.object(hub, "build", return_value=self.files),
                   mock.patch.object(hub, "OUT", self.root / "build/mockups-hub")]
        for p in patches:
            p.start()
            self.addCleanup(p.stop)

    def git(self, *args):
        return subprocess.run(["git", "-C", str(self.root), *args], capture_output=True, text=True, check=True).stdout.strip()

    def commit(self, name):
        (self.root / name).write_text(name)
        self.git("add", name)
        self.git("commit", "-q", "-m", name)
        return self.git("rev-parse", "HEAD")

    def run_main(self, *argv):
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            code = hub.main(list(argv))
        return code, out.getvalue(), err.getvalue()

    def read(self, name):
        return json.loads((self.root / "build" / name).read_text())

    def publish_from(self, branch, sha):
        (self.root / "build/mockups-hub.published.json").write_text(json.dumps({"branch": branch, "sha": sha}))

    def test_build_writes_the_stamp_and_prints_branch_and_sha(self):
        """Fails if: the build writes no branch and head sha beside the old stamp, or prints no `built from branch@sha7, N pages` line."""
        code, out, _ = self.run_main()
        self.assertEqual(code, 0)
        self.assertEqual(self.read("mockups-hub.built.json"), {"branch": "main", "sha": self.main_sha})
        self.assertIn(f"built from main@{self.main_sha[:7]}, 2 pages", out)
        self.assertTrue((self.root / "build/mockups-hub.built").is_file(), "the old mtime stamp the Stop hook reads must stay")

    def test_batches_keeps_stdout_json(self):
        """Fails if: the provenance line lands on stdout in --batches mode and breaks the JSON."""
        code, out, err = self.run_main("--batches")
        self.assertEqual(code, 0)
        json.loads(out)
        self.assertIn("built from main@", err)

    def test_older_build_is_refused(self):
        """Fails if: a build from a head that does not contain the published commit exits 0 without --allow-older, or prints no branch and sha."""
        self.git("checkout", "-q", "-b", "lane")
        lane_sha = self.commit("lane")
        self.git("checkout", "-q", "main")
        self.publish_from("lane", lane_sha)
        code, _, err = self.run_main("--batches")
        self.assertEqual(code, 1)
        self.assertIn(f"lane@{lane_sha[:7]}", err)
        self.assertIn("--allow-older", err)
        self.assertFalse((self.root / "build/mockups-hub.built.json").exists(), "a refused build must not touch the stamps")

    def test_rebase_on_the_same_branch_is_not_refused(self):
        """Fails if: a rebased or amended build on the same branch (published commit no longer an ancestor) is refused."""
        self.git("checkout", "-q", "-b", "lane")
        old = self.commit("lane")
        self.git("reset", "-q", "--hard", "HEAD~1")
        self.commit("lane2")
        self.publish_from("lane", old)
        self.assertEqual(self.run_main()[0], 0)

    def test_allow_older_passes(self):
        """Fails if: --allow-older still refuses."""
        self.git("checkout", "-q", "-b", "lane")
        lane_sha = self.commit("lane")
        self.git("checkout", "-q", "main")
        self.publish_from("lane", lane_sha)
        code, _, _ = self.run_main("--allow-older")
        self.assertEqual(code, 0)

    def test_newer_head_replaces_without_a_flag(self):
        """Fails if: a build whose head contains the published commit is refused."""
        self.publish_from("main", self.main_sha)
        self.commit("two")
        self.assertEqual(self.run_main()[0], 0)

    def test_mark_published_records_the_built_pair(self):
        """Fails if: --mark-published does not copy the built pair, so the next build cannot compare against it."""
        self.run_main()
        code, out, _ = self.run_main("--mark-published")
        self.assertEqual(code, 0)
        self.assertEqual(self.read("mockups-hub.published.json"), {"branch": "main", "sha": self.main_sha})
        self.assertTrue((self.root / "build/mockups-hub.published").is_file())
        self.assertIn(self.main_sha[:7], out)


if __name__ == "__main__":
    unittest.main()
