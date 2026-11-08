"""The pre-push denylist hook (``.githooks/pre-push`` -> ``tools/prepush_denylist.py``), ``tools/setup.sh`` and the push rules of
``commit_guard``. Temp repos and a fake denylist through ``HOUSE_SCAN_DENYLIST``; ``HOME`` is a temp dir so no real list is found.
The fake terms are made-up words."""

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "hooks"))
sys.path.insert(0, str(ROOT / "tools"))
import commit_guard  # noqa: E402

HOOK = ROOT / ".githooks" / "pre-push"
ZERO = "0" * 40
PUBLIC = "git@github.com:SFenton/native-home.git"
OTHER = "git@github.com:someone/else.git"
TERMS = [f"zorblax{i}" for i in range(25)]


class Repo:
    """A temp repo with a fake denylist and helpers to commit and run the hook."""

    def __init__(self, terms=TERMS):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = self.tmp.name
        self.work = os.path.join(self.dir, "work")
        os.mkdir(self.work)
        self.list = os.path.join(self.dir, "list.txt")
        if terms is not None:
            Path(self.list).write_text("\n".join(terms) + "\n")
        self.env = {**os.environ, "HOME": self.dir, "HOUSE_SCAN_DENYLIST": self.list if terms is not None else os.path.join(self.dir, "none.txt"),
                    "GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_SYSTEM": os.devnull,
                    "GIT_ALLOW_PROTOCOL": "file", "GIT_TERMINAL_PROMPT": "0"}  # ls-remote of a non-file URL fails fast
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.email", "t@example.com")
        self.git("config", "user.name", "tester")
        self.commit("seed.txt", "hello\n", "seed")

    def git(self, *args, check=True):
        done = subprocess.run(["git", *args], cwd=self.work, env=self.env, capture_output=True, text=True)
        if check and done.returncode:
            raise AssertionError(done.stderr)
        return done.stdout.strip()

    def commit(self, path, text, message, extra=()):
        target = Path(self.work, path)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)
        self.git("add", "-A")
        self.git(*extra, "commit", "-q", "-m", message)
        return self.git("rev-parse", "HEAD")

    def push(self, local, remote=ZERO, url=PUBLIC, line=None, name="origin"):
        stdin = line if line is not None else f"refs/heads/main {local} refs/heads/main {remote}\n"
        return subprocess.run([str(HOOK), name, url], cwd=self.work, env=self.env, input=stdin, capture_output=True, text=True)


