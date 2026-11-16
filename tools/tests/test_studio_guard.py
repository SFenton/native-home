"""Role and file-tool tests for tools/hooks/studio_guard.py, the only protection for the Studio draft and port 4801.

The guard table (``guard_tables/studio_guard.tsv``) replays a coder; these cover the roles the table cannot name. The Studio CLI itself is
tested in the Studio repo (``tests/studio-publish.test.ts``).
"""
import io
import json
import sys
import unittest
from contextlib import redirect_stderr
from pathlib import Path
from unittest import mock

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
sys.path.insert(0, str(TOOLS / "hooks"))
sys.path.insert(0, str(TOOLS / "tests"))
import studio_guard  # noqa: E402
from test_guard_tables import studio_fixtures  # noqa: E402

STUDIO, NOTSTUDIO = studio_fixtures()
TSX = f"{STUDIO}/node_modules/.bin/tsx {STUDIO}/scripts/studio-publish.ts"
BASE_ENV = {"PATH": "/usr/bin:/bin", "HOME": "/nonexistent"}


class GuardRoleTests(unittest.TestCase):
    """The table replays a coder; these cover the roles the table cannot name."""

    def verdict(self, command, agent_type=None, headless=False, cwd=None):
        payload = {"tool_name": "Bash", "tool_input": {"command": command}, "cwd": cwd or str(TOOLS.parent)}
        if agent_type:
            payload["agent_type"] = agent_type
        env = dict(BASE_ENV)
        if headless:
            env["FENTON_HEADLESS"] = "1"
        with mock.patch.dict("os.environ", env, clear=True), mock.patch.object(sys, "stdin", io.StringIO(json.dumps(payload))), \
                redirect_stderr(io.StringIO()):
            return studio_guard.main([])

    def test_publisher_roles(self):
        """Fails if: the orchestrator or menial cannot run apply, or a reviewer, researcher or headless session can."""
        command = f"{TSX} apply build/studio-publish/c1 --reason x"
        for role in ("orchestrator", "menial"):
            self.assertEqual(self.verdict(command, role), 0, role)
        for role in ("coder", "reviewer", "researcher", "verifier", "steward", "designer"):
            self.assertEqual(self.verdict(command, role), 2, role)
        self.assertEqual(self.verdict(command, "orchestrator", headless=True), 2)

    def test_npm_form_roles(self):
        """Fails if: the npm form skips the role gate, or works outside a Studio checkout."""
        command = "npm run studio:publish -- resolve c --reason x"
        self.assertEqual(self.verdict(command, "menial", cwd=STUDIO), 0)
        self.assertEqual(self.verdict(command, "coder", cwd=STUDIO), 2)
        self.assertEqual(self.verdict(command, "menial", cwd=NOTSTUDIO), 2)
        self.assertEqual(self.verdict(command, "menial"), 2)

    def test_role_gate_cannot_be_bypassed_by_other_forms(self):
        """Fails if: any form other than the exact exempt one runs for the orchestrator, or a global option hides a mutating subcommand."""
        for command in ("python3 tools/studio_publish.py apply c --reason x", "python3 -m tools.studio_publish apply c --reason x",
                        f"{STUDIO}/node_modules/.bin/tsx {STUDIO}/scripts/../scripts/studio-publish.ts apply c --reason x",
                        f"{STUDIO}/node_modules/.bin/tsx {NOTSTUDIO}/scripts/studio-publish.ts apply c --reason x",
                        f"{NOTSTUDIO}/node_modules/.bin/tsx {NOTSTUDIO}/scripts/studio-publish.ts apply c --reason x",
                        f"npx tsx {STUDIO}/scripts/studio-publish.ts apply c --reason x"):
            self.assertEqual(self.verdict(command, "orchestrator"), 2, command)
        self.assertEqual(self.verdict(f"{TSX} --log x.jsonl apply c --reason x", "orchestrator"), 0)
        self.assertEqual(self.verdict(f"{TSX} --log x.jsonl status apply c --reason x", "coder"), 2)
        self.assertEqual(self.verdict(f"{TSX} --log x.jsonl status", "coder"), 0)

    def test_file_tools(self):
        """Fails if: a file tool reaches native-v2 or the studio lock, or an ordinary path is blocked."""
        for path, want in (("/x/studio/native-v2/state.json", 2), ("/x/studio/.studio.lock", 2), ("/x/repo/docs/a.md", 0)):
            payload = {"tool_name": "Write", "tool_input": {"file_path": path, "content": "x"}, "agent_type": "coder", "cwd": "/x"}
            with mock.patch.dict("os.environ", BASE_ENV, clear=True), mock.patch.object(sys, "stdin", io.StringIO(json.dumps(payload))), \
                    redirect_stderr(io.StringIO()):
                self.assertEqual(studio_guard.main([]), want, path)


if __name__ == "__main__":
    unittest.main()
