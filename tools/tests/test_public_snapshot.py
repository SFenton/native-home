"""``tools/public_snapshot.py``: the one-commit public snapshot."""

import os
import subprocess
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import mock

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import public_snapshot  # noqa: E402

NEUTRAL = "S+H <noreply@example.com>"


def git(repo, *args):
    return subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True, check=True).stdout.strip()


class SnapshotTests(unittest.TestCase):
    def setUp(self):
        self.tmp = TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.src = self.root / "src"
        self.src.mkdir()
        git(self.src, "init", "-q", "-b", "main")
        git(self.src, "config", "user.name", "Private Person")
        git(self.src, "config", "user.email", "private@example.org")
        git(self.src, "config", "commit.gpgsign", "false")
        (self.src / "a.txt").write_text("a\n")
        (self.src / ".gitleaksignore").write_text("x\n")
        (self.src / "sub").mkdir()
        (self.src / "sub" / "b.txt").write_text("b\n")
        self.commit("private history")
        (self.src / "a.txt").write_text("a2\n")
        self.commit("second")
        self.out = self.root / "out"

    def commit(self, message):
        git(self.src, "add", "--force", "-A")
        git(self.src, "commit", "-q", "-m", message)

    def build(self):
        return public_snapshot.build(self.out, "HEAD", self.src)

    def test_orphan_single_clean_commit(self):
        result = self.build()
        self.assertEqual(git(self.out, "rev-list", "--all", "--count"), "1")
        self.assertEqual(git(self.out, "status", "--porcelain"), "")
        self.assertEqual(git(self.out, "for-each-ref", "--format=%(refname)"), "refs/heads/main")
        self.assertEqual(git(self.out, "remote"), "")
        self.assertEqual(git(self.out, "tag"), "")
        self.assertEqual((self.out / "a.txt").read_text(), "a2\n")
        self.assertEqual(result["files"], 2)

    def test_excluded_paths_absent(self):
        result = self.build()
        self.assertFalse((self.out / ".gitleaksignore").exists())
        self.assertEqual(result["left_out"], [".gitleaksignore"])

    def test_non_empty_out_refused(self):
        self.out.mkdir()
        (self.out / "keep").write_text("x")
        with self.assertRaises(SystemExit):
            self.build()
        self.assertEqual([p.name for p in self.out.iterdir()], ["keep"])

    def test_identity_neutral_against_hostile_environment_and_template(self):
        template = self.root / "tpl"
        (template / "hooks").mkdir(parents=True)
        (template / "hooks" / "pre-commit").write_text("#!/bin/sh\nexit 0\n")
        (template / "config").write_text('[remote "origin"]\n\turl = https://example.org/leak.git\n')
        home = self.root / "home"
        home.mkdir()
        (home / ".gitconfig").write_text(f"[user]\n\tname = Leak\n\temail = leak@example.org\n[init]\n\ttemplateDir = {template}\n")
        hostile = {"GIT_AUTHOR_NAME": "Leak", "GIT_AUTHOR_EMAIL": "leak@example.org", "GIT_COMMITTER_NAME": "Leak",
                   "GIT_COMMITTER_EMAIL": "leakc@example.org", "GIT_TEMPLATE_DIR": str(template), "HOME": str(home),
                   "GIT_DIR": str(self.src / ".git"), "GIT_INDEX_FILE": str(self.root / "idx")}
        with mock.patch.dict(os.environ, hostile):
            self.build()
        self.assertEqual(git(self.out, "log", "-1", "--format=%an <%ae>|%cn <%ce>|%s"), f"{NEUTRAL}|{NEUTRAL}|Initial public snapshot")
        self.assertEqual(git(self.out, "remote"), "")
        self.assertFalse((self.out / ".git" / "hooks" / "pre-commit").exists())
        self.assertEqual(git(self.src, "rev-list", "--count", "HEAD"), "2", "the source repository was not touched")

    def test_reproducible_commit(self):
        self.build()
        first = git(self.out, "rev-parse", "HEAD")
        other = self.root / "out2"
        public_snapshot.build(other, "HEAD", self.src)
        self.assertEqual(git(other, "rev-parse", "HEAD"), first)

    def test_exclude_list_not_widened_by_tree(self):
        (self.src / "tools").mkdir()
        (self.src / "tools" / "public_snapshot.py").write_text("PRIVATE_ONLY = {'a.txt': 'x'}\n")
        (self.src / "public_snapshot_exclude.txt").write_text("a.txt\n")
        self.commit("try to widen")
        self.build()
        self.assertTrue((self.out / "a.txt").exists())

    def test_tracked_file_matching_gitignore_is_kept(self):
        (self.src / ".gitignore").write_text("*.log\n")
        (self.src / "kept.log").write_text("tracked\n")
        self.commit("ignored but tracked")
        result = self.build()
        self.assertIn("kept.log", git(self.out, "ls-files").split("\n"))
        self.assertEqual(result["files"], len(git(self.out, "ls-files").split("\n")))

    def test_export_attributes_do_not_change_the_snapshot(self):
        (self.src / ".gitattributes").write_text("a.txt export-subst\nsub/b.txt export-ignore\n")
        (self.src / "a.txt").write_text("$Format:%ae$\n")
        self.commit("attributes")
        self.build()
        self.assertEqual((self.out / "a.txt").read_text(), "$Format:%ae$\n")
        self.assertTrue((self.out / "sub" / "b.txt").exists())

    def test_executable_bit_and_symlink_survive(self):
        script = self.src / "run.sh"
        script.write_text("#!/bin/sh\n")
        script.chmod(0o755)
        os.symlink("a.txt", self.src / "link")
        self.commit("modes")
        self.build()
        self.assertTrue(os.access(self.out / "run.sh", os.X_OK))
        self.assertEqual(os.readlink(self.out / "link"), "a.txt")

    def test_tampered_snapshot_fails_the_tree_check(self):
        self.build()
        expected = public_snapshot.tree_entries(self.src, "HEAD", public_snapshot.scrubbed_env(self.root))
        expected = [e for e in expected if e[2] not in public_snapshot.PRIVATE_ONLY]
        env = public_snapshot.scrubbed_env(self.root)
        public_snapshot.verify(self.out, expected, env)  # the honest snapshot passes
        (self.out / "a.txt").write_text("tampered\n")
        git(self.out, "add", "-A")
        git(self.out, "-c", "user.name=x", "-c", "user.email=x@x", "commit", "-q", "--amend", "--no-edit")
        with self.assertRaises(SystemExit):
            public_snapshot.verify(self.out, expected, env)

    def test_verify_refuses_leaks(self):
        self.build()
        env = public_snapshot.scrubbed_env(self.root)
        expected = [e for e in public_snapshot.tree_entries(self.out, "HEAD", env)]
        git(self.out, "remote", "add", "origin", "https://example.org/x.git")
        with self.assertRaises(SystemExit):
            public_snapshot.verify(self.out, expected, env)
        git(self.out, "remote", "remove", "origin")
        git(self.out, "tag", "v1")
        with self.assertRaises(SystemExit):
            public_snapshot.verify(self.out, expected, env)
        git(self.out, "tag", "-d", "v1")
        git(self.out, "-c", "user.name=Leak", "-c", "user.email=leak@example.org", "commit", "-q", "--amend", "--no-edit", "--reset-author")
        with self.assertRaises(SystemExit):
            public_snapshot.verify(self.out, expected, env)

    def test_unsafe_paths_and_modes_refused(self):
        env = public_snapshot.scrubbed_env(self.root)
        out = self.root / "o"
        out.mkdir()
        for rel in ("../x", "/abs", "a/../b", ".git/config", "sub/.GIT/x", "", "a//b"):
            with self.assertRaises(SystemExit, msg=rel):
                public_snapshot.safe_path(out, rel)
        for mode in ("160000", "100664", "040000"):
            with self.assertRaises(SystemExit, msg=mode):
                public_snapshot.write_entries(self.src, [(mode, "0" * 40, "x")], out, env)
        os.symlink(self.root, out / "esc")
        with self.assertRaises(SystemExit):
            public_snapshot.safe_path(out, "esc/x")
        self.assertEqual(list(out.iterdir()), [out / "esc"])

    def test_case_and_normalisation_collisions_refused_before_any_write(self):
        outside = self.root / "outside.txt"
        outside.write_text("untouched\n")
        env = public_snapshot.scrubbed_env(self.root)
        sha = "0" * 40
        for pair in (("Link", "link"), ("a/b", "A/b"), ("x", "X/y"), ("café", "café")):
            out = self.root / ("o" + str(abs(hash(pair))))
            out.mkdir()
            entries = [("120000", sha, pair[0]), ("100644", sha, pair[1])]
            with self.assertRaises(SystemExit, msg=str(pair)):
                public_snapshot.write_entries(self.src, entries, out, env)
            self.assertEqual(list(out.iterdir()), [], "nothing written")
        self.assertEqual(outside.read_text(), "untouched\n")

    def test_write_never_follows_an_existing_symlink(self):
        outside = self.root / "outside.txt"
        outside.write_text("untouched\n")
        out = self.root / "o"
        out.mkdir()
        os.symlink(outside, out / "link")
        env = public_snapshot.scrubbed_env(self.root)
        blob = git(self.src, "rev-parse", "HEAD:a.txt")
        with mock.patch.object(public_snapshot, "refuse_collisions"):  # as if the collision check had missed it
            with self.assertRaises(FileExistsError):
                public_snapshot.write_entries(self.src, [("100644", blob, "link")], out, env)
        self.assertEqual(outside.read_text(), "untouched\n")

    def test_submodule_in_tree_refused(self):
        git(self.src, "update-index", "--add", "--cacheinfo", "160000," + "1" * 40 + ",mod")
        git(self.src, "commit", "-q", "-m", "gitlink")
        with self.assertRaises(SystemExit):
            self.build()


if __name__ == "__main__":
    unittest.main()
