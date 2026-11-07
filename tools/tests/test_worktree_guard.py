"""``tools/hooks/worktree_guard.py``: one session, one worktree. Real temporary git repos, no mocks of git."""

import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

HOOKS = Path(__file__).resolve().parents[1] / "hooks"
sys.path.insert(0, str(HOOKS))
import worktree_guard  # noqa: E402

GIT_ENV = {"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"}


def git(cwd, *args):
    subprocess.run(["git", "-C", str(cwd), *args], check=True, capture_output=True, env=dict(os.environ, **GIT_ENV))


class Fixture(unittest.TestCase):
    """A primary checkout with a linked worktree beside it and another nested under ``.claude/worktrees``."""

    @classmethod
    def setUpClass(cls):
        cls.root = Path(os.path.realpath(tempfile.mkdtemp(prefix="wtguard-")))
        cls.primary = cls.root / "primary"
        cls.primary.mkdir()
        git(cls.primary, "init", "-q", "-b", "main")
        (cls.primary / ".gitignore").write_text("build/\n.build/\n.claude/worktrees/\n")
        (cls.primary / "tracked.txt").write_text("a\n")
        (cls.primary / "src").mkdir()
        (cls.primary / "src" / "x.swift").write_text("x\n")
        git(cls.primary, "add", "-A")
        git(cls.primary, "commit", "-q", "-m", "init")
        cls.linked = cls.root / "linked"
        git(cls.primary, "worktree", "add", "-q", "-b", "linked", str(cls.linked))
        cls.nested = cls.primary / ".claude" / "worktrees" / "nested"
        git(cls.primary, "worktree", "add", "-q", "-b", "nested", str(cls.nested))
        cls.plain = cls.root / "plain"
        cls.plain.mkdir()
        cls.sub = cls.primary / "src"
        # an unrelated repository (a scratch `git init`): its primary checkout is not the project's
        cls.scratch = cls.root / "scratch"
        cls.scratch.mkdir()
        git(cls.scratch, "init", "-q", "-b", "main")
        (cls.scratch / "f.txt").write_text("f\n")
        git(cls.scratch, "add", "-A")
        git(cls.scratch, "commit", "-q", "-m", "init")

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.root, ignore_errors=True)

    def setUp(self):
        worktree_guard._RAW_CACHE.clear()
        patch = mock.patch.dict(os.environ, {"CLAUDE_PROJECT_DIR": str(self.primary), "HOME": str(self.root / "home")})
        patch.start()
        self.addCleanup(patch.stop)

    def run_hook(self, payload, *argv, raw=None):
        out, err = io.StringIO(), io.StringIO()
        stdin = io.StringIO(raw if raw is not None else json.dumps(payload))
        with mock.patch("sys.stdin", stdin), redirect_stdout(out), redirect_stderr(err):
            code = worktree_guard.main(list(argv))
        return code, out.getvalue(), err.getvalue()

    def bash(self, command, cwd):
        return self.run_hook({"tool_name": "Bash", "tool_input": {"command": self.fill(command)}, "cwd": str(cwd)})

    def edit(self, path, cwd=None, tool="Edit", key="file_path"):
        return self.run_hook({"tool_name": tool, "tool_input": {key: self.fill(str(path))}, "cwd": str(cwd or self.primary)})

    def fill(self, text):
        return text.replace("{P}", str(self.primary)).replace("{L}", str(self.linked)).replace("{N}", str(self.nested))


class DetectionTests(Fixture):
    def test_primary_versus_linked(self):
        self.assertEqual(worktree_guard.repo_info(str(self.primary)), (str(self.primary), True))
        self.assertEqual(worktree_guard.repo_info(str(self.sub)), (str(self.primary), True))
        self.assertEqual(worktree_guard.repo_info(str(self.linked)), (str(self.linked), False))
        self.assertEqual(worktree_guard.repo_info(str(self.nested)), (str(self.nested), False))
        self.assertIsNone(worktree_guard.repo_info(str(self.plain)))
        self.assertIsNone(worktree_guard.repo_info(str(self.root / "missing")))

    def test_primary_dir_walks_up_to_an_existing_directory(self):
        self.assertEqual(worktree_guard.primary_dir(str(self.primary / "not" / "yet")), str(self.primary))
        self.assertIsNone(worktree_guard.primary_dir(str(self.nested / "not" / "yet")))
        self.assertIsNone(worktree_guard.primary_dir(None))


