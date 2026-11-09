"""Denylist layers (owner, 2026-11-07): ship.sh before the push, pr_land on the exact PR head, and the go-public gate.

Every list here is a temporary file of synthetic terms; no real house term appears in this repository.
"""

import json
import os
import re
import shutil
import stat
import subprocess
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import mock

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import go_public_gate  # noqa: E402
import house_scan  # noqa: E402
import pr_land  # noqa: E402
from test_lane_ship import ENV, git, make_repo  # noqa: E402

TERM = "zorgblatquux"  # synthetic: stands in for a house term


def write_list(directory, terms=(TERM,)):
    path = Path(directory) / "denylist.txt"
    path.write_text("# synthetic\n" + "\n".join(terms) + "\n")
    return path


class HouseScanDenylistCommandTests(unittest.TestCase):
    def run_cmd(self, root, denylist, *extra):
        env = {**ENV, "HOUSE_SCAN_DENYLIST": str(denylist)}
        proc = subprocess.run([sys.executable, str(TOOLS / "house_scan.py"), "denylist", "--root", str(root), *extra],
                              env=env, capture_output=True, text=True)
        return proc.returncode, proc.stdout

    def test_hit_clean_and_missing(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp) / "tree"
            root.mkdir()
            (root / "a.txt").write_text("hello\n")
            lst = write_list(tmp)
            code, out = self.run_cmd(root, lst)
            self.assertEqual(code, 0)
            self.assertIn("denylist loaded, 0 hit(s)", out)
            self.assertIn("denylist source env, 1 term(s)", out)  # the source and the count, never a term
            (root / "b.md").write_text(f"x\nsee {TERM} here\n")
            code, out = self.run_cmd(root, lst)
            self.assertEqual(code, 1)
            self.assertIn("1 hit(s)", out)
            self.assertIn("b.md:2 denylist", out)
            self.assertNotIn(TERM, out)
            code, out = self.run_cmd(root, Path(tmp) / "missing.txt")
            self.assertEqual(code, 0)
            self.assertIn("denylist not loaded", out)
            code, out = self.run_cmd(root, Path(tmp) / "missing.txt", "--required", "true")
            self.assertEqual(code, house_scan.EXIT_NOT_LOADED)

    def test_required_comes_from_a_config_key_defaulting_to_false(self):
        with TemporaryDirectory() as tmp:
            for body, expected in (('{"denylist_required": true}', True), ('{"denylist_required": false}', False), ("{}", False),
                                   ("not json", False)):
                config = Path(tmp) / "c.json"
                config.write_text(body)
                self.assertIs(house_scan.denylist_required(config), expected, body)
            self.assertIs(house_scan.denylist_required(Path(tmp) / "none.json"), False)