class PrePushTests(unittest.TestCase):
    def setUp(self):
        self.repo = Repo()
        self.addCleanup(self.repo.tmp.cleanup)
        self.base = self.repo.git("rev-parse", "HEAD")

    def test_clean_push_passes(self):
        head = self.repo.commit("a.txt", "nothing here\n", "add a")
        done = self.repo.push(head, self.base)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn("1 commit(s) scanned, 0 hit(s)", done.stdout)

    def test_hit_in_file_is_refused_without_printing_the_term(self):
        head = self.repo.commit("a.txt", "ok\nthe ZORBLAX3 room\n", "add a")
        done = self.repo.push(head, self.base)
        self.assertEqual(done.returncode, 1)
        self.assertIn("a.txt:2 denylist", done.stdout)
        self.assertNotIn("zorblax", (done.stdout + done.stderr).lower())

    def test_hit_in_path_is_refused(self):
        head = self.repo.commit("docs/zorblax7-notes.txt", "clean\n", "add notes")
        done = self.repo.push(head, self.base)
        self.assertEqual(done.returncode, 1)
        self.assertIn("docs/…:path denylist", done.stdout)
        self.assertNotIn("zorblax", done.stderr.lower())

    def test_hit_in_commit_message_is_refused(self):
        head = self.repo.commit("a.txt", "clean\n", "move zorblax1 stuff")
        done = self.repo.push(head, self.base)
        self.assertEqual(done.returncode, 1)
        self.assertIn(f"{head[:8]}:message denylist", done.stdout)

    def test_hit_in_author_is_refused(self):
        self.repo.git("config", "user.name", "zorblax2 person")
        head = self.repo.commit("a.txt", "clean\n", "plain")
        done = self.repo.push(head, self.base)
        self.assertEqual(done.returncode, 1)
        self.assertIn(f"{head[:8]}:author denylist", done.stdout)

    def test_hit_in_committer_email_is_refused(self):
        head = self.repo.commit("a.txt", "clean\n", "plain", extra=("-c", "user.email=zorblax4@example.com"))
        done = self.repo.push(head, self.base)
        self.assertEqual(done.returncode, 1)
        self.assertIn(":author denylist", done.stdout)

    def test_new_branch_hit_in_new_commit_is_refused(self):
        old = self.repo.commit("old.txt", "clean\n", "old")
        self.repo.git("update-ref", "refs/remotes/origin/main", old)
        head = self.repo.commit("new.txt", "zorblax6\n", "new work")
        self.assertEqual(self.repo.push(head, ZERO).returncode, 1)

    def test_missing_list_with_public_remote_is_refused(self):
        repo = Repo(terms=None)
        self.addCleanup(repo.tmp.cleanup)
        head = repo.commit("a.txt", "clean\n", "add a")
        done = repo.push(head, ZERO, url=PUBLIC)
        self.assertEqual(done.returncode, 1)
        self.assertIn("refusing the push to the public repo", done.stderr)

    def test_short_list_with_public_remote_is_refused(self):
        repo = Repo(terms=TERMS[:5])
        self.addCleanup(repo.tmp.cleanup)
        head = repo.commit("a.txt", "clean\n", "add a")
        done = repo.push(head, ZERO, url="https://github.com/sfenton/native-home")
        self.assertEqual(done.returncode, 1)
        self.assertIn("fewer than 20", done.stderr)

    def test_missing_list_with_other_remote_warns_and_allows(self):
        repo = Repo(terms=None)
        self.addCleanup(repo.tmp.cleanup)
        head = repo.commit("a.txt", "clean\n", "add a")
        done = repo.push(head, ZERO, url=OTHER)
        self.assertEqual(done.returncode, 0)
        self.assertIn("warning", done.stderr)

    def test_short_list_with_other_remote_still_scans(self):
        repo = Repo(terms=TERMS[:5])
        self.addCleanup(repo.tmp.cleanup)
        head = repo.commit("a.txt", "zorblax1\n", "add a")
        done = repo.push(head, repo.git("rev-parse", "HEAD~1"), url=OTHER)
        self.assertEqual(done.returncode, 0)
        self.assertIn("1 hit(s)", done.stdout)
        self.assertIn("warning", done.stderr)

    def test_private_push_touching_a_file_with_a_hit_is_allowed(self):
        head = self.repo.commit("a.txt", "zorblax1\n", "add a")
        done = self.repo.push(head, self.base, url=OTHER)
        self.assertEqual(done.returncode, 0)
        self.assertIn("a.txt:1 denylist", done.stdout)
        self.assertIn("allowed for a non-public remote", done.stderr)

    def test_public_url_variants(self):
        import prepush_denylist as hook
        for url in ("https://github.com/SFenton/native-home", "https://github.com/sfenton/NATIVE-HOME.git", "https://github.com/SFenton/native-home/",
                    "https://github.com/SFenton/native-home.git/", "git@github.com:SFenton/native-home.git", "ssh://git@github.com/SFenton/native-home"):
            with self.subTest(url=url):
                self.assertTrue(hook.is_public(url))
        for url in (OTHER, "https://github.com/SFenton/native-home-private", "https://github.com/SFenton/Fenton-HASS-Native.git"):
            with self.subTest(url=url):
                self.assertFalse(hook.is_public(url))

    def test_new_branch_exposes_history_on_another_remote(self):
        """P1: history on origin/*, pushed to the public remote as a new branch, is scanned in full."""
        old = self.repo.commit("old.txt", "zorblax5 here\n", "old hit")
        self.repo.git("update-ref", "refs/remotes/origin/main", old)
        head = self.repo.commit("new.txt", "clean\n", "new work")
        refused = self.repo.push(head, ZERO, name="native")
        self.assertEqual(refused.returncode, 1)
        self.assertIn("old.txt:1 denylist", refused.stdout)
        by_url = self.repo.push(head, ZERO, name=PUBLIC)
        self.assertEqual(by_url.returncode, 1)

    def _bare(self, name="SFenton"):
        """A bare repo at ``<tmp>/<name>/native-home.git``: a public URL (``is_public``) that ``ls-remote`` reaches offline."""
        path = os.path.join(self.repo.dir, name, "native-home.git")
        os.makedirs(os.path.dirname(path))
        subprocess.run(["git", "init", "-q", "--bare", path], check=True, env=self.repo.env)
        return path

    def _public(self, bare, author="zorblax7 person", blob="clean\n", branch="main"):
        """Commit on top of the base with a denylisted author, publish it to ``bare`` (it really has it), return its sha."""
        self.repo.git("checkout", "-q", "-B", "tmp-" + branch, self.base)
        self.repo.git("config", "user.name", author)
        theirs = self.repo.commit("theirs.txt", blob, "public squash")
        self.repo.git("config", "user.name", "tester")
        self.repo.git("push", "-q", bare, f"{theirs}:refs/heads/{branch}")
        return theirs

    def _merged(self, theirs):
        """A ``pr`` branch from the base with one commit and a merge of ``theirs``; return (pr commit, merge head)."""
        self.repo.git("checkout", "-q", "-B", "pr", self.base)
        mine = self.repo.commit("mine.txt", "clean\n", "pr work")
        self.repo.git("merge", "-q", "--no-ff", "-m", "merge main", theirs)
        return mine, self.repo.git("rev-parse", "HEAD")

    def test_new_branch_scans_only_its_new_commits(self):
        bare = self._bare()
        old = self._public(bare, blob="zorblax5 here\n")  # the destination really has it
        self.repo.git("checkout", "-q", "-B", "pr", old)
        head = self.repo.commit("new.txt", "clean\n", "new work")
        done = self.repo.push(head, ZERO, url=bare)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("1 commit(s) scanned", done.stdout)

    def test_known_sha_merge_of_advertised_commit_with_denylisted_author_pushes(self):
        bare = self._bare()
        theirs = self._public(bare)
        mine, head = self._merged(theirs)
        done = self.repo.push(head, mine, url=bare)  # remote_sha known: the branch exists on the destination
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("1 commit(s) scanned, 0 hit(s)", done.stdout)  # only the local merge commit

    def test_new_branch_merge_of_advertised_commit_with_denylisted_author_pushes(self):
        bare = self._bare()
        theirs = self._public(bare)
        _mine, head = self._merged(theirs)
        done = self.repo.push(head, ZERO, url=bare)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("2 commit(s) scanned, 0 hit(s)", done.stdout)

    def test_known_sha_new_commit_with_denylisted_author_or_blob_is_refused(self):
        bare = self._bare()
        theirs = self._public(bare)
        self.repo.git("checkout", "-q", "-B", "pr", theirs)
        blob = self.repo.commit("mine.txt", "the zorblax9 room\n", "pr work")
        done = self.repo.push(blob, theirs, url=bare)
        self.assertEqual(done.returncode, 1)
        self.assertIn("mine.txt:1 denylist", done.stdout)
        self.repo.git("config", "user.name", "zorblax8 person")
        author = self.repo.commit("other.txt", "clean\n", "more")
        done = self.repo.push(author, theirs, url=bare)
        self.assertEqual(done.returncode, 1)
        self.assertIn(f"{author[:8]}:author denylist", done.stdout)

    def test_new_branch_new_commit_with_denylisted_author_or_blob_is_refused(self):
        bare = self._bare()
        theirs = self._public(bare)
        self.repo.git("checkout", "-q", "-B", "pr", theirs)
        blob = self.repo.commit("mine.txt", "the zorblax9 room\n", "pr work")
        self.assertEqual(self.repo.push(blob, ZERO, url=bare).returncode, 1)
        self.repo.git("config", "user.name", "zorblax8 person")
        author = self.repo.commit("other.txt", "clean\n", "more")
        done = self.repo.push(author, ZERO, url=bare)
        self.assertEqual(done.returncode, 1)
        self.assertIn(f"{author[:8]}:author denylist", done.stdout)

    def test_commit_on_another_local_branch_only_is_still_scanned(self):
        bare = self._bare()
        self._public(bare)
        self.repo.git("checkout", "-q", "-b", "other", self.base)
        stray = self.repo.commit("stray.txt", "zorblax10\n", "stray")  # a local branch only: the destination lacks it
        mine, head = self._merged(stray)
        for remote in (mine, ZERO):
            with self.subTest(remote=remote[:8]):
                done = self.repo.push(head, remote, url=bare)
                self.assertEqual(done.returncode, 1)
                self.assertIn("stray.txt:1 denylist", done.stdout)

    def test_stale_tracking_ref_is_not_trusted(self):
        """A tracking ref at a commit the destination no longer has (rewritten history) hides nothing, in both paths."""
        bare = self._bare()
        self.repo.git("remote", "add", "origin", bare)
        self.repo.git("checkout", "-q", "-B", "gone", self.base)
        purged = self.repo.commit("purged.txt", "the zorblax11 room\n", "purged")
        self.repo.git("update-ref", "refs/remotes/origin/main", purged)  # stale: the bare repo never had it
        self.repo.git("push", "-q", bare, f"{self.base}:refs/heads/main")
        self.repo.git("checkout", "-q", "-B", "pr", purged)
        head = self.repo.commit("mine.txt", "clean\n", "pr work")
        for remote in (self.base, ZERO):
            with self.subTest(remote=remote[:8]):
                done = self.repo.push(head, remote, url=bare, name="origin")
                self.assertEqual(done.returncode, 1, done.stdout)
                self.assertIn("purged.txt:1 denylist", done.stdout)

    def test_split_pushurl_is_refused_when_the_push_target_lacks_the_commit(self):
        """``origin`` fetches from a private repo that has the commit; the push goes to a public one that does not."""
        fetch_from = self._bare("private")
        push_to = self._bare()
        theirs = self._public(fetch_from, blob="the zorblax12 room\n")
        self.repo.git("remote", "add", "origin", fetch_from)
        self.repo.git("config", "remote.origin.pushurl", push_to)
        self.repo.git("fetch", "-q", "origin")
        self.repo.git("push", "-q", push_to, f"{self.base}:refs/heads/main")
        self.repo.git("checkout", "-q", "-B", "pr", theirs)
        head = self.repo.commit("mine.txt", "clean\n", "pr work")
        for remote in (self.base, ZERO):
            with self.subTest(remote=remote[:8]):
                done = self.repo.push(head, remote, url=push_to, name="origin")
                self.assertEqual(done.returncode, 1, done.stdout)
                self.assertIn("theirs.txt:1 denylist", done.stdout)

    def test_ls_remote_failure_scans_everything(self):
        bare = self._bare()
        theirs = self._public(bare)
        mine, head = self._merged(theirs)
        missing = os.path.join(self.repo.dir, "absent", "SFenton", "native-home.git")  # ls-remote fails
        done = self.repo.push(head, mine, url=missing)
        self.assertEqual(done.returncode, 1)
        self.assertIn(f"{theirs[:8]}:author denylist", done.stdout)

    def test_annotated_tag_message_is_scanned(self):
        self.repo.git("tag", "-a", "v1", "-m", "release zorblax5", self.base)
        tag = self.repo.git("rev-parse", "v1")
        done = self.repo.push(tag, ZERO, line=f"refs/tags/v1 {tag} refs/tags/v1 {ZERO}\n")
        self.assertEqual(done.returncode, 1)
        self.assertIn(":tag denylist", done.stdout)

    def test_blob_and_tree_tags_are_scanned(self):
        blob = subprocess.run(["git", "hash-object", "-w", "--stdin"], cwd=self.repo.work, env=self.repo.env, input="zorblax6\n",
                              capture_output=True, text=True).stdout.strip()
        done = self.repo.push(blob, ZERO, line=f"refs/tags/b {blob} refs/tags/b {ZERO}\n")
        self.assertEqual(done.returncode, 1)
        self.repo.commit("t/zorblax7.txt", "x\n", "tree")
        tree = self.repo.git("rev-parse", "HEAD^{tree}")
        done = self.repo.push(tree, ZERO, line=f"refs/tags/t {tree} refs/tags/t {ZERO}\n")
        self.assertEqual(done.returncode, 1)
        self.assertNotIn("zorblax", done.stdout.lower())

    def test_git_error_refuses(self):
        done = self.repo.push("1" * 40, self.base)
        self.assertEqual(done.returncode, 1)
        self.assertIn("refusing the push", done.stderr)
        private = self.repo.push("1" * 40, self.base, url=OTHER)
        self.assertEqual(private.returncode, 1)

    def test_utf16_file_is_scanned(self):
        Path(self.repo.work, "u.txt").write_bytes("x\nzorblax8\n".encode("utf-16"))
        self.repo.git("add", "-A")
        self.repo.git("commit", "-q", "-m", "u16")
        done = self.repo.push(self.repo.git("rev-parse", "HEAD"), self.base)
        self.assertEqual(done.returncode, 1)
        self.assertIn("u.txt:", done.stdout)

    def test_large_file_is_scanned_to_its_last_line(self):
        Path(self.repo.work, "big.json").write_text("line of filler text\n" * 150000 + "zorblax9\n")
        self.repo.git("add", "-A")
        self.repo.git("commit", "-q", "-m", "big")
        done = self.repo.push(self.repo.git("rev-parse", "HEAD"), self.base)
        self.assertEqual(done.returncode, 1)
        self.assertIn("big.json:150001 denylist", done.stdout)

    def test_term_across_a_chunk_edge_is_found_once(self):
        import prepush_denylist as hook
        matcher = hook.Matcher(__import__("house_scan").load_denylist({"HOUSE_SCAN_DENYLIST": self.repo.list}))
        data = b"a" * (hook.CHUNK - 4) + b" zorblax3 " + b"b" * 10
        self.assertEqual(matcher.lines(data), {1})

    def test_ref_names_are_scanned_and_redacted(self):
        head = self.repo.commit("a.txt", "clean\n", "add a")
        for line in (f"refs/heads/zorblax11 {head} refs/heads/zorblax11 {self.base}\n",
                     f"refs/heads/main {head} refs/tags/zorblax12 {ZERO}\n",
                     f"(delete) {ZERO} refs/heads/zorblax13 {self.base}\n"):
            with self.subTest(line=line):
                done = self.repo.push(head, self.base, line=line)
                self.assertEqual(done.returncode, 1)
                self.assertIn("ref:", done.stdout)
                self.assertNotIn("zorblax", (done.stdout + done.stderr).lower())
        private = self.repo.push(head, self.base, url=OTHER, line=f"refs/heads/zorblax11 {head} refs/heads/zorblax11 {self.base}\n")
        self.assertEqual(private.returncode, 0)
        self.assertNotIn("zorblax", (private.stdout + private.stderr).lower())

    def test_path_hit_is_redacted(self):
        """P13: a term in a path never reaches the output."""
        head = self.repo.commit("zorblax13/inner/f.txt", "ok\n", "p")
        done = self.repo.push(head, self.base)
        self.assertEqual(done.returncode, 1)
        self.assertNotIn("zorblax", (done.stdout + done.stderr).lower())
        self.assertIn("…/inner/f.txt:path denylist", done.stdout)
        head = self.repo.commit("zorblax14/g.txt", "zorblax2\n", "q")
        done = self.repo.push(head, self.base)
        self.assertNotIn("zorblax", (done.stdout + done.stderr).lower())

    def test_delete_is_skipped(self):
        done = self.repo.push(ZERO, self.base, line=f"(delete) {ZERO} refs/heads/old {self.base}\n")
        self.assertEqual(done.returncode, 0)
        self.assertIn("0 commit(s) scanned", done.stdout)

    def test_binary_blob_is_scanned(self):
        target = Path(self.repo.work, "b.bin")
        target.write_bytes(b"\x00\x01zorblax1\x00")
        self.repo.git("add", "-A")
        self.repo.git("commit", "-q", "-m", "bin")
        done = self.repo.push(self.repo.git("rev-parse", "HEAD"), self.base)
        self.assertEqual(done.returncode, 1)

    def test_merge_commit_is_scanned(self):
        self.repo.git("checkout", "-q", "-b", "side")
        self.repo.commit("s.txt", "clean\n", "side")
        self.repo.git("checkout", "-q", "main")
        self.repo.commit("m.txt", "clean\n", "main")
        self.repo.git("merge", "-q", "--no-ff", "-m", "merge", "side")
        done = self.repo.push(self.repo.git("rev-parse", "HEAD"), self.base)
        self.assertEqual(done.returncode, 0, done.stderr)

    def test_real_push_runs_the_hook(self):
        bare = os.path.join(self.repo.dir, "bare")
        subprocess.run(["git", "init", "-q", "--bare", bare], check=True)
        self.repo.git("remote", "add", "origin", bare)
        self.repo.git("config", "core.hooksPath", str(ROOT / ".githooks"))
        self.repo.commit("a.txt", "zorblax9\n", "add a")
        done = subprocess.run(["git", "push", "-q", "origin", "main"], cwd=self.repo.work, env=self.repo.env, capture_output=True, text=True)
        self.assertEqual(done.returncode, 0)  # a private remote only warns
        self.assertIn("allowed for a non-public remote", done.stderr)
        self.assertNotIn("zorblax", (done.stdout + done.stderr).lower())