class SessionStartTests(Fixture):
    def start(self, cwd):
        return self.run_hook({"cwd": str(cwd)}, "--session-start")

    def test_context_only_in_a_primary_checkout(self):
        for cwd in (self.primary, self.sub):
            code, out, _ = self.start(cwd)
            context = json.loads(out)["hookSpecificOutput"]
            self.assertEqual(code, 0)
            self.assertEqual(context["hookEventName"], "SessionStart")
            self.assertIn(str(self.primary), context["additionalContext"])
            self.assertIn("EnterWorktree", context["additionalContext"])
            self.assertIn("worktree_guard", context["additionalContext"])
        for cwd in (self.linked, self.nested, self.plain, self.root / "missing"):
            self.assertEqual(self.start(cwd), (0, "", ""))


class FailOpenTests(Fixture):
    def test_malformed_input_fails_open(self):
        for argv in ((), ("--session-start",)):
            for raw in ("", "not json", "[]", "null", "42"):
                self.assertEqual(self.run_hook(None, *argv, raw=raw), (0, "", ""), (argv, raw))

    def test_git_failure_fails_open(self):
        with mock.patch.object(worktree_guard.subprocess, "run", side_effect=OSError("no git")):
            self.assertEqual(self.bash("git commit -m x", self.primary)[0], 0)
            self.assertEqual(self.edit(self.primary / "tracked.txt")[0], 0)
        with mock.patch.object(worktree_guard, "bash_reason", side_effect=RuntimeError("boom")):
            self.assertEqual(self.bash("git commit -m x", self.primary)[0], 0)

    def test_other_tools_and_empty_targets_pass(self):
        self.assertEqual(self.run_hook({"tool_name": "Read", "tool_input": {"file_path": str(self.primary / "tracked.txt")}})[0], 0)
        self.assertEqual(self.run_hook({"tool_name": "Edit", "tool_input": {}, "cwd": str(self.primary)})[0], 0)
        self.assertEqual(self.run_hook({"tool_name": "Bash", "tool_input": {}, "cwd": str(self.primary)})[0], 0)


class EditTests(Fixture):
    def test_denied_in_primary(self):
        for path in ("{P}/tracked.txt", "{P}/new.swift", "{P}/src/x.swift", "{P}/newdir/deeper/f.md", "{P}/.claude/settings.json"):
            code, _, err = self.edit(path)
            self.assertEqual(code, 2, path)
            self.assertIn("EnterWorktree", err)
            self.assertIn(str(self.primary), err)

    def test_relative_path_resolves_against_cwd(self):
        self.assertEqual(self.edit("tracked.txt", cwd=self.primary)[0], 2)
        self.assertEqual(self.edit("tracked.txt", cwd=self.linked)[0], 0)

    def test_every_edit_tool_is_covered(self):
        for tool, key in (("Edit", "file_path"), ("Write", "file_path"), ("MultiEdit", "file_path"), ("NotebookEdit", "notebook_path")):
            self.assertEqual(self.edit("{P}/tracked.txt", tool=tool, key=key)[0], 2, tool)
            self.assertEqual(self.edit("{L}/tracked.txt", tool=tool, key=key)[0], 0, tool)

    def test_allowed_places(self):
        for path in ("{L}/tracked.txt", "{L}/brand/new/file.py", "{N}/tracked.txt", "{N}/not/yet/there.md",
                     "{N}/f.txt",
                     str(self.plain / "f.txt"), "/private/tmp/claude-501/scratch/f.txt",
                     "{P}/build/handoff/topic.md", "{P}/.build/x/y.o", "{P}/build/f"):
            self.assertEqual(self.edit(path)[0], 0, path)


