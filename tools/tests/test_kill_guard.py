"""``tools/hooks/kill_guard.py``: block machine-wide process kills, allow scoped ones."""

import io
import json
import os
import sys
import time
import unittest
from contextlib import redirect_stderr
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "hooks"))
import kill_guard  # noqa: E402

MAIN = "/Users/me/repos/Proj"
WT = MAIN + "/.claude/worktrees/agent-1"
CWD = WT + "/apple"

BLOCKED = [
    # the 2026-10-30 incident, verbatim and in quoting variants
    'pkill -f "swift-test|swift-testing|swift-build|xctest"',
    "pkill -f 'swift-test|swift-testing|swift-build|xctest'",
    "pkill -f swift-test",
    "pkill -9 -f xctest",
    "pkill -fl xctest",
    "pkill xctest",
    "pkill -KILL swift-build",
    "sudo pkill -f xctest",
    "sudo -u root pkill -f xctest",
    "FOO=1 pkill -f xctest",
    "env FOO=1 pkill -f xctest",
    "cd apple && pkill -f xctest; echo done",
    "swift build || pkill -f swift-build",
    "echo hi | pkill -f xctest",
    'bash -c "pkill -f xctest"',
    "eval 'pkill -f xctest'",
    "killall xctest",
    "killall -9 Xcode",
    "sudo killall swift-test",
    # unscoped alternative next to a scoped one
    f'pkill -f "{WT}/build|xctest"',
    # path outside the worktree, and a sibling with the same prefix
    "pkill -f /Users/me/repos/Proj/other/thing",
    f"pkill -f {WT}-other/thing",
    # shared infrastructure, even inside a scoped path
    "pkill -f Runner.Listener",
    "pkill -f Runner.Worker",
    f"pkill -f {WT}/Runner.Worker",
    "pkill -f actions-runner-hass",
    f"pkill -f {WT}/actions-runner",
    "pkill -f devcap",
    f"pkill -f {WT}/tools/devcap.py",
    "pkill -f Simulator",
    "pkill -f CoreSimulator",
    "pkill launchd",
    "pkill -P 123 Runner.Worker",
    # kill fed by pgrep
    "kill $(pgrep -f xctest)",
    "kill -9 $(pgrep -f 'swift-test|xctest')",
    "kill `pgrep -f xctest`",
    "pgrep -f xctest | xargs kill",
    "pgrep xctest | xargs kill -9",
    "pgrep -f xctest | xargs -n1 kill",
    f"kill $(pgrep -f {WT}/x Runner.Worker)",
    "kill -9 -1",
    "kill -1",
    # shell constructs and wrappers (review round 1)
    "if pgrep xctest; then pkill -f xctest; fi",
    "for p in $(pgrep -f xctest); do kill $p; done",
    "pgrep -f xctest | while read p; do kill $p; done",
    "{ pkill -f xctest; }",
    "timeout 5 pkill -f xctest",
    "gtimeout -s KILL 5 pkill -f xctest",
    "watch -n 2 pkill -f xctest",
    "while true; do pkill -f xctest; done",
    "! pkill -f xctest",
    # scope is the agent's own worktree, not the project root or a sibling lane
    f"pkill -f {MAIN}/.*xctest",
    f"pkill -f {MAIN}",
    f"pkill -f {MAIN}/",
    f"pkill -f {MAIN}/.claude/worktrees/agent-2/build",
    f"pkill -f {WT}",
    f"pkill -f {WT}/.*xctest",
    f"pkill -f '({WT})?xctest'",
    f"pkill -f '({WT}/x)?xctest'",
    f"pkill -f 'xctest|{WT}'",
    "pkill -f /private/tmp/claude-501",
    # lookups feeding a kill
    "ps aux | grep xctest | grep -v grep | awk '{print $2}' | xargs kill",
    "ps aux | grep -E 'swift-test|xctest' | awk '{print $2}' | xargs kill -9",
    "kill $(ps aux | grep xctest | awk '{print $2}')",
    "pgrep -fl xctest; kill $PID",
    "pkill -P 1",
    "pkill -P 01 xctest",
    "pkill -P 0,1",
    "env --split-string='pkill -f xctest'",
    "env --split-string=\"pkill -f xctest\" true",
    "env -S'pkill -f xctest'",
    f'env -C {MAIN} pkill -f "$PWD/build"',
    # a comment must not hide the next line (round 3)
    "# stop stray test runs\npkill -f xctest",
    "swift build  # compile\npkill -f swift-build",
    "echo hi # note\nkillall xctest",
    "# cleanup\nxcrun simctl shutdown all",
    "echo a#b; pkill -f xctest",
    "echo '# not a comment'; pkill -f xctest",
    'echo "# kill-ok: reason"; pkill -f xctest',
    "echo $#; pkill -f xctest",
    # a ps filter in one pipeline does not vouch for another
    "ps aux | grep \"$PWD/x\" >/dev/null; ps aux | awk '{print $2}' | xargs kill",
    "pkill -P 1,2 xctest",
    "pkill -P 2,1",
    # a cd/pushd/popd changes what $PWD means (the 2026-10-30 incident, as the runner would have run it)
    'cd ~/actions-runner-hass/_work/Fenton-HASS-Native/Fenton-HASS-Native && pkill -f "$PWD/apple/.build"',
    'cd "$CLAUDE_PROJECT_DIR" && pkill -f "$PWD/.claude/worktrees"',
    f'pushd {MAIN}/.claude/worktrees/agent-2 && pkill -f "$(pwd)/build"',
    f'(cd {MAIN}/.claude/worktrees/agent-2; pkill -f "${{PWD}}/build")',
    f"cd /tmp && popd && pkill -f $PWD/build",
    # lookups
    "ps aux | awk '/xctest/{print $2}' | xargs kill",
    "ps aux | awk '{print $2}' | xargs kill",
    "pidof xctest | xargs kill",
    "kill $(pidof xctest)",
    # holes closed in round 2
    "find /tmp -name x -exec pkill -f xctest ';'",
    "find . -exec pkill -f xctest \\;",
    "env -S 'pkill -f xctest'",
    "env -S\"pkill -f xctest\" true",
    "pgrep -f xctest | parallel kill",
    "bash <<EOF\npkill -f xctest\nEOF",
    "cat <<EOF | sh\npkill -f xctest\nEOF",
    "pkill -9 -P1 xctest",
    "xcrun simctl delete all",
    # the override must be a real comment with a reason
    "pkill -f xctest # skill-okay",
    "pkill -f xctest # kill-ok:",
    "pkill -f xctest kill-ok: reason",
    # review minors from #234 (issue #236): quoted heredoc markers, override in a heredoc body, backtick comments, env flags
    'git commit -m "use cat <<EOF here"\npkill -f xctest',
    "echo '<<EOF'\npkill -f xctest",
    'echo "<<-EOF"\npkill -f xctest',
    "echo \"<<'EOF'\"\npkill -f xctest",
    "echo '<<\"EOF\"'\npkill -f xctest",
    "echo hi # <<EOF\npkill -f xctest",
    "cat <<EOF > f\n# kill-ok: x\nEOF\npkill -f xctest",
    "cat <<-EOF\n# kill-ok: x\nEOF\npkill -f xctest",
    "cat <<'EOF'\n# kill-ok: reason\nEOF\npkill -f xctest",
    'git commit -m "$(cat <<\'EOF\'\nmsg\n# kill-ok: reason\nEOF\n)"\npkill -f xctest',
    "echo `date #now`; pkill -f xctest",
    "echo `date #now` && killall xctest",
    "echo `date  # x`\npkill -f xctest",
    "env -iS 'pkill -f xctest'",
    "env -uS 'pkill -f xctest'",
    "env -iuFOO pkill -f xctest",
    "env -i pkill -f xctest",
    "env -iC /tmp pkill -f xctest",
    "env -i FOO=1 pkill -f xctest",
    "env -iSpkill\\ -f\\ xctest",
    # review round: backslash-newline continuation, and substitutions inside double quotes
    "xcrun simctl \\\n  shutdown all",
    "pkill \\\n  -f xctest",
    "kill \\\n $(pgrep -f xctest)",
    'kill "$(pgrep -f xctest)"',
    'kill -9 "`pgrep -f xctest`"',
    'echo "$(pkill -f xctest)"',
    'echo "a $(echo "b $(killall xctest)")"',
    'x="$(cat <<\'EOF\'\nhi\nEOF\n)"; pkill -f xctest',
    # simulators
    "xcrun simctl shutdown all",
    "xcrun simctl erase all",
    "simctl shutdown all",
    "FOO=1 xcrun simctl shutdown all && echo ok",
]
ALLOWED = [
    "kill 12345",
    "kill -9 12345 12346",
    "kill %1",
    "kill $!",
    "kill -TERM $PID",
    "pkill -P 12345",
    "pkill -9 -P 12345",
    "pkill -TERM -P $$",
    "pkill -f '" + WT + "/build/run.py'",
    f"pkill -f {WT}/build/run.py",
    f'pkill -f "{WT}/a|{WT}/b"',
    f"pkill -9 -f {WT}/build",
    # the advice the message gives
    'pkill -f "$PWD/build/run.py"',
    "pkill -f ${PWD}/build/run.py",
    "pkill -f $CLAUDE_PROJECT_DIR/.claude/worktrees/agent-1/build",
    "pkill -f $(pwd)/build",
    "timeout 5 pkill -f $PWD/build",
    "for p in $(pgrep -f $PWD/build/x); do kill $p; done",
    f"pkill -f '^{WT}/build'",
    f"pkill -f .*{WT}/build",
    "ps aux | grep $PWD/build | awk '{print $2}' | xargs kill",
    "pgrep -fl xctest; kill 4567",
    "# don't pkill -f xctest here\necho ok",
    'echo "a # b"',
    "echo 'x' # pkill -f xctest",
    "echo a # killall xctest\nkill 123",
    "kill 123 # pkill -f xctest",
    "pkill -P 12 xctest",
    "pkill -P 10,11",
    "ps aux | grep \"$PWD/x\" | awk '{print $2}' | xargs kill",
    "grep -q error out.log && kill $PID",
    "until grep -q Listening log; do sleep 1; done; kill $SERVER_PID",
    "ps aux | grep $PWD/build | awk '{print $2}' | xargs kill",
    "ps -p 123 -o pid=; kill $PID",
    "find . -name x -exec echo {} ';'",
    "cat <<EOF > notes.txt\npkill -f xctest\nEOF",
    'cd apple && pkill -f /private/tmp/claude-501/x/y',
    "pgrep -fl xctest; kill -9 4567",
    "grep -r foo . ; kill 99",
    "xcrun simctl delete 8A1B2C3D",
    "pkill -f /private/tmp/claude-501/-Users-me/abc/scratchpad/server.py",
    "pkill -f /tmp/claude-501/x/y",
    f"sudo pkill -f {WT}/build/x",
    f"pkill -f {WT}/build/Debug-iphonesimulator/App.app",
    f"kill $(pgrep -f {WT}/build/x)",
    f"pgrep -f {WT}/build/x | xargs kill",
    "pgrep -P 123",
    "pgrep -f xctest",  # a lookup with no kill
    "xcrun simctl shutdown 8A1B2C3D",
    "xcrun simctl list",
    "ls killer.txt",
    "git commit -m 'no pkill here'",
    # heredoc markers and comments that really are what they look like
    "cat <<EOF > f\npkill -f xctest\nEOF\necho done",
    "cat <<-EOF > f\n\tpkill -f xctest\n\tEOF\necho done",
    "cat <<'EOF' > f\npkill -f xctest\nEOF",
    'cat <<"EOF" > f\npkill -f xctest\nEOF',
    'git commit -m "$(cat <<\'EOF\'\npkill -f xctest\nEOF\n)"',
    "echo `date` # pkill -f xctest",
    "echo `date #now`\nkill 123",
    "env -i kill 123",
    "env -iu FOO kill 123",
    # a quote inside a heredoc inside "$(...)" must not end the outer quote (it worked on main)
    'git commit -m "$(cat <<\'EOF\'\nGuard 5" screens\nkillall is now blocked by the hook\nEOF\n)"',
    'gh pr create --body "$(cat <<\'EOF\'\npkill -f xctest "x\nEOF\n)"',
    'echo "$(date)" && kill 123',
    "echo a \\\n  b",
    "cat <<'EOF' \\\n > f\npkill -f xctest\nEOF",
    # the override comment
    'pkill -f xctest  # kill-ok: my own stray test run, verified with ps',
    "killall Dock # kill-ok: restart the dock for the user",
]