class ShipDenylistTests(unittest.TestCase):
    """``tools/ship.sh`` scans before it pushes."""

    def clone(self, tmp, required):
        clone, origin = make_repo(tmp)
        shutil.copy(TOOLS / "house_scan.py", clone / "tools" / "house_scan.py")
        (clone / "tools" / "triage").mkdir()
        (clone / "tools" / "triage" / "config.json").write_text(json.dumps({"denylist_required": required}))
        git(clone, "add", "-A")
        git(clone, "commit", "-q", "-m", "scan tools")
        git(clone, "push", "-q", "origin", "main")
        git(clone, "switch", "-q", "-c", "claude/x")
        return clone, origin

    def ship(self, clone, denylist):
        env = {**ENV, "HOUSE_SCAN_DENYLIST": str(denylist)}
        return subprocess.run(["bash", "tools/ship.sh", "Add a"], cwd=clone, env=env, capture_output=True, text=True)

    def pushed(self, origin):
        return subprocess.run(["git", "-C", str(origin), "rev-parse", "--verify", "-q", "claude/x"], capture_output=True).returncode == 0

    def test_a_hit_blocks_the_push_and_prints_location_not_term(self):
        with TemporaryDirectory() as tmp:
            clone, origin = self.clone(tmp, False)
            (clone / "a.txt").write_text(f"line\n{TERM}\n")
            done = self.ship(clone, write_list(tmp))
            self.assertEqual(done.returncode, 1, done.stderr)
            self.assertIn("a.txt:2 denylist", done.stdout)
            self.assertIn("1 new hit(s)", done.stdout)
            self.assertNotIn(TERM, done.stdout + done.stderr)
            self.assertFalse(self.pushed(origin))

    def test_clean_pushes(self):
        with TemporaryDirectory() as tmp:
            clone, origin = self.clone(tmp, True)
            (clone / "a.txt").write_text("nothing here\n")
            done = self.ship(clone, write_list(tmp))
            self.assertEqual(done.returncode, 0, done.stderr)
            self.assertIn("denylist loaded, 0 new hit(s)", done.stdout)
            self.assertTrue(self.pushed(origin))

    def test_a_hit_already_on_the_base_does_not_block_but_a_second_one_does(self):
        with TemporaryDirectory() as tmp:
            clone, origin = self.clone(tmp, False)
            (clone / "old.txt").write_text(f"{TERM}\n")
            git(clone, "add", "-A")
            git(clone, "commit", "-q", "-m", "debt")
            git(clone, "push", "-q", "origin", "HEAD:main")  # the hit is now on origin/main
            (clone / "a.txt").write_text("fine\n")
            done = self.ship(clone, write_list(tmp))
            self.assertEqual(done.returncode, 0, done.stderr)
            self.assertIn("0 new hit(s)", done.stdout)
            self.assertTrue(self.pushed(origin))
            (clone / "old.txt").write_text(f"{TERM}\nand {TERM} again\n")
            blocked = subprocess.run(["bash", "tools/ship.sh", "More"], cwd=clone,
                                     env={**ENV, "HOUSE_SCAN_DENYLIST": str(Path(tmp) / "denylist.txt")}, capture_output=True, text=True)
            self.assertEqual(blocked.returncode, 1, blocked.stderr)
            self.assertIn("old.txt:2 denylist", blocked.stdout)

    def test_missing_list_when_optional_warns_and_pushes(self):
        with TemporaryDirectory() as tmp:
            clone, origin = self.clone(tmp, False)
            (clone / "a.txt").write_text("x\n")
            done = self.ship(clone, Path(tmp) / "missing.txt")
            self.assertEqual(done.returncode, 0, done.stderr)
            self.assertIn("denylist not loaded", done.stdout)
            self.assertTrue(self.pushed(origin))

    def test_missing_list_when_required_refuses_before_the_push(self):
        with TemporaryDirectory() as tmp:
            clone, origin = self.clone(tmp, True)
            (clone / "a.txt").write_text("x\n")
            done = self.ship(clone, Path(tmp) / "missing.txt")
            self.assertEqual(done.returncode, 1, done.stderr)
            self.assertIn("denylist is required but not loaded", done.stderr)
            self.assertFalse(self.pushed(origin))


