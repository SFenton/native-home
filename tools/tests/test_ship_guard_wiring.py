"""Ship safety split (owner, 2026-11-04): ``ship.sh`` stays agent-editable, the guard it calls is owner-only.

Wiring: ship.sh calls ``ship_guard.sh`` before every commit and push, the guard keeps every pattern, ``commit_guard`` is
registered, and the owner-only lists name the three guard files but not ship.sh. Behaviour: both guards in a temp repo.
This file is itself owner-only (``tools/lane_land.py`` DEFAULT_PROTECTED and ``tools/triage/config.json``).
"""

import io
import json
import os
import re
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stderr
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools" / "hooks"))
import commit_guard  # noqa: E402
import lane_land  # noqa: E402

GUARD = ROOT / "tools" / "ship_guard.sh"
NEW_PROTECTED = ("tools/ship_guard.sh", "tools/hooks/commit_guard.py", "tools/tests/test_ship_guard_wiring.py")


def git(cwd, *args):
    subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True)


def make_repo(branch):
    tmp = tempfile.TemporaryDirectory()
    git(tmp.name, "init", "-q", "-b", branch)
    git(tmp.name, "config", "user.email", "t@example.com")
    git(tmp.name, "config", "user.name", "t")
    (Path(tmp.name) / "seed.txt").write_text("x\n")
    git(tmp.name, "add", "-A")
    git(tmp.name, "commit", "-q", "-m", "seed")
    return tmp


def run_guard(cwd, mode="all", env=None):
    return subprocess.run(["bash", str(GUARD), mode], cwd=cwd, capture_output=True, text=True, env={**os.environ, **(env or {})})


def hook(command, cwd):
    err = io.StringIO()
    body = json.dumps({"tool_name": "Bash", "tool_input": {"command": command}, "cwd": cwd})
    with mock.patch.object(sys, "stdin", io.StringIO(body)), redirect_stderr(err):
        return commit_guard.main(), err.getvalue()


class WiringTests(unittest.TestCase):
    def test_ship_calls_guard_before_every_commit_and_push(self):
        lines = (ROOT / "tools" / "ship.sh").read_text().splitlines()
        code = [(i, l) for i, l in enumerate(lines) if not l.lstrip().startswith("#")]
        guards = [i for i, l in code if re.search(r'"\$GUARD"|ship_guard\.sh', l) and "GUARD=" not in l]
        self.assertTrue(guards, "ship.sh no longer calls ship_guard.sh")
        for verb in ("git commit", "git push"):
            uses = [i for i, l in code if verb in l]
            self.assertTrue(uses, f"ship.sh has no {verb}")
            for use in uses:
                self.assertTrue(any(g < use for g in guards), f"{verb} on line {use + 1} has no guard call before it")
        push = next(i for i, l in code if "git push" in l)
        self.assertIn("branch", lines[push - 1], "the push needs the branch check right before it")
        add = next(i for i, l in code if "git add -A" in l)
        commit = next(i for i, l in code if "git commit" in l)
        self.assertTrue(any(add < g < commit and "staged" in lines[g] for g in guards), "secrets check between add and commit")

    def test_guard_keeps_every_pattern(self):
        text = GUARD.read_text()
        for needle in ("main|master|HEAD", r"\.env[^/]*", r"[^/]*\.env", r"[^/]*\.p12", r"[^/]*\.p8", r"[^/]*\.mobileprovision",
                       r"grep -v '\.env\.example$'", "git diff --cached --name-only"):
            self.assertIn(needle, text)

    def test_commit_guard_registered_for_bash(self):
        settings = json.loads((ROOT / ".claude" / "settings.json").read_text())
        found = [h["command"] for block in settings["hooks"]["PreToolUse"] if block["matcher"] == "Bash" for h in block["hooks"]]
        self.assertTrue(any("tools/hooks/commit_guard.py" in c for c in found), found)

    def test_the_guard_files_are_unlocked_but_ship_must_still_call_them(self):
        """Owner, 2026-11-07: the guard files left the fixed set; the wiring tests above still fail if ship.sh stops calling them."""
        self.assertNotIn("tools/ship.sh", lane_land.DEFAULT_PROTECTED)
        config = json.loads((ROOT / "tools" / "triage" / "config.json").read_text())
        for path in NEW_PROTECTED:
            self.assertNotIn(path, lane_land.DEFAULT_PROTECTED)
            self.assertNotIn(path, config["protected_paths"])