class GitBashTests(Fixture):
    BLOCKED_IN_PRIMARY = [
        "git commit -m x", "git commit --amend", "git add .", "git add -A", "git add tracked.txt", "git rm tracked.txt",
        "git mv a b", "git restore tracked.txt", "git restore --staged .", "git checkout main", "git checkout -b topic",
        "git checkout -- tracked.txt", "git switch topic", "git switch -c topic", "git reset --hard", "git reset HEAD~1",
        "git merge topic", "git rebase main", "git pull", "git pull --rebase", "git cherry-pick abc", "git revert abc",
        "git am p.mbox", "git apply p.diff", "git clean -fd", "git stash", "git stash push -m x", "git stash pop",
        "git stash drop", "git -c user.name=x commit -m y", "git --no-pager commit -m y", "git -c core.x=1 -c a=b add .",
        "cd src && git commit -m x", "cd . ; git add .", "(git commit -m x)", "true && git commit -m x",
        "echo `git commit -m x`", "echo $(git add .)", "bash -c 'git commit -m x'", "eval 'git add .'", "sudo git commit -m x",
        "env FOO=1 git commit -m x", "command git commit -m x", "git status && git commit -m x",
        "git commit -m x # not an override", "git commit -m \"# worktree-ok: quoted\"", "echo '# worktree-ok: quoted'; git commit -m x",
        "cat <<EOF\n# worktree-ok: heredoc body\nEOF\ngit commit -m x",
        "git commit -m \"use cat <<EOF here\"\ngit add .",
        "git -C . commit -m x", "git -C {P} commit -m x", "git -C src add .", "git --git-dir={P}/.git commit -m x",
    ]
    ALLOWED_IN_PRIMARY = [
        "git status", "git diff", "git diff --stat HEAD", "git log --oneline", "git show HEAD", "git fetch origin",
        "git fetch --prune", "git worktree add ../w2 -b w2 origin/main", "git worktree list", "git worktree remove ../w2",
        "git worktree prune", "git branch -a", "git branch topic", "git push origin topic", "git stash list", "git stash show -p",
        "git apply --check p.diff", "git apply --stat p.diff", "git rev-parse HEAD", "git ls-files", "git remote -v",
        "git config --get user.name", "git tag -l", "git blame tracked.txt", "git grep foo",
        "git commit -m x # worktree-ok: owner asked for it", "git commit -m x\n# worktree-ok: owner asked for it",
        "git -C {L} commit -m x", "git -C {N} add .", "cd {L} && git commit -m x", "cd {N} ; git add .",
        "(cd {L} && git commit -m x)", "env -C {L} git commit -m x", "pushd {L} && git commit -m x",
        "echo 'git commit' > /dev/null", "echo git commit", "ls", "gh pr view 1", "cd {L} && cd {P} && git status",
        "cat <<EOF > /dev/null\ngit commit -m x\nEOF",
    ]
    BLOCKED_FROM_LINKED = [
        "git -C {P} commit -m x", "git -C {P}/src add .", "cd {P} && git commit -m x", "cd {P}; git add .",
        "(cd {P} && git commit -m x)", "env -C {P} git commit -m x", "env --chdir={P} git commit -m x",
        "pushd {P} && git commit -m x", "cd $CLAUDE_PROJECT_DIR && git commit -m x", "git -C \"$CLAUDE_PROJECT_DIR\" add .",
    ]
    ALLOWED_FROM_LINKED = [
        "git commit -m x", "git add .", "git checkout -b topic", "git rebase origin/main", "git stash", "git status",
        "cd {P} && git status", "git -C {P} fetch", "git -C {P} worktree add ../w3", "cd {P} && cd {L} && git commit -m x",
        "(cd {P}); git commit -m x", "cd {N} && git commit -m x",
    ]

    def test_blocked_in_primary(self):
        for command in self.BLOCKED_IN_PRIMARY:
            code, _, err = self.bash(command, self.primary)
            self.assertEqual(code, 2, command)
            self.assertIn("EnterWorktree", err, command)

    def test_blocked_in_a_primary_subdirectory(self):
        self.assertEqual(self.bash("git commit -m x", self.sub)[0], 2)

    def test_allowed_in_primary(self):
        for command in self.ALLOWED_IN_PRIMARY:
            self.assertEqual(self.bash(command, self.primary)[0], 0, command)

    def test_blocked_from_a_linked_worktree(self):
        for command in self.BLOCKED_FROM_LINKED:
            self.assertEqual(self.bash(command, self.linked)[0], 2, command)

    def test_allowed_from_a_linked_worktree(self):
        for command in self.ALLOWED_FROM_LINKED:
            self.assertEqual(self.bash(command, self.linked)[0], 0, command)

    def test_allowed_outside_git(self):
        for command in ("git commit -m x", "git add .", "echo hi > f.txt", "rm f.txt"):
            self.assertEqual(self.bash(command, self.plain)[0], 0, command)

    def test_unknown_directory_fails_open(self):
        for command in ("cd $SOMEWHERE && git commit -m x", "cd - && git add .", "popd && git add ."):
            self.assertEqual(self.bash(command, self.primary)[0], 0, command)