class PrLandDenylistTests(unittest.TestCase):
    """``pr_land.denylist_gate`` scans the exact PR head."""

    def setUp(self):
        self.tmp = TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.repo = Path(self.tmp.name) / "repo"
        self.repo.mkdir()
        git(self.repo, "init", "-q", "-b", "main")
        (self.repo / "ok.txt").write_text("fine\n")
        git(self.repo, "add", "-A")
        git(self.repo, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "base")
        self.head_clean = git(self.repo, "rev-parse", "HEAD")
        (self.repo / "leak.txt").write_text(f"a\nb {TERM}\n")
        git(self.repo, "add", "-A")
        git(self.repo, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "leak")
        self.head_hit = git(self.repo, "rev-parse", "HEAD")
        self.addCleanup(os.chdir, os.getcwd())
        os.chdir(self.repo)

    def gate(self, head, required, denylist, base=""):
        with mock.patch.dict(os.environ, {"HOUSE_SCAN_DENYLIST": str(denylist)}):
            return pr_land.denylist_gate("7", head, required, base)

    def test_only_hits_the_pr_adds_against_its_base_refuse(self):
        lst = write_list(self.tmp.name)
        git(self.repo, "update-ref", "refs/remotes/origin/main", self.head_clean)
        self.assertIn("leak.txt:2 denylist", self.gate(self.head_hit, False, lst, "main"))
        git(self.repo, "update-ref", "refs/remotes/origin/main", self.head_hit)  # the same hit is already on the base
        self.assertIsNone(self.gate(self.head_hit, False, lst, "main"))

    def test_a_hit_in_the_head_refuses_with_a_location(self):
        refused = self.gate(self.head_hit, False, write_list(self.tmp.name))
        self.assertIn("1 hit(s)", refused)
        self.assertIn("leak.txt:2 denylist", refused)
        self.assertNotIn(TERM, refused)

    def test_a_clean_head_passes(self):
        self.assertIsNone(self.gate(self.head_clean, True, write_list(self.tmp.name)))

    def test_missing_list_optional_warns_and_continues(self):
        with mock.patch("sys.stderr") as err:
            self.assertIsNone(self.gate(self.head_hit, False, Path(self.tmp.name) / "none.txt"))
        self.assertIn("denylist not loaded", "".join(c.args[0] for c in err.write.call_args_list))

    def test_missing_list_required_refuses(self):
        self.assertIn("denylist not loaded", self.gate(self.head_clean, True, Path(self.tmp.name) / "none.txt"))

    def test_an_unreadable_head_refuses_once_a_list_is_loaded(self):
        self.assertIn("cannot read the head", self.gate("0" * 40, False, write_list(self.tmp.name)))


MANY = [TERM] + [f"synthterm{i}" for i in range(25)]  # a list that is long enough for the go-public gate