class ShipGuardBehaviourTests(unittest.TestCase):
    def stage(self, tmp, name):
        (Path(tmp.name) / name).write_text("s\n")
        git(tmp.name, "add", "-A")

    def test_secrets_refused_and_index_reset(self):
        for name in (".env", "prod.env", ".env.local", "k.p12", "AuthKey.p8", "a.mobileprovision", "dir/.env"):
            with self.subTest(name=name):
                tmp = make_repo("agents/x")
                (Path(tmp.name) / "dir").mkdir()
                self.stage(tmp, name)
                done = run_guard(tmp.name, "staged")
                self.assertEqual(done.returncode, 1)
                self.assertIn("these must never be committed", done.stderr)
                self.assertIn(name, done.stderr)
                staged = subprocess.run(["git", "diff", "--cached", "--name-only"], cwd=tmp.name, capture_output=True, text=True)
                self.assertEqual(staged.stdout.strip(), "")  # reset, as ship.sh always did
                tmp.cleanup()

    def test_env_example_and_normal_files_pass(self):
        tmp = make_repo("agents/x")
        self.stage(tmp, ".env.example")
        self.stage(tmp, "Sources.swift")
        self.assertEqual(run_guard(tmp.name).returncode, 0)
        tmp.cleanup()

    def test_branch_refusals(self):
        for branch in ("main", "master"):
            tmp = make_repo(branch)
            done = run_guard(tmp.name, "branch")
            self.assertEqual(done.returncode, 1)
            self.assertIn(f"refusing to commit on '{branch}'", done.stderr)
            tmp.cleanup()
        tmp = make_repo("agents/x")
        git(tmp.name, "checkout", "-q", "--detach")
        self.assertEqual(run_guard(tmp.name, "branch").returncode, 1)
        tmp.cleanup()

    def test_bad_mode(self):
        self.assertEqual(run_guard(str(ROOT), "nope").returncode, 2)


SHIP_ENV = {**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@example.com", "GIT_COMMITTER_NAME": "t",
            "GIT_COMMITTER_EMAIL": "t@example.com", "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_SYSTEM": "/dev/null"}


def git_env(cwd, *args):
    return subprocess.run(["git", *args], cwd=cwd, env=SHIP_ENV, capture_output=True, text=True, check=True).stdout.strip()


def ship_clone(tmp, ship_text=None):
    """A clone of a local bare origin holding the real ship.sh (or ``ship_text``) beside the real ship_guard.sh."""
    origin = Path(tmp) / "origin.git"
    clone = Path(tmp) / "clone"
    git_env(tmp, "init", "-q", "--bare", "-b", "main", str(origin))
    git_env(tmp, "clone", "-q", str(origin), str(clone))
    (clone / "tools").mkdir()
    (clone / "tools" / "ship.sh").write_text(ship_text if ship_text is not None else (ROOT / "tools" / "ship.sh").read_text())
    (clone / "tools" / "ship_guard.sh").write_text(GUARD.read_text())
    (clone / "tools" / "ship_guard.sh").chmod(0o755)
    (clone / "tools" / "review_verdict.py").write_text((ROOT / "tools" / "review_verdict.py").read_text())
    (clone / "README.md").write_text("hi\n")
    git_env(clone, "add", "-A")
    git_env(clone, "commit", "-q", "-m", "init")
    git_env(clone, "push", "-q", "-u", "origin", "main")
    return clone


