"""``tools/build_path_check.py``: a branch that adds a ``build/`` path fails; a deletion passes."""

import contextlib
import io
import os
import subprocess
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import build_path_check  # noqa: E402

ENV = {**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t",
       "GIT_COMMITTER_EMAIL": "t@t", "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_SYSTEM": "/dev/null"}


class BuildPathCheckTests(unittest.TestCase):
    def setUp(self):
        self.tmp = TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.repo = os.path.realpath(self.tmp.name)
        self.git("init", "-q", "-b", "main")
        self.write("src.txt", "a\n")
        self.write("build/old.md", "old\n")
        self.commit("base")
        self.git("update-ref", "refs/remotes/origin/main", "HEAD")
        self.git("checkout", "-q", "-b", "lane")

    def git(self, *args):
        return subprocess.run(["git", *args], cwd=self.repo, env=ENV, capture_output=True, text=True, check=True).stdout

    def write(self, name, text):
        path = Path(self.repo) / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def commit(self, message):
        self.git("add", "-A", "-f")
        self.git("commit", "-q", "-m", message)

    def run_main(self, *argv):
        out, err = io.StringIO(), io.StringIO()
        old = os.getcwd()
        os.chdir(self.repo)
        try:
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                code = build_path_check.main(list(argv))
        finally:
            os.chdir(old)
        return code, out.getvalue(), err.getvalue()

    def test_an_added_build_path_fails_and_is_named(self):
        self.write("build/evidence/x.md", "x\n")
        self.write("build/y.png", "y\n")
        self.commit("add")
        code, out, _ = self.run_main()
        self.assertEqual(code, 1)
        self.assertIn("build/evidence/x.md", out)
        self.assertIn("build/y.png", out)

    def test_no_build_add_passes(self):
        self.write("src.txt", "b\n")
        self.write("docs/build/x.md", "x\n")
        self.commit("edit")
        self.assertEqual(self.run_main()[0], 0)

    def test_deleting_or_modifying_a_build_path_the_base_has_passes(self):
        self.write("build/old.md", "changed\n")
        self.commit("modify")
        self.assertEqual(self.run_main()[0], 0)
        self.git("rm", "-q", "build/old.md")
        self.git("commit", "-q", "-m", "delete")
        self.assertEqual(self.run_main()[0], 0)

    def test_an_add_removed_again_in_the_branch_passes(self):
        self.write("build/tmp.md", "x\n")
        self.commit("add")
        self.git("rm", "-q", "build/tmp.md")
        self.git("commit", "-q", "-m", "drop")
        self.assertEqual(self.run_main()[0], 0)

    def test_an_unknown_base_is_exit_2_never_a_pass(self):
        code, _, err = self.run_main("--base", "origin/nope")
        self.assertEqual(code, 2)
        self.assertIn("cannot compare", err)

    def test_the_workflow_runs_the_check_in_the_repo_checks_job(self):
        text = (TOOLS.parent / ".github" / "workflows" / "pr-checks.yml").read_text()
        self.assertIn("tools/build_path_check.py --base", text)
        self.assertLess(text.index("tools/rules_lint.py"), text.index("tools/build_path_check.py"))
        self.assertLess(text.index("tools/build_path_check.py"), text.index("tools/lint_motion.sh"))


if __name__ == "__main__":
    unittest.main()
