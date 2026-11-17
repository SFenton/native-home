"""``tools/bg_run.py``: a refused ``killpg`` still ends in exit 124 and a digest, and the digest's sha and lane come from the command's cwd."""

import os
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path
from unittest import mock

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import bg_run  # noqa: E402


def git(directory, *args):
    return subprocess.run(["git", *args], cwd=directory, capture_output=True, text=True, check=True).stdout.strip()


class FakeKillpg:
    """Stands in for ``os.killpg``: raises ``PermissionError`` for a real signal, answers the liveness probe (signal 0) as gone."""

    def __init__(self):
        self.calls = []

    def __call__(self, pgid, sig):
        self.calls.append((pgid, int(sig)))
        if int(sig) == 0:
            raise ProcessLookupError
        raise PermissionError("operation not permitted")


class KillFallbackTests(unittest.TestCase):
    def test_a_killpg_permission_error_still_gives_exit_124_and_a_digest(self):
        """Fails if: PermissionError escapes kill_group, the hung command survives, or no digest is written."""
        fake = FakeKillpg()
        with tempfile.TemporaryDirectory() as tmp, mock.patch.object(bg_run.os, "killpg", fake), redirect_stdout(StringIO()):
            status = bg_run.main(["hang", "--dir", tmp, "--timeout", "1", "--", "sleep", "30"])
            digest = (Path(tmp) / "hang.digest").read_text()
        self.assertEqual(status, 124)
        self.assertTrue(digest.strip())
        self.assertTrue(fake.calls)

    def test_kill_group_falls_back_to_killing_the_leader(self):
        """Fails if: the leader keeps running after killpg is refused."""
        process = subprocess.Popen(["sleep", "30"], start_new_session=True)
        try:
            with mock.patch.object(bg_run.os, "killpg", FakeKillpg()):
                bg_run.kill_group(process, grace=0.2)
            self.assertIsNotNone(process.poll())
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()


class CwdStampTests(unittest.TestCase):
    def test_a_command_run_in_another_worktree_stamps_that_worktrees_sha_and_lane(self):
        """Fails if: the digest carries the launching checkout's sha or lane, not the command's cwd."""
        with tempfile.TemporaryDirectory() as tmp:
            other = Path(tmp) / "other-lane"
            other.mkdir()
            git(other, "init", "-q")
            git(other, "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "--allow-empty", "-m", "x")
            sha = git(other, "rev-parse", "--short=8", "HEAD")
            logs = Path(tmp) / "logs"
            with redirect_stdout(StringIO()):
                status = bg_run.run("stamp", ["true"], logs, None, cwd=str(other))
            digest = (logs / "stamp.digest").read_text()
        self.assertEqual(status, 0)
        self.assertIn(sha, digest)
        self.assertIn("other-lane", digest)

    def test_the_default_cwd_is_the_current_directory(self):
        """Fails if: a run with no cwd stamps the bg_run script's checkout instead of where it was launched."""
        with tempfile.TemporaryDirectory() as tmp:
            here = Path(tmp) / "here-lane"
            here.mkdir()
            git(here, "init", "-q")
            git(here, "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "--allow-empty", "-m", "x")
            old = os.getcwd()
            os.chdir(here)
            try:
                with redirect_stdout(StringIO()):
                    bg_run.run("here", ["true"], Path(tmp) / "logs", None)
            finally:
                os.chdir(old)
            digest = (Path(tmp) / "logs" / "here.digest").read_text()
        self.assertIn("here-lane", digest)


if __name__ == "__main__":
    unittest.main()