def ship_failures(ship_text=None):
    """Run the end-to-end refusal checks against ship.sh; returns the checks that did not hold (empty = the guard works)."""
    failed = []

    def ship(clone):
        return subprocess.run(["bash", "tools/ship.sh", "Add stuff", "--no-push"], cwd=clone, env=SHIP_ENV, capture_output=True, text=True)

    for name in (".env", "k.p12"):
        with tempfile.TemporaryDirectory() as tmp:
            clone = ship_clone(tmp, ship_text)
            git_env(clone, "checkout", "-q", "-b", "agents/x")
            before = git_env(clone, "rev-parse", "HEAD")
            (clone / name).write_text("secret\n")
            (clone / "ok.txt").write_text("ok\n")
            done = ship(clone)
            if done.returncode == 0 or "must never be committed" not in done.stderr:
                failed.append(f"{name}: ship was not refused by the guard")
            if git_env(clone, "rev-parse", "HEAD") != before:
                failed.append(f"{name}: a commit was made")
            if git_env(clone, "diff", "--cached", "--name-only"):
                failed.append(f"{name}: index not empty")
    with tempfile.TemporaryDirectory() as tmp:
        clone = ship_clone(tmp, ship_text)
        (clone / "a.txt").write_text("x\n")
        done = ship(clone)
        if done.returncode == 0 or "refusing to commit on 'main'" not in done.stderr:
            failed.append("main: ship was not refused by the guard")
        if git_env(clone, "diff", "--cached", "--name-only"):
            failed.append("main: files were staged before the refusal")
    return failed


class ShipEndToEndTests(unittest.TestCase):
    """The real ship.sh with the real ship_guard.sh: this protected test is the control if ship.sh is edited."""

    def test_guard_refuses_secrets_and_main(self):
        self.assertEqual(ship_failures(), [])

    def test_normal_lane_run_commits(self):
        with tempfile.TemporaryDirectory() as tmp:
            clone = ship_clone(tmp)
            git_env(clone, "checkout", "-q", "-b", "agents/x")
            (clone / ".env.example").write_text("A=\n")
            (clone / "ok.txt").write_text("ok\n")
            done = subprocess.run(["bash", "tools/ship.sh", "Add ok", "--note", "none"], cwd=clone, env=SHIP_ENV, capture_output=True, text=True)
            self.assertEqual(done.returncode, 0, done.stderr)
            self.assertIn("Release-Note: none", git_env(clone, "log", "-1", "--format=%B"))
            pushed = git_env(tmp, "--git-dir", str(Path(tmp) / "origin.git"), "rev-parse", "agents/x")
            self.assertEqual(git_env(clone, "rev-parse", "HEAD"), pushed)

    def test_guard_variable_and_call_lines_are_not_neutered(self):
        text = (ROOT / "tools" / "ship.sh").read_text()
        assigns = [l.strip() for l in text.splitlines() if re.match(r"\s*GUARD=", l)]
        self.assertEqual(len(assigns), 1)
        self.assertRegex(assigns[0], r'^GUARD="\$\(dirname "\$0"\)/ship_guard\.sh"(\s+#.*)?$')
        calls = [l.strip() for l in text.splitlines() if "$GUARD" in l and not l.lstrip().startswith("#") and "GUARD=" not in l]
        self.assertGreaterEqual(len(calls), 3)
        for line in calls:
            self.assertRegex(line, r'^"\$GUARD" (branch|staged)$', f"guard call must stand alone: {line}")

    def test_neutered_ship_is_caught_by_the_behaviour_checks(self):
        text = (ROOT / "tools" / "ship.sh").read_text()
        mutants = {
            "or-true": text.replace('"$GUARD" staged', '"$GUARD" staged || true').replace('"$GUARD" branch\n\ngit add', '"$GUARD" branch || true\n\ngit add'),
            "guard-true": text.replace('GUARD="$(dirname "$0")/ship_guard.sh"', "GUARD=true"),
        }
        for label, mutant in mutants.items():
            with self.subTest(mutant=label):
                self.assertNotEqual(mutant, text)
                self.assertTrue(ship_failures(mutant), "the behaviour checks did not catch the neutered ship.sh")


