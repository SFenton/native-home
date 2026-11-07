"""Usage report (``tools/token_report.py``) over synthetic transcripts."""

import io
import json
import sys
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from tempfile import TemporaryDirectory

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import token_report  # noqa: E402


def turn(mid, time, model, read, write=0, command=None, five_minute=True):
    block = [{"type": "tool_use", "name": "Bash", "input": {"command": command}}] if command else [{"type": "text", "text": "x"}]
    usage = {"input_tokens": 2, "cache_read_input_tokens": read, "cache_creation_input_tokens": write, "output_tokens": 10}
    if write:
        usage["cache_creation"] = {"ephemeral_5m_input_tokens": write if five_minute else 0,
                                   "ephemeral_1h_input_tokens": 0 if five_minute else write}
    return json.dumps({"type": "assistant", "timestamp": time, "uuid": mid,
                       "message": {"id": mid, "model": model, "usage": usage, "content": block}})


def write(path, lines):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n")


class TokenReportTests(unittest.TestCase):
    def test_weights_cache_tiers_and_models(self):
        usage = {"input_tokens": 0, "cache_read_input_tokens": 1000, "cache_creation_input_tokens": 100,
                 "cache_creation": {"ephemeral_5m_input_tokens": 100, "ephemeral_1h_input_tokens": 0}, "output_tokens": 10}
        self.assertEqual(token_report.weighted(usage, "claude-sonnet-5-5"), 100 + 125 + 50)
        self.assertEqual(token_report.weighted(usage, "claude-opus-5-5"), 5 * 275)
        self.assertEqual(token_report.weighted(usage, "<synthetic>"), 0)

    def test_report_flags_polls_rewrites_and_long_sessions(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            poll = "until grep -q done $L; do sleep 10; done"
            lines = [turn("m0", "2026-10-11T10:00:00Z", "claude-opus-5-5", 100_000)]
            # A poll, then ten idle minutes, then a turn that re-writes the whole context.
            lines.append(turn("m1", "2026-10-11T10:01:00Z", "claude-opus-5-5", 100_000, command=poll))
            lines.append(turn("m2", "2026-10-11T10:11:00Z", "claude-opus-5-5", 0, write=100_000))
            lines += [turn(f"x{i}", "2026-10-11T10:12:00Z", "claude-opus-5-5", 100_000) for i in range(210)]
            write(root / "-Users-x-Fenton-HASS-Native" / "aaaa1111.jsonl", lines)
            write(root / "-Users-x-Other" / "bbbb2222.jsonl", [turn("o", "2026-10-11T10:00:00Z", "claude-opus-5-5", 1)])
            text = token_report.report(token_report.find_sessions(root, "*Fenton-HASS-Native*", None))
            self.assertIn("2026-10-11  opus", text)
            self.assertIn("sessions over 200 turns: 1 of 1", text)
            self.assertIn("poll turns (sleep loops): 1", text)
            self.assertIn("re-wrote the whole cached context after a 5+ min gap: 1", text)
            self.assertNotIn("bbbb2222", text)

    def test_heredoc_bodies_are_not_polls(self):
        with TemporaryDirectory() as tmp:
            path = Path(tmp) / "p" / "s.jsonl"
            command = "python3 - <<'EOF'\nwhile x:\n    do = 1\n    sleep 60\nEOF"
            write(path, [turn("a", "2026-10-11T10:00:00Z", "claude-sonnet-5-5", 10, command=command)])
            self.assertFalse(token_report.Session(path).load().turns[0]["poll"])

    def test_since_filters_turns_and_cli(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            write(root / "Fenton-HASS-Native" / "s.jsonl", [turn("a", "2026-10-01T10:00:00Z", "claude-opus-5-5", 10),
                                                            turn("b", "2026-10-12T10:00:00Z", "claude-haiku-5-5", 10)])
            buffer = io.StringIO()
            with redirect_stdout(buffer):
                self.assertEqual(token_report.main(["--root", str(root), "--since", "2026-10-10"]), 0)
            self.assertIn("2026-10-12  haiku", buffer.getvalue())
            self.assertNotIn("2026-10-01", buffer.getvalue())
            self.assertEqual(token_report.main(["--root", str(root), "--projects", "nope*"]), 1)


if __name__ == "__main__":
    unittest.main()
