"""``tools/agent_status.py``: the interactive session's status file."""

import io
import json
import sys
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import mock

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import agent_status  # noqa: E402


class AgentStatusTests(unittest.TestCase):
    def test_validate(self):
        self.assertEqual(agent_status.validate({"status": "done", "summary": "ok", "acceptance": {"a": "pass"}}), [])
        self.assertTrue(agent_status.validate({"status": "weird"}))
        self.assertTrue(agent_status.validate({"status": "done", "acceptance": {"a": "fail"}}))
        self.assertTrue(agent_status.validate({"status": "done", "summary": "w " * 251}))
        self.assertTrue(agent_status.validate([]))

    def test_write_status_sets_task_and_path(self):
        with TemporaryDirectory() as d:
            path = agent_status.write_status("T-1", {"status": "done"}, Path(d))
            self.assertEqual(path, Path(d) / "build" / "status" / "T-1.json")
            self.assertEqual(json.loads(path.read_text())["task"], "T-1")
        with self.assertRaises(ValueError):
            agent_status.write_status("../x", {}, Path("."))

    def test_cli_writes_from_json_and_file(self):
        with TemporaryDirectory() as d:
            root = Path(d)
            src = root / "in.json"
            src.write_text(json.dumps({"status": "blocked", "summary": "x"}))
            with mock.patch.object(agent_status, "ROOT", root):
                out = io.StringIO()
                with redirect_stdout(out):
                    self.assertEqual(agent_status.main(["write", "--task", "T-2", "--file", str(src)]), 0)
                self.assertTrue(Path(out.getvalue().strip()).exists())

    def test_cli_rejects_bad_input(self):
        with redirect_stderr(io.StringIO()):
            self.assertEqual(agent_status.main(["write", "--task", "T", "--json", "not json"]), 2)
            self.assertEqual(agent_status.main(["write", "--task", "T", "--json", '{"status": "x"}']), 1)


if __name__ == "__main__":
    unittest.main()