class WriterBashTests(Fixture):
    BLOCKED_IN_PRIMARY = [
        "sed -i 's/a/b/' tracked.txt", "sed -i '' 's/a/b/' tracked.txt", "sed -i.bak -e 's/a/b/' tracked.txt",
        "sed -n -i -e 's/a/b/' tracked.txt", "sed -Ei 's/a/b/' tracked.txt", "sed --in-place 's/a/b/' tracked.txt",
        "sed -i 's/a/b/' src/x.swift", "perl -pi -e 's/a/b/' tracked.txt", "perl -i -pe 's/a/b/' tracked.txt",
        "perl -i.orig -pe 's/a/b/' tracked.txt", "echo hi > new.txt", "echo hi >> tracked.txt", "echo hi >| new.txt",
        "cat x &> out.txt", "echo hi 2> err.txt", "echo hi > {P}/new.txt", "echo hi | tee tracked.txt", "echo hi | tee -a out.txt",
        "touch new.txt", "touch -t 202001010000 new.txt", "touch a b", "cp /etc/hosts tracked.txt", "cp -r /tmp/x ./copy",
        "cp -t src /tmp/f", "mv /tmp/f tracked.txt", "mv tracked.txt /tmp/gone", "mv tracked.txt other.txt", "ln -s /tmp/x link",
        "ln -sf /tmp/x tracked.txt", "install -m 644 /tmp/f tool.sh", "install -d newdir", "rm tracked.txt", "rm -rf src",
        "rm -f new.txt", "rmdir src", "cd src && rm x.swift", "cd src && echo hi > y.txt", "cd src; touch z", "(cd src && touch z)",
        "echo hi > \"$PWD/new.txt\"", "echo hi > $(pwd)/new.txt", "echo hi > $CLAUDE_PROJECT_DIR/new.txt",
        "echo hi > $HOME/../primary/new.txt",
        "bash -c 'echo hi > new.txt'", "tools/ship.sh \"Subject\" --pr", "./tools/ship.sh x", "{P}/tools/ship.sh x",
        "bash tools/ship.sh x", "sh -x ./tools/ship.sh x", "cd src && ../tools/ship.sh x",
        "echo hi > new.txt # not an override", "echo hi > new.txt # worktree-ok:", "echo '# worktree-ok: q'; touch new.txt",
        "cat <<EOF\n# worktree-ok: heredoc body\nEOF\ntouch new.txt",
        "cp a b 2>/dev/null",
    ]
    ALLOWED_IN_PRIMARY = [
        "echo hi > /dev/null", "echo hi 2>/dev/null", "ls 2>&1", "echo hi >&2", "echo hi > /dev/stderr", "cmd 2>&1 | tee /dev/null",
        "echo hi >/dev/stdout", "echo hi | tee /dev/tty", "sed -n '1p' tracked.txt", "sed 's/a/b/' tracked.txt > build/out.txt",
        "sed -i 's/a/b/' build/out.txt", "sed -i '' 's/a/b/' build/out.txt", "perl -pi -e 's/a/b/' build/out.txt",
        "echo hi > build/x.txt", "echo hi >> build/handoff/topic.md", "echo hi | tee build/x.txt", "touch build/handoff/x.md",
        "cp tracked.txt build/copy.txt", "cp -t build tracked.txt", "mv build/a build/b", "ln -s ../tracked.txt build/link",
        "install -d build/dir", "rm -rf build/old", "rm -rf .build", "cd build && echo hi > x", "cd build; rm -rf old",
        "echo hi > {P}/build/x.txt", "echo hi > $PWD/build/x.txt", "rm -rf .claude/worktrees/nested/tmp",
        "echo hi > {N}/x.txt", "touch {N}/new", "cp tracked.txt {N}/copy", "echo hi > /tmp/scratch.txt", "rm -f /tmp/x",
        "echo hi > {L}/x.txt", "cat tracked.txt", "grep -r foo .", "ls -la", "cp a b # worktree-ok: owner approved",
        "echo hi > new.txt # worktree-ok: owner approved", "echo hi > new.txt\n# worktree-ok: owner approved",
        "echo hi > $UNSET/x", "echo hi > \"$OUT\"", "cp tracked.txt $DEST", "cat <<EOF > build/f\nhello\nEOF",
        "cat <<EOF\ntouch new.txt\nEOF", "python3 tools/ship.sh.py", "echo ship.sh", "cp -t",
    ]
    BLOCKED_FROM_LINKED = [
        "echo hi > {P}/new.txt", "sed -i 's/a/b/' {P}/tracked.txt", "rm {P}/tracked.txt", "touch {P}/src/new",
        "cp tracked.txt {P}/tracked.txt", "mv tracked.txt {P}/src/", "echo hi | tee {P}/new.txt", "cd {P} && touch new",
        "cd {P} && echo hi > new.txt", "ln -s x {P}/link", "install tracked.txt {P}/tool", "cp -t {P} tracked.txt",
        "cd {P}; ./tools/ship.sh x", "(cd {P} && tools/ship.sh x)", "env -C {P} tools/ship.sh x",
    ]
    ALLOWED_FROM_LINKED = [
        "echo hi > new.txt", "sed -i 's/a/b/' tracked.txt", "rm tracked.txt", "touch src/new", "cp tracked.txt copy.txt",
        "tools/ship.sh x --pr", "./tools/ship.sh x", "{L}/tools/ship.sh x", "{P}/tools/ship.sh x", "cp {P}/tracked.txt copy.txt",
        "cat {P}/tracked.txt > copy.txt", "cd {P}/build && echo hi > x", "echo hi > {P}/build/x.txt", "rm {P}/build/old",
        "mv {P}/build/a b", "sed -n 1p {P}/tracked.txt", "cd {P} && git status", "cd {P} && cd {L} && touch new",
    ]

    def test_blocked_in_primary(self):
        for command in self.BLOCKED_IN_PRIMARY:
            code, _, err = self.bash(command, self.primary)
            self.assertEqual(code, 2, command)
            self.assertIn("worktree", err, command)

    def test_allowed_in_primary(self):
        for command in self.ALLOWED_IN_PRIMARY:
            self.assertEqual(self.bash(command, self.primary)[0], 0, command)

    def test_blocked_from_a_linked_worktree(self):
        for command in self.BLOCKED_FROM_LINKED:
            self.assertEqual(self.bash(command, self.linked)[0], 2, command)

    def test_allowed_from_a_linked_worktree(self):
        for command in self.ALLOWED_FROM_LINKED:
            self.assertEqual(self.bash(command, self.linked)[0], 0, command)

    def test_the_message_names_the_checkout_and_the_way_out(self):
        _, _, err = self.bash("touch new.txt", self.primary)
        for needle in (str(self.primary), "EnterWorktree", "worktree-ok", "origin/main"):
            self.assertIn(needle, err)

    def test_large_command_checks_quickly(self):
        body = "\n".join("echo line %d 'quoted text' | cat > /dev/null" % i for i in range(3000))
        start = time.perf_counter()
        code = self.bash("cat <<'EOF' > build/f\n%s\nEOF\ngit commit -m x\n%s" % (body, body), self.primary)[0]
        self.assertEqual(code, 2)
        self.assertLess(time.perf_counter() - start, 3)