class GoPublicGateTests(unittest.TestCase):
    """``go_public_gate``: the trusted base config, every file type, one orphan commit, gitleaks, 20+ denylist terms (round-1 bypasses)."""

    def fake_gitleaks(self, directory, exit_code, findings):
        script = Path(directory) / "gitleaks"
        report = json.dumps([{"RuleID": "x"}] * findings)
        script.write_text("#!/bin/sh\nwhile [ $# -gt 0 ]; do [ \"$1\" = --report-path ] && out=\"$2\"; shift; done\n"
                          f"echo '{report}' > \"$out\"\nexit {exit_code}\n")
        script.chmod(script.stat().st_mode | stat.S_IEXEC)
        return str(script)

    def base_repo(self, tmp, config=None):
        """The tool repository: ``origin/main`` holds the trusted ``contracts/house_scan.json``."""
        repo = Path(tmp) / "tools-repo"
        repo.mkdir()
        git(repo, "init", "-q", "-b", "main")
        (repo / "contracts").mkdir()
        (repo / "contracts" / "house_scan.json").write_text(json.dumps(config or {"allow": {"skip_prefixes": ["build/"]}, "debt": []}))
        git(repo, "add", "-A")
        git(repo, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "base")
        git(repo, "update-ref", "refs/remotes/origin/main", "HEAD")
        return repo

    def snapshot(self, tmp, files=None, commits=1):
        """A git snapshot of ``files``; with ``commits`` > 1 the earlier commits carry each file's text before it was scrubbed."""
        snap = Path(tmp) / "snap"
        snap.mkdir()
        git(snap, "init", "-q", "-b", "main")
        for rel, text in (files or {"README.md": "nothing\n"}).items():
            (snap / rel).parent.mkdir(parents=True, exist_ok=True)
            (snap / rel).write_text(text)
        git(snap, "add", "-A")
        neutral = {**ENV, "GIT_AUTHOR_NAME": "S+H", "GIT_AUTHOR_EMAIL": "noreply@example.com",
                   "GIT_COMMITTER_NAME": "S+H", "GIT_COMMITTER_EMAIL": "noreply@example.com"}
        subprocess.run(["git", "-C", str(snap), "commit", "-qm", "snapshot"], env=neutral, check=True, capture_output=True)
        return snap

    def run_gate(self, snap, denylist, gitleaks, base):
        env = {**ENV, "HOUSE_SCAN_DENYLIST": str(denylist)}
        proc = subprocess.run([sys.executable, str(TOOLS / "go_public_gate.py"), str(snap), "--gitleaks", gitleaks,
                               "--base-repo", str(base)], env=env, capture_output=True, text=True)
        return proc.returncode, proc.stdout + proc.stderr

    def gate(self, files=None, terms=MANY, gitleaks=(0, 0), config=None, mutate=None):
        with TemporaryDirectory() as tmp:
            base = self.base_repo(tmp, config)
            snap = self.snapshot(tmp, files)
            if mutate:
                mutate(snap)
            return self.run_gate(snap, write_list(tmp, terms), self.fake_gitleaks(tmp, *gitleaks), base)

    def test_a_clean_orphan_snapshot_passes_and_prints_counts_and_the_source_only(self):
        code, out = self.gate()
        self.assertEqual(code, 0, out)
        self.assertIn("denylist source env, 26 term(s)", out)
        self.assertIn("1 orphan commit", out)
        self.assertNotIn(TERM, out)

    def test_the_denylist_not_loaded_or_too_short_refuses(self):
        with TemporaryDirectory() as tmp:
            base = self.base_repo(tmp)
            snap = self.snapshot(tmp)
            code, out = self.run_gate(snap, Path(tmp) / "missing.txt", self.fake_gitleaks(tmp, 0, 0), base)
            self.assertEqual(code, go_public_gate.EXIT_NO_DENYLIST, out)
            self.assertIn("stays private", out)
        code, out = self.gate(terms=[TERM, "other"])
        self.assertEqual(code, go_public_gate.EXIT_NO_DENYLIST, out)
        self.assertIn("need at least 20 terms", out)

    def test_a_denylist_hit_refuses_and_hides_the_term(self):
        code, out = self.gate({"README.md": f"{TERM}\n"})
        self.assertEqual(code, 1, out)
        self.assertIn("1 denylist hit(s) in every file type", out)
        self.assertNotIn(TERM, out)

    def test_a_house_scan_hit_refuses(self):
        code, out = self.gate({"README.md": "host " + ".".join(["10", "9", "8", "20"]) + "\n"})
        self.assertEqual(code, 1, out)
        self.assertIn("1 hit(s)", out)

    def test_reviewer_bypass_1_the_snapshots_own_skip_prefixes_hide_nothing(self):
        files = {"docs/a.md": f"{TERM}\n", "contracts/house_scan.json": json.dumps({"allow": {"skip_prefixes": ["docs/"]}})}
        code, out = self.gate(files)
        self.assertEqual(code, 1, out)
        self.assertIn("1 denylist hit(s)", out)

    def test_the_trusted_configs_skip_prefixes_and_debt_hide_nothing_either(self):
        config = {"allow": {"skip_prefixes": ["docs/"]}, "debt": [{"path": "docs", "check": "x:y", "reason": "r", "baseline": {"denylist": 1}}]}
        code, out = self.gate({"docs/a.md": f"{TERM}\n"}, config=config)
        self.assertEqual(code, 1, out)

    def test_reviewer_bypass_2_plist_and_svg_are_read(self):
        for name in ("Info.plist", "icon.svg", "PrivacyInfo.xcprivacy", "x.png"):
            with self.subTest(name=name):
                code, out = self.gate({"README.md": "ok\n", name: f"<string>{TERM}</string>\n"})
                self.assertEqual(code, 1, out)

    def test_round2_a_term_in_a_file_name_or_directory_name_refuses(self):
        for rel in (f"{TERM}-notes.md", f"{TERM}/page.md"):
            with self.subTest(rel=rel):
                code, out = self.gate({"README.md": "ok\n", rel: "fine\n"})
                self.assertEqual(code, 1, out)
                self.assertIn("metadata:", out)
                self.assertNotIn(TERM, out)

    def test_round2_a_term_only_in_the_commit_message_author_or_committer_refuses(self):
        def amend(*extra, env=None):
            def run(snap):
                subprocess.run(["git", "-C", str(snap), "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--amend", *extra],
                               check=True, env={**os.environ, **(env or {})})
            return run
        cases = {"message": amend("-m", f"notes for {TERM}"), "author": amend("--no-edit", "--author", f"{TERM} <a@b.c>"),
                 "committer": amend("--no-edit", env={"GIT_COMMITTER_NAME": TERM, "GIT_COMMITTER_EMAIL": "c@d.e"})}
        for name, mutate in cases.items():
            with self.subTest(name=name):
                code, out = self.gate(mutate=mutate)
                self.assertEqual(code, 1, out)
                self.assertIn("metadata:", out)

    def test_a_real_identity_or_a_remote_refuses(self):
        def amend(snap):
            git(snap, "-c", "user.name=Real", "-c", "user.email=real@example.org", "commit", "-q", "--amend", "--no-edit", "--reset-author")
        cases = {"author_and_committer": amend,
                 "committer_only": lambda snap: subprocess.run(
                     ["git", "-C", str(snap), "commit", "-q", "--amend", "--no-edit"], check=True, capture_output=True,
                     env={**ENV, "GIT_AUTHOR_NAME": "S+H", "GIT_AUTHOR_EMAIL": "noreply@example.com",
                          "GIT_COMMITTER_NAME": "S+H", "GIT_COMMITTER_EMAIL": "real@example.org"}),
                 "remote": lambda snap: git(snap, "remote", "add", "origin", "https://example.org/x.git")}
        for name, mutate in cases.items():
            with self.subTest(name=name):
                code, out = self.gate(mutate=mutate)
                self.assertEqual(code, 1, out)
                self.assertIn("identity:", out)
                self.assertNotIn("real@example.org", out)
        code, out = self.gate()
        self.assertIn("identity: neutral author and committer, 0 remotes", out)

    def test_extra_commit_headers_and_extra_config_keys_refuse(self):
        def header(snap):
            raw = git(snap, "cat-file", "commit", "HEAD").replace("\n\n", "\nencoding UTF-8\n\n", 1) + "\n"
            sha = subprocess.run(["git", "-C", str(snap), "hash-object", "-t", "commit", "-w", "--stdin"], input=raw, text=True,
                                 check=True, capture_output=True, env=ENV).stdout.strip()
            git(snap, "update-ref", "refs/heads/main", sha)
        cases = {"encoding_header": header,
                 "insteadOf": lambda snap: git(snap, "config", "url.https://example.org/.insteadOf", "https://github.com/"),
                 "credential": lambda snap: git(snap, "config", "credential.helper", "store"),
                 "include": lambda snap: git(snap, "config", "include.path", "/tmp/x")}
        for name, mutate in cases.items():
            with self.subTest(name=name):
                code, out = self.gate(mutate=mutate)
                self.assertEqual(code, 1, out)
                self.assertIn("identity:", out)

    def test_round2_a_utf16_file_is_scanned(self):
        def utf16(snap):
            (snap / "notes.txt").write_bytes(f"{TERM}\n".encode("utf-16"))
            git(snap, "add", "-A")
            git(snap, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--amend", "--no-edit")
        code, out = self.gate(mutate=utf16)
        self.assertEqual(code, 1, out)

    def test_round2_an_oversize_file_is_refused_not_skipped(self):
        with TemporaryDirectory() as tmp:
            snap = self.snapshot(tmp, {"README.md": "ok\n", "big.bin": "x" * 100})
            with mock.patch.object(house_scan, "ALL_MODE_MAX_BYTES", 10):
                self.assertEqual(house_scan.oversize_files(snap), ["big.bin"])

    def test_reviewer_bypass_3_a_term_in_the_history_refuses(self):
        def two_commits(snap):
            (snap / "README.md").write_text(f"{TERM}\n")
            git(snap, "add", "-A")
            git(snap, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "leak")
            (snap / "README.md").write_text("scrubbed\n")
            git(snap, "add", "-A")
            git(snap, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "scrub")
        code, out = self.gate(mutate=two_commits)
        self.assertEqual(code, 1, out)
        self.assertIn("history: the snapshot has 3 commit(s)", out)

    def test_other_ways_to_hide_history_or_state_refuse(self):
        def tag(snap):
            git(snap, "tag", "extra")
        def branch(snap):
            git(snap, "branch", "other")
        def dirty(snap):
            (snap / "new.txt").write_text("untracked\n")
        for name, mutate in (("tag", tag), ("branch", branch), ("dirty", dirty)):
            with self.subTest(case=name):
                code, out = self.gate(mutate=mutate)
                self.assertEqual(code, 1, out)
                self.assertIn("history:", out)
        with TemporaryDirectory() as tmp:  # not a git repository at all
            base = self.base_repo(tmp)
            plain = Path(tmp) / "plain"
            plain.mkdir()
            (plain / "README.md").write_text("x\n")
            code, out = self.run_gate(plain, write_list(tmp, MANY), self.fake_gitleaks(tmp, 0, 0), base)
            self.assertEqual(code, go_public_gate.EXIT_ERROR, out)

    def test_an_unreadable_trusted_config_fails_closed(self):
        with TemporaryDirectory() as tmp:
            empty = Path(tmp) / "empty"
            empty.mkdir()
            git(empty, "init", "-q", "-b", "main")
            snap = self.snapshot(tmp)
            code, out = self.run_gate(snap, write_list(tmp, MANY), self.fake_gitleaks(tmp, 0, 0), empty)
            self.assertEqual(code, go_public_gate.EXIT_ERROR, out)
            self.assertIn("cannot read contracts/house_scan.json", out)

    def test_a_gitleaks_finding_refuses(self):
        code, out = self.gate(gitleaks=(1, 2))
        self.assertEqual(code, 1, out)
        self.assertIn("gitleaks: 4 finding(s) in files and history", out)  # the dir scan and the history scan each found 2

    def test_a_missing_or_failing_gitleaks_fails_closed(self):
        with TemporaryDirectory() as tmp:
            snap = self.snapshot(tmp)
            code, out = go_public_gate.gitleaks_gate(snap, str(Path(tmp) / "nope"))
            self.assertEqual(code, go_public_gate.EXIT_ERROR, out)
            code, out = go_public_gate.gitleaks_gate(snap, self.fake_gitleaks(tmp, 5, 0))
            self.assertEqual(code, go_public_gate.EXIT_ERROR, out)
            with mock.patch.object(shutil, "which", return_value=None):
                self.assertEqual(go_public_gate.gitleaks_gate(snap)[0], go_public_gate.EXIT_ERROR)

    def test_gitleaks_runs_from_the_snapshot_with_the_trusted_config_in_both_modes(self):
        with TemporaryDirectory() as tmp:
            snap = self.snapshot(tmp)
            (snap / ".gitleaks.toml").write_text('[allowlist]\npaths = [".*"]\n')
            log = Path(tmp) / "calls.txt"
            tool = Path(tmp) / "gitleaks"
            tool.write_text(f'#!/bin/sh\necho "$PWD|$*" >> {log}\nwhile [ $# -gt 0 ]; do [ "$1" = --config ] && cat "$2" >> {log}; '
                            '[ "$1" = --report-path ] && out="$2"; shift; done\necho "[]" > "$out"\n')
            tool.chmod(tool.stat().st_mode | stat.S_IEXEC)
            self.assertEqual(go_public_gate.gitleaks_gate(snap, str(tool), "# trusted-marker\n")[0], 0)
            calls = log.read_text()
            for mode in ("dir", "git"):
                self.assertRegex(calls, rf"{re.escape(str(snap.resolve()))}\|{mode} \. --config ")
            self.assertEqual(calls.count("--ignore-gitleaks-allow"), 2)
            self.assertEqual(calls.count("# trusted-marker"), 2)
            self.assertNotIn("[allowlist]", calls)
            log.unlink()
            go_public_gate.gitleaks_gate(snap, str(tool))  # no trusted config on the base: the built-in rules, named explicitly
            self.assertIn("useDefault = true", log.read_text())

    @unittest.skipUnless(shutil.which("gitleaks"), "gitleaks is not installed")
    def test_a_snapshot_with_its_own_allowlist_everything_config_still_fails(self):
        with TemporaryDirectory() as tmp:
            snap = Path(tmp) / "snap"
            snap.mkdir()
            git(snap, "init", "-q", "-b", "main")
            secret = "gh" + "p_" + "aB3dE5gH7jK9mN1pQ3sT5vX7zA9cD1fG3hJ5"  # built at run time: never a literal token
            (snap / "leak.txt").write_text(f"token = {secret}\n")
            self.assertEqual(go_public_gate.gitleaks_gate(snap)[0], go_public_gate.EXIT_FOUND, "the default rules find the planted token")
            (snap / ".gitleaks.toml").write_text('[allowlist]\npaths = [".*"]\nregexes = [".*"]\n')
            git(snap, "add", "-A")
            git(snap, "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-qm", "x")
            code, out = go_public_gate.gitleaks_gate(snap)
            self.assertEqual(code, go_public_gate.EXIT_FOUND, out)
            self.assertIn("finding(s)", out)
            (snap / ".gitleaksignore").write_text("leak.txt:github-pat:1\n")  # gitleaks would honour this one from the root
            code, out = go_public_gate.gitleaks_gate(snap)
            self.assertEqual(code, go_public_gate.EXIT_FOUND, out)
            self.assertIn(".gitleaksignore", out)
            self.assertEqual(go_public_gate.gitleaks_gate(snap, None, None, "leak.txt:github-pat:1\n")[0], 0, "an ignore file the trusted base also carries is honoured")

    def test_a_missing_snapshot_is_a_usage_error(self):
        with TemporaryDirectory() as tmp:
            self.assertEqual(go_public_gate.main([str(Path(tmp) / "nope")]), go_public_gate.EXIT_ERROR)


class PrLandTrustedConfigTests(unittest.TestCase):
    """Denylist layer 1 judges the PR head by the base's config (round-1 bypass: a PR adding ``skip_prefixes`` hid its own hit)."""

    def test_a_skip_prefixes_edit_in_the_pr_does_not_hide_its_hit(self):
        with TemporaryDirectory() as tmp:
            repo = Path(tmp) / "repo"
            repo.mkdir()
            git(repo, "init", "-q", "-b", "main")
            (repo / "ok.txt").write_text("fine\n")
            git(repo, "add", "-A")
            git(repo, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "base")
            git(repo, "update-ref", "refs/remotes/origin/main", "HEAD")
            (repo / "docs").mkdir()
            (repo / "docs" / "a.md").write_text(f"{TERM}\n")
            (repo / "contracts").mkdir()
            (repo / "contracts" / "house_scan.json").write_text(json.dumps({"allow": {"skip_prefixes": ["docs/"]}}))
            git(repo, "add", "-A")
            git(repo, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "hide")
            head = git(repo, "rev-parse", "HEAD")
            cwd = os.getcwd()
            os.chdir(repo)
            try:
                with mock.patch.dict(os.environ, {"HOUSE_SCAN_DENYLIST": str(write_list(tmp))}):
                    refused = pr_land.denylist_gate("7", head, False, "main")
                # the PR's own config would have made this 0 hits; the base has none, so the hit counts
                self.assertIn("docs/a.md:1 denylist", refused or "")
                # and the head's own config on its own does hide it (the reproduction of the reviewer's bypass)
                tree = Path(tmp) / "tree"
                shutil.copytree(repo, tree)
                own = house_scan.scan_repo(tree, house_scan.load_config(tree / "contracts" / "house_scan.json"), [house_scan.re.compile(TERM)])
                self.assertEqual([h for h in own if h.rule == "denylist"], [])
            finally:
                os.chdir(cwd)

    def test_the_denylist_command_reads_plists_and_svgs_but_the_other_rules_do_not(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp) / "tree"
            root.mkdir()
            (root / "Info.plist").write_text(f"<string>{TERM}</string>\n<string>" + ".".join(["10", "9", "8", "20"]) + "</string>\n")
            terms = house_scan.load_denylist({"HOUSE_SCAN_DENYLIST": str(write_list(tmp))})
            cfg = house_scan.load_config(root / "none.json")
            self.assertEqual([h.rule for h in house_scan.scan_repo(root, cfg, terms)], [])
            self.assertEqual([h.rule for h in house_scan.scan_repo(root, cfg, terms, "denylist") if h.rule == "denylist"], ["denylist"])


if __name__ == "__main__":
    unittest.main()