def run_hook(command, tool="Bash", cwd=CWD, top=WT):
    err = io.StringIO()
    payload = json.dumps({"tool_name": tool, "tool_input": {"command": command}, "cwd": cwd})
    with mock.patch.dict(os.environ, {"CLAUDE_PROJECT_DIR": MAIN, "HOME": "/Users/me"}), \
            mock.patch.object(kill_guard, "find_toplevel", return_value=top), \
            mock.patch("sys.stdin", io.StringIO(payload)), redirect_stderr(err):
        code = kill_guard.main()
    return code, err.getvalue()


class KillGuardTests(unittest.TestCase):
    def test_blocked(self):
        for command in BLOCKED:
            with self.subTest(command=command):
                code, message = run_hook(command)
                self.assertEqual(code, 2, command)
                self.assertIn("kill-ok", message)

    def test_allowed(self):
        for command in ALLOWED:
            with self.subTest(command=command):
                self.assertEqual(run_hook(command)[0], 0, command)

    def test_main_checkout_does_not_scope_sibling_worktrees(self):
        code = run_hook(f"pkill -f {MAIN}/.claude/worktrees/agent-2/x", cwd=MAIN, top=MAIN)[0]
        self.assertEqual(code, 2)
        self.assertEqual(run_hook(f"pkill -f {MAIN}/build/x", cwd=MAIN, top=MAIN)[0], 0)

    def test_no_repo_falls_back_to_a_deep_cwd_only(self):
        with mock.patch.object(kill_guard, "find_toplevel", return_value=""):
            self.assertIsNone(kill_guard.reason(f"pkill -f {CWD}/x", CWD))
            self.assertIsNotNone(kill_guard.reason("pkill -f /Users/x/y", "/Users"))

    def test_find_toplevel_walks_up_to_dot_git(self):
        from tempfile import TemporaryDirectory
        with TemporaryDirectory() as tmp:
            (Path(tmp) / "a" / "b").mkdir(parents=True)
            (Path(tmp) / "a" / ".git").write_text("gitdir: x")
            self.assertEqual(kill_guard.find_toplevel(str(Path(tmp) / "a" / "b")), str(Path(tmp) / "a"))
            self.assertEqual(kill_guard.find_toplevel("/"), "")

    def test_tilde_expands_to_home(self):
        with mock.patch.dict(os.environ, {"HOME": WT}), mock.patch.object(kill_guard, "find_toplevel", return_value=WT):
            self.assertIsNone(kill_guard.reason("pkill -f ~/build/x", CWD))

    def test_large_command_checks_quickly(self):
        body = "\n".join(f"echo line {i} 'quoted text' | tee -a /tmp/x{i}" for i in range(3000))
        command = f"cat <<'EOF' > f\n{body}\nEOF\npkill -f xctest\n" + body
        start = time.perf_counter()
        code, _ = run_hook(command)
        self.assertEqual(code, 2)
        self.assertLess(time.perf_counter() - start, 0.5)  # loose; ~15 ms measured
        # the heredoc body is skipped, so a kill word inside it does not trigger
        quiet = "cat <<'EOF' > f\npkill -f xctest\nEOF\necho done"
        self.assertEqual(run_hook(quiet)[0], 0)

    def test_other_tools_and_bad_payloads_pass(self):
        self.assertEqual(run_hook("pkill -f xctest", tool="Edit")[0], 0)
        with mock.patch("sys.stdin", io.StringIO("not json")):
            self.assertEqual(kill_guard.main(), 0)

    def test_message_is_actionable(self):
        _, message = run_hook("pkill -f 'swift-test|xctest'")
        for needle in ("PID", "worktree", "kill-ok", "not scoped"):
            self.assertIn(needle, message)


if __name__ == "__main__":
    unittest.main()