def table(name, blocked, allowed, cwd="primary"):
    """A test method that runs every command of ``blocked`` (exit 2) and ``allowed`` (exit 0) in ``cwd``."""
    def test(self):
        directory = getattr(self, cwd)
        for command in blocked:
            self.assertEqual(self.bash(command, directory)[0], 2, command)
        for command in allowed:
            self.assertEqual(self.bash(command, directory)[0], 0, command)
    test.__name__ = name
    return test


class ReviewRoundTests(Fixture):
    """Findings of the independent review of the first version."""

    test_continuations = table(
        "test_continuations",
        ["sed -i '' \\\n  -e s/a/b/ \\\n  tracked.txt", "git \\\n  commit -m x", "git add \\\n .", "touch \\\n new.txt"],
        ["rm -rf \\\n  build/foo \\\n  build/bar", "cp build/a \\\n  build/b", "echo a \\\n b"])
    test_continuation_with_git_c_from_linked = table(
        "test_continuation_with_git_c_from_linked", ["git -C {P} \\\n  commit -m x"], [], cwd="linked")

    test_gh_branch_changes = table(
        "test_gh_branch_changes", ["gh pr checkout 12", "gh repo sync", "gh pr checkout 12 --branch x"],
        ["gh pr view 1", "gh pr create --title x --body y", "gh pr list", "gh issue view 5", "gh repo view"])
    test_gh_in_a_linked_worktree = table(
        "test_gh_in_a_linked_worktree", [], ["gh pr checkout 12", "gh repo sync"], cwd="linked")

    test_truncate_patch_and_branch_rename = table(
        "test_truncate_patch_and_branch_rename",
        ["truncate -s 0 tracked.txt", "truncate -s0 tracked.txt", "truncate --size=0 tracked.txt",
         "patch -p1 < x.diff", "patch tracked.txt x.diff", "git branch -m old new", "git branch -M new",
         "git branch --move a b", "git branch -m new"],
        ["patch --dry-run -p1 < x.diff", "truncate -s 0 build/x", "git branch -d old", "git branch -a", "git branch topic"])
    test_git_dir_and_work_tree_from_linked = table(
        "test_git_dir_and_work_tree_from_linked",
        ["GIT_DIR={P}/.git git commit -m x", "GIT_DIR={P}/.git GIT_WORK_TREE={P} git add .", "env GIT_WORK_TREE={P} git add .",
         "git --git-dir={P}/.git commit -m x", "git --git-dir {P}/.git --work-tree {P} add .", "git --work-tree={P} checkout main",
         "GIT_WORK_TREE={P} git reset --hard", "export_x=1 GIT_DIR={P}/.git git stash"],
        ["GIT_DIR={P}/.git git status", "git --work-tree={L} add .", "git --git-dir={P}/.git log", "truncate -s 0 tracked.txt",
         "git branch -m new"], cwd="linked")

    test_help_flags = table(
        "test_help_flags", ["git commit -m x"], ["git commit --help", "git add -h", "git checkout --help", "git stash --help"])

    test_not_redirects = table(
        "test_not_redirects", ["echo $((1>2)) > new.txt"],
        ["[[ a > b ]] && echo ok", "(( 1 > 2 )) && echo no", "echo $((1>2))", "if [[ \"$x\" > \"y\" ]]; then echo hi; fi",
         "echo $((1>2)) > build/x", "x=$((3>2)); echo $x"])

    test_worktree_add_chain = table(
        "test_worktree_add_chain",
        ["git worktree add ../w9 -b w9 origin/main && git commit -m x", "git worktree add ../w9; cd . ; git add .",
         "git worktree add ../w9 && cd {P} && git add ."],
        ["git worktree add ../w9 -b w9 origin/main && cd ../w9 && git add . && git commit -m x",
         "git worktree add -b x {P}/.claude/worktrees/y origin/main && cd {P}/.claude/worktrees/y && git commit -m x",
         "git worktree add --detach build/rel ios/v1 && cd build/rel && touch x && echo hi > y.txt",
         "git worktree add -B q ../w9 && git -C ../w9 commit -m x", "git worktree add ../w9 && echo hi > ../w9/f && rm ../w9/f"])

    test_substitutions_in_double_quotes = table(
        "test_substitutions_in_double_quotes",
        ['out="$(git pull 2>&1)"', 'echo "x $(git add .)"', 'echo "`git commit -m x`"', 'echo "a $(echo "b $(git reset --hard)")"',
         'out="$(touch new.txt)"'],
        ['gh pr create --body "$(cat <<\'EOF\'\nsummary\ngit add is not needed\n"quoted" and \'single\'\nEOF\n)"',
         'gh pr create --title "t" --body "$(cat <<\'EOF\'\nGuard 5" screens\ngit commit -m x\nEOF\n)"',
         'echo "$(git status)"', 'out="$(cd {L} && git pull 2>&1)"', 'echo "$(date)" "$(pwd)"'])

    def test_a_scratch_repository_is_not_guarded(self):
        for command in ("git commit -m x", "git add .", "echo hi > new.txt", "rm f.txt", "git checkout -b t", "sed -i s/f/g/ f.txt"):
            self.assertEqual(self.bash(command, self.scratch)[0], 0, command)
        self.assertEqual(self.bash("echo hi > {P}/new.txt", self.scratch)[0], 2)
        self.assertEqual(self.edit(self.scratch / "f.txt", cwd=self.scratch)[0], 0)
        self.assertEqual(self.edit(self.primary / "tracked.txt", cwd=self.scratch)[0], 2)
        self.assertEqual(self.start(self.scratch), (0, "", ""))

    def start(self, cwd):
        return self.run_hook({"cwd": str(cwd)}, "--session-start")

    def test_scope_follows_the_project_even_when_it_is_a_linked_worktree(self):
        with mock.patch.dict(os.environ, {"CLAUDE_PROJECT_DIR": str(self.linked)}):
            self.assertEqual(self.bash("git commit -m x", self.primary)[0], 2)
            self.assertEqual(self.bash("git commit -m x", self.linked)[0], 0)
            self.assertEqual(self.bash("git commit -m x", self.scratch)[0], 0)
            self.assertEqual(self.edit(self.primary / "tracked.txt")[0], 2)
            self.assertIn("EnterWorktree", self.start(self.primary)[1])

    def test_scope_falls_back_to_the_hook_cwd(self):
        env = {k: v for k, v in os.environ.items() if k != "CLAUDE_PROJECT_DIR"}
        with mock.patch.dict(os.environ, env, clear=True):
            self.assertEqual(self.bash("git commit -m x", self.primary)[0], 2)
            self.assertEqual(self.bash("git commit -m x", self.scratch)[0], 2)  # no project dir: the cwd's repository
            self.assertEqual(self.bash("echo hi > {P}/new.txt", self.scratch)[0], 0)
            self.assertEqual(self.bash("git commit -m x", self.plain)[0], 0)

    def test_no_project_repository_guards_nothing(self):
        with mock.patch.dict(os.environ, {"CLAUDE_PROJECT_DIR": str(self.plain)}):
            self.assertEqual(self.bash("git commit -m x", self.plain)[0], 0)
            self.assertEqual(self.bash("git commit -m x", self.primary)[0], 0)

    def test_many_targets_are_checked_in_one_batch(self):
        command = "rm -f " + " ".join("build/old/f%d.o" % i for i in range(2000))
        real_run = subprocess.run
        calls = []

        def counting(*args, **kwargs):
            calls.append(args[0])
            return real_run(*args, **kwargs)

        start = time.perf_counter()
        with mock.patch.object(worktree_guard.subprocess, "run", counting):
            code = self.bash(command, self.primary)[0]
        elapsed = time.perf_counter() - start
        self.assertEqual(code, 0)
        self.assertLess(elapsed, 2)
        self.assertLessEqual(len(calls), 6, calls[:8])
        self.assertEqual(sum(1 for c in calls if "check-ignore" in c), 1)
        # one unignored path among them still blocks
        self.assertEqual(self.bash(command + " tracked.txt", self.primary)[0], 2)


