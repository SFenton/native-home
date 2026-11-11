"""``tools/hooks/tier_guard.py``: no unfiltered journey run or full coverage outside the nightly and release tiers."""

import io
import json
import os
import sys
import unittest
from contextlib import redirect_stderr
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "hooks"))
import tier_guard  # noqa: E402

BODY = "tools/ios_uitest.sh"
BLOCKED = [
    "tools/ios_uitest.sh",
    "tools/ios_uitest.sh --only iphone",
    "./tools/ios_uitest.sh --env shell --only duo --force",
    "tools/bg_run.py uitest-iphone -- tools/ios_uitest.sh --only iphone",
    "python3 tools/bg_run.py uitest -- tools/ios_uitest.sh",
    "FENTON_DEVCAP_HOLD=7200 tools/ios_uitest.sh --only ipad",
    "cd apple && ../tools/ios_uitest.sh",
    "bash -c 'tools/ios_uitest.sh --only iphone'",
    "tools/ios_uitest.sh --plan Gate",
    "tools/ios_uitest.sh --full",
    "tools/apple_coverage.sh",
    "tools/bg_run.py cov -- tools/apple_coverage.sh --full",
    "nohup tools/apple_coverage.sh > out.log 2>&1 &",
]
ALLOWED = [
    "tools/ios_uitest.sh --changed",
    "tools/ios_uitest.sh --only duo --changed",
    "tools/ios_uitest.sh --only ipad -only-testing:FentonHomeUITests/ChoresSwipeJourneyTests",
    "tools/ios_uitest.sh -only-testing:FentonHomeUITests/A/testB",
    "tools/ios_uitest.sh --only duo --plan Smoke",
    "tools/ios_uitest.sh --plan=Perf",
    "tools/bg_run.py uitest -- tools/ios_uitest.sh --changed --only iphone",
    "tools/apple_coverage.sh --changed",
    "tools/bg_run.py cov -- tools/apple_coverage.sh --changed",
    "FENTON_TIER=nightly tools/ios_uitest.sh --only iphone",
    "FENTON_TIER=release tools/apple_coverage.sh",
    "tools/ios_uitest.sh --full  # full-ok: release candidate sign-off",
    "tools/ios_uitest.sh --help",
    "grep -n changed tools/ios_uitest.sh",
    "cat tools/apple_coverage.sh | head",
    "git add tools/ios_uitest.sh",
    "bash -n tools/ios_uitest.sh",
    "swift test --filter Foo",
    "echo hello",
    "FENTON_HOSTED_FILTER=UKHostedTests tools/bg_run.py hosted -- tools/ios_uitest.sh --hosted",
]
# A heredoc body that is only text, written to a file by a command that runs nothing.
ALLOWED_PLAIN_WRITES = [
    f"cat > f <<'EOF'\n{BODY}\nEOF\n",
    "cat > f <<'EOF'\ntools/apple_coverage.sh\nEOF\n",
    f"cat <<'EOF' > f\n{BODY}\nEOF\n",
    f"cat >> f <<EOF\n{BODY}\nEOF\n",
    f"cat <<EOF >f\n{BODY}\nEOF\n",
    f"tee f <<EOF\n{BODY}\nEOF\n",
    f"tee -a f <<'EOF' >> g\n{BODY}\nEOF\n",
    f"cat > a <<EOF\n{BODY}\nEOF\ncat > b <<EOF\ntools/apple_coverage.sh\nEOF\n",
]
ALLOWED_HOSTED_FORMS = [
    "FENTON_HOSTED_FILTER=A tools/ios_uitest.sh --hosted",
    "FENTON_HOSTED_FILTER='A B' tools/ios_uitest.sh --hosted",
    'FENTON_HOSTED_FILTER="A" tools/ios_uitest.sh --hosted',
    "env FENTON_HOSTED_FILTER=A tools/ios_uitest.sh --hosted",
    "export FENTON_HOSTED_FILTER=A\ntools/ios_uitest.sh --hosted",
    "export FENTON_HOSTED_FILTER=A; tools/bg_run.py hosted -- tools/ios_uitest.sh --hosted",
    "export FENTON_HOSTED_FILTER=A && tools/ios_uitest.sh --hosted",
]
# Each was blocked before heredoc bodies were skipped and must stay blocked.
BLOCKED_HEREDOC_BYPASSES = [
    f"bash <<EOF\n{BODY}\nEOF\n",
    f"nohup {BODY} > out.log 2>&1 <<EOF\nnote\nEOF\n",
    "cat > f <<'EOF'\nx\nEOF\ntools/apple_coverage.sh",
    f'bash -c "$(cat <<EOF\n{BODY}\nEOF\n)"',
    f'eval "$(cat <<EOF\n{BODY}\nEOF\n)"',
    f"cat <<EOF |\n{BODY}\nEOF\nbash",
    f"cat <<EOF | bash\n{BODY}\nEOF\n",
    f"cat <<EOF \\\n| bash\n{BODY}\nEOF\n",
    f"source /dev/stdin <<EOF\n{BODY}\nEOF\n",
    f". /dev/stdin <<EOF\n{BODY}\nEOF\n",
    f"python3 - <<EOF\nimport os; os.system('{BODY}')\nEOF\n",
    f"xargs env <<EOF\n{BODY}\nEOF\n",
    f"cat > run.sh <<EOF\n{BODY}\nEOF\nbash run.sh",
    f"cat > run.sh <<EOF\n{BODY}\nEOF\n. ./run.sh",
    f"cat > run.sh <<EOF && bash run.sh\n{BODY}\nEOF\n",
    f"cat > run.sh <<EOF; bash run.sh\n{BODY}\nEOF\n",
    f"cat > /dev/stdout <<EOF\n{BODY}\nEOF\n",
    f"tee run.sh <<EOF | bash\n{BODY}\nEOF\n",
    f"cat <<EOF\n{BODY}\nEOF\n",
    f"cat <<EOF > >(bash)\n{BODY}\nEOF\n",
]
# Each is an empty, expanded or misplaced filter and must not count.
BLOCKED_HOSTED_SPOOFS = [
    "FENTON_HOSTED_FILTER= tools/ios_uitest.sh --hosted",
    "FENTON_HOSTED_FILTER='' tools/ios_uitest.sh --hosted",
    "FENTON_HOSTED_FILTER=' ' tools/ios_uitest.sh --hosted",
    'FENTON_HOSTED_FILTER="  " tools/ios_uitest.sh --hosted',
    "FENTON_HOSTED_FILTER=$EMPTY tools/ios_uitest.sh --hosted",
    'FENTON_HOSTED_FILTER="$EMPTY" tools/ios_uitest.sh --hosted',
    "FENTON_HOSTED_FILTER=`true` tools/ios_uitest.sh --hosted",
    "tools/ios_uitest.sh --hosted # FENTON_HOSTED_FILTER=A",
    "# FENTON_HOSTED_FILTER=A\ntools/ios_uitest.sh --hosted",
    "true # note; export FENTON_HOSTED_FILTER=A\ntools/ios_uitest.sh --hosted",
    "echo FENTON_HOSTED_FILTER=A; tools/ios_uitest.sh --hosted",
    "echo 'export FENTON_HOSTED_FILTER=A'; tools/ios_uitest.sh --hosted",
    "FENTON_HOSTED_FILTER=A true; tools/ios_uitest.sh --hosted",
    "FENTON_HOSTED_FILTER=A true && tools/ios_uitest.sh --hosted",
    "FENTON_HOSTED_FILTER=A tools/ios_uitest.sh --only iphone",
    "tools/bg_run.py FENTON_HOSTED_FILTER=A -- tools/ios_uitest.sh --hosted",
    "export FENTON_HOSTED_FILTER=A; unset FENTON_HOSTED_FILTER; tools/ios_uitest.sh --hosted",
    "export FENTON_HOSTED_FILTER=; tools/ios_uitest.sh --hosted",
    "export FENTON_HOSTED_FILTER=' '; tools/ios_uitest.sh --hosted",
    "(export FENTON_HOSTED_FILTER=A); tools/ios_uitest.sh --hosted",
    "tools/ios_uitest.sh --hosted; export FENTON_HOSTED_FILTER=A",
    f"cat <<EOF\nexport FENTON_HOSTED_FILTER=A\nEOF\n{BODY} --hosted",
]