class SetupTests(unittest.TestCase):
    def test_setup_is_idempotent_and_reports_counts(self):
        repo = Repo()
        self.addCleanup(repo.tmp.cleanup)
        subprocess.run(["git", "init", "-q", "-b", "main", repo.dir + "/co"], check=True)
        co = repo.dir + "/co"
        (Path(co) / "tools").mkdir()
        (Path(co) / ".githooks").mkdir()
        for name in ("setup.sh", "house_scan.py"):
            (Path(co) / "tools" / name).write_bytes((ROOT / "tools" / name).read_bytes())
        hook = Path(co) / ".githooks" / "pre-push"
        hook.write_bytes(HOOK.read_bytes())
        hook.chmod(0o644)
        for _ in range(2):
            done = subprocess.run(["sh", "tools/setup.sh"], cwd=co, env=repo.env, capture_output=True, text=True)
            self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn("25 term(s)", done.stdout)
        self.assertTrue(os.access(hook, os.X_OK))
        cfg = subprocess.run(["git", "config", "core.hooksPath"], cwd=co, capture_output=True, text=True).stdout.strip()
        self.assertEqual(cfg, ".githooks")
        self.assertNotIn("zorblax", done.stdout.lower())


class GuardTests(unittest.TestCase):
    def reason(self, command):
        return commit_guard.command_reason(command, tempfile.gettempdir())

    def check(self, args, override=False):
        return commit_guard.check_git("push", args, tempfile.gettempdir(), override)

    def test_push_bypasses_are_refused(self):
        for args in (["--no-verify", "origin", "x"], ["--no-veri"], ["-q", "--no-verify"]):
            with self.subTest(args=args):
                self.assertTrue(commit_guard.push_skips_hook(args))

    def test_dry_run_is_not_refused(self):
        for args in (["-n", "origin"], ["--dry-run"], ["-un"]):
            self.assertFalse(commit_guard.push_skips_hook(args))

    def test_config_and_env_overrides_are_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            subprocess.run(["git", "init", "-q", "-b", "lane", tmp], check=True)
            refused = ("git config core.hooksPath /dev/null", "git config --global core.hooksPath /dev/null", "git config --local core.hookspath x",
                       "git config --worktree core.hooksPath x", "git config --unset core.hooksPath", "git config --global --unset-all core.hooksPath",
                       "git config core.hooksPath /dev/null && git push", "git --config-env=core.hooksPath=HP push",
                       "git --config-env core.hooksPath=HP push", "GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=x GIT_CONFIG_VALUE_0=y git push",
                       "GIT_CONFIG_PARAMETERS=\"'a'='b'\" git push", "env GIT_CONFIG_GLOBAL=/x git push")
            for command in refused:
                with self.subTest(command=command):
                    self.assertIsNotNone(commit_guard.command_reason(command, tmp))
            for command in ("git config core.hooksPath", "git config --get core.hooksPath", "git config user.name x", "git push -n origin lane",
                            "git push --dry-run", "git config --list"):
                with self.subTest(command=command):
                    self.assertIsNone(commit_guard.command_reason(command, tmp))

    def test_plain_push_is_not_a_bypass(self):
        for args in (["-q", "-u", "origin", "agents/x"], ["origin", "HEAD:agents/x"], ["--set-upstream", "origin", "x"], ["--", "-n"]):
            with self.subTest(args=args):
                self.assertFalse(commit_guard.push_skips_hook(args))

    def test_hooks_path_override_on_push_is_refused(self):
        self.assertIn("core.hooksPath", self.check(["origin", "x"], override=True) or "")

    def test_command_level_refusals(self):
        with tempfile.TemporaryDirectory() as tmp:
            subprocess.run(["git", "init", "-q", "-b", "lane", tmp], check=True)
            for command in ("git push --no-verify origin lane", "git -c core.hooksPath=/dev/null push origin lane"):
                with self.subTest(command=command):
                    self.assertIsNotNone(commit_guard.command_reason(command, tmp))
            self.assertIsNone(commit_guard.command_reason("git push -q -u origin lane", tmp))


if __name__ == "__main__":
    unittest.main()