class CommitGuardBehaviourTests(unittest.TestCase):
    def setUp(self):
        self.lane = make_repo("agents/x")
        self.main = make_repo("main")
        self.addCleanup(self.lane.cleanup)
        self.addCleanup(self.main.cleanup)

    def code(self, command, repo=None):
        return hook(command, (repo or self.lane).name)[0]

    def test_main_refused_for_commit_and_push(self):
        self.assertEqual(self.code('git commit -m "x"', self.main), 2)
        self.assertEqual(self.code("git push origin HEAD", self.main), 2)
        self.assertEqual(self.code(f'cd {self.main.name} && git commit -m x', self.lane), 2)
        self.assertEqual(self.code(f"git -C {self.main.name} push", self.lane), 2)
        self.assertEqual(self.code(f'bash -c "git commit -m x"', self.main), 2)

    def test_lane_commit_and_push_allowed(self):
        self.assertEqual(self.code('git commit -m "Fix it" -m "Release-Note: none"'), 0)
        self.assertEqual(self.code("git push -u origin agents/x"), 0)
        self.assertEqual(self.code(f"cd {self.lane.name} && git commit -m ok"), 0)
        self.assertEqual(self.code(f"git -C {self.lane.name} commit -m ok", self.main), 0)

    def test_staged_secrets_refused(self):
        (Path(self.lane.name) / "k.p12").write_text("s\n")
        git(self.lane.name, "add", "-A")
        code, err = hook('git commit -m "x"', self.lane.name)
        self.assertEqual(code, 2)
        self.assertIn("k.p12", err)
        staged = subprocess.run(["git", "diff", "--cached", "--name-only"], cwd=self.lane.name, capture_output=True, text=True)
        self.assertIn("k.p12", staged.stdout)  # the hook never touches the index

    def test_commit_all_checks_modified_tracked_files(self):
        (Path(self.lane.name) / ".env").write_text("s\n")
        git(self.lane.name, "add", "-f", ".env")
        git(self.lane.name, "commit", "-q", "-m", "env", "--no-verify")
        (Path(self.lane.name) / ".env").write_text("changed\n")
        self.assertEqual(self.code("git commit -am x"), 2)

    def test_no_verify_refused(self):
        for cmd in ("git commit --no-verify -m x", "git commit -n -m x", "git commit -m x --no-verify", "git commit -anm x",
                    "git -c user.name=a commit -n -m x"):
            with self.subTest(cmd=cmd):
                self.assertEqual(self.code(cmd), 2)

    def test_abbreviated_no_verify_hookspath_and_gpg_sign(self):
        for cmd in ("git commit --no-veri -m x", "git commit --no-verif -m x", "git commit --no-verify -m x",
                    "git -c core.hooksPath=/dev/null commit -m x", "git -c core.hookspath=x commit -m x",
                    "git commit -S -n -m x", "git commit --gpg-sign --no-verify -m x"):
            with self.subTest(cmd=cmd):
                self.assertEqual(self.code(cmd), 2)
        for cmd in ("git commit -S -m x", "git commit --gpg-sign=ABC -m x", "git commit --no-edit -m x", "git commit --no -m x"):
            with self.subTest(cmd=cmd):
                self.assertEqual(self.code(cmd), 0)

    def test_message_values_are_not_flags(self):
        for cmd in ("git commit -m -n", 'git commit -m "use --no-verify never"', "git commit -mn", "git commit -F msg.txt"):
            with self.subTest(cmd=cmd):
                self.assertEqual(self.code(cmd), 0)

    def test_words_in_quotes_comments_and_heredocs_ignored(self):
        for cmd in ('echo "git commit --no-verify"', "echo 'git push' # git commit -n", "grep 'git commit' docs.md",
                    "cat <<'EOF'\ngit commit --no-verify\ngit push\nEOF", "# git commit -n\nls",
                    "python3 -c 'print(\"git commit -n\")'"):
            with self.subTest(cmd=cmd):
                self.assertEqual(self.code(cmd, self.main), 0)

    def test_read_only_git_and_other_tools_pass_on_main(self):
        for cmd in ("git status", "git log --oneline", "git diff --cached --name-only", "git branch -a", "git fetch origin",
                    "git add -A", "git checkout -b agents/y", "ls && git rev-parse HEAD"):
            with self.subTest(cmd=cmd):
                self.assertEqual(self.code(cmd, self.main), 0)

    def test_non_bash_and_bad_payload(self):
        with mock.patch.object(sys, "stdin", io.StringIO(json.dumps({"tool_name": "Read", "tool_input": {}}))):
            self.assertEqual(commit_guard.main(), 0)
        with mock.patch.object(sys, "stdin", io.StringIO("not json")):
            self.assertEqual(commit_guard.main(), 0)


if __name__ == "__main__":
    unittest.main()