class ScriptTests(Fixture):
    def test_runs_as_a_script_from_any_directory(self):
        script = str(HOOKS / "worktree_guard.py")
        payload = json.dumps({"tool_name": "Bash", "tool_input": {"command": "git commit -m x"}, "cwd": str(self.primary)})
        env = {k: v for k, v in os.environ.items() if k != "PYTHONPATH"}
        denied = subprocess.run([sys.executable, script], input=payload, capture_output=True, text=True, cwd=str(self.plain), env=env)
        self.assertEqual(denied.returncode, 2, denied.stderr)
        start = subprocess.run([sys.executable, script, "--session-start"], input=json.dumps({"cwd": str(self.primary)}),
                               capture_output=True, text=True, cwd=str(self.plain), env=env)
        self.assertEqual(start.returncode, 0)
        self.assertIn("EnterWorktree", start.stdout)
        bad = subprocess.run([sys.executable, script], input="nope", capture_output=True, text=True, env=env)
        self.assertEqual((bad.returncode, bad.stdout, bad.stderr), (0, "", ""))

    def test_registered_in_settings(self):
        settings = json.loads((Path(__file__).resolve().parents[2] / ".claude" / "settings.json").read_text())
        pre = settings["hooks"]["PreToolUse"]
        commands = {entry["matcher"]: [h["command"] for h in entry["hooks"]] for entry in pre}
        guarded = 'f="$CLAUDE_PROJECT_DIR/tools/hooks/worktree_guard.py"; [ -f "$f" ] || exit 0; exec python3 "$f"'
        self.assertEqual(commands["Bash"][-1], guarded)
        self.assertEqual(commands["Edit|Write|MultiEdit|NotebookEdit"][0], guarded)
        starts = [h["command"] for entry in settings["hooks"]["SessionStart"] for h in entry["hooks"]]
        self.assertIn(guarded + " --session-start", starts)


if __name__ == "__main__":
    unittest.main()