def run(command, tool="Bash"):
    err = io.StringIO()
    payload = json.dumps({"tool_name": tool, "tool_input": {"command": command}})
    with mock.patch.object(sys, "stdin", io.StringIO(payload)), redirect_stderr(err), \
            mock.patch.dict(os.environ, {}, clear=False):
        os.environ.pop("FENTON_TIER", None)
        status = tier_guard.main()
    return status, err.getvalue()


class TierGuardTests(unittest.TestCase):
    def test_blocks_unfiltered_runs(self):
        for command in BLOCKED:
            with self.subTest(command=command):
                status, message = run(command)
                self.assertEqual(status, 2, message)
                self.assertIn("--changed", message)
                self.assertIn("nightly", message)

    def test_still_blocks_heredoc_bodies_that_could_reach_a_shell(self):
        for command in BLOCKED_HEREDOC_BYPASSES:
            with self.subTest(command=command):
                self.assertEqual(run(command)[0], 2)

    def test_blocks_empty_and_spoofed_hosted_filters(self):
        for command in BLOCKED_HOSTED_SPOOFS:
            with self.subTest(command=command):
                self.assertEqual(run(command)[0], 2)

    def test_allows_plain_heredoc_writes_to_files(self):
        for command in ALLOWED_PLAIN_WRITES:
            with self.subTest(command=command):
                self.assertEqual(run(command)[0], 0)

    def test_allows_valid_hosted_filter_forms(self):
        for command in ALLOWED_HOSTED_FORMS:
            with self.subTest(command=command):
                self.assertEqual(run(command)[0], 0)

    def test_allows_filtered_nightly_and_overridden_runs(self):
        for command in ALLOWED:
            with self.subTest(command=command):
                self.assertEqual(run(command)[0], 0)

    def test_full_without_a_reason_is_refused(self):
        self.assertEqual(run("tools/ios_uitest.sh --full # full-ok:")[0], 2)

    def test_the_environment_tier_lifts_the_block(self):
        payload = json.dumps({"tool_name": "Bash", "tool_input": {"command": "tools/ios_uitest.sh"}})
        with mock.patch.object(sys, "stdin", io.StringIO(payload)), mock.patch.dict(os.environ, {"FENTON_TIER": "nightly"}):
            self.assertEqual(tier_guard.main(), 0)

    def test_message_names_the_alternative_for_coverage(self):
        self.assertIn("apple_coverage.sh --changed", run("tools/apple_coverage.sh")[1])

    def test_ignores_other_tools_and_bad_input(self):
        self.assertEqual(run("tools/ios_uitest.sh", tool="Read")[0], 0)
        with mock.patch.object(sys, "stdin", io.StringIO("not json")):
            self.assertEqual(tier_guard.main(), 0)


class SettingsTests(unittest.TestCase):
    def test_the_hook_is_registered_for_bash(self):
        settings = json.loads((Path(__file__).resolve().parents[2] / ".claude" / "settings.json").read_text())
        commands = [h["command"] for g in settings["hooks"]["PreToolUse"] if g["matcher"] == "Bash" for h in g["hooks"]]
        self.assertTrue(any("tier_guard.py" in c for c in commands))


if __name__ == "__main__":
    unittest.main()
