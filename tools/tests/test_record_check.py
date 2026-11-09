"""``tools/review/record.py`` posts the ``ai-review`` check run on the reviewed head (fake ``gh``, git and GitHub API)."""

import io
import json
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
sys.path.insert(0, str(TOOLS / "review"))
import gh_app_token  # noqa: E402
import record  # noqa: E402

HEAD = "a" * 40
PASS = {"verdict": "pass", "findings": [{"severity": "minor", "rule": "style", "file": "x.py", "detail": "nit", "fix": "tidy"}]}
MAJOR = {"severity": "major", "rule": "bug", "file": "y.py", "detail": "broken", "fix": "fix it"}
BLOCKER = {"severity": "blocker", "rule": "security", "detail": "leak"}


def outcome(verdict, rnd, findings, confirmation=None):
    data = {"verdict": verdict, "round": rnd, "findings": findings}
    if confirmation:
        data["round_confirmation"] = confirmation
    return record.check_outcome(data)[0]


class CheckOutcomeTests(unittest.TestCase):
    def test_table(self):
        """Fails if the rule is inverted or ``MAX_ROUNDS`` is not honoured."""
        self.assertEqual(outcome("pass", 1, []), "success")
        self.assertEqual(outcome("changes", 1, [MAJOR]), "failure")
        self.assertEqual(outcome("changes", 2, [MAJOR]), "success")
        self.assertEqual(outcome("changes", 2, [MAJOR, BLOCKER]), "failure")
        self.assertEqual(outcome("blocker", 1, [BLOCKER]), "failure")
        self.assertEqual(outcome("changes", 3, [MAJOR], "confirmation pass"), "success")


class CheckPayloadTests(unittest.TestCase):
    def test_payload_shape(self):
        """Fails if the name, head binding, summary cap or per-finding text is wrong."""
        findings = [MAJOR, BLOCKER, {"severity": "minor", "rule": "r", "detail": "d" * 70000}]
        payload = record.check_payload({"verdict": "blocker", "round": 1, "head": HEAD, "findings": findings})
        self.assertEqual((payload["name"], payload["head_sha"], payload["status"]), ("ai-review", HEAD, "completed"))
        self.assertEqual(payload["conclusion"], "failure")
        self.assertLessEqual(len(payload["output"]["summary"]), record.SUMMARY_MAX)
        small = record.check_payload({"verdict": "changes", "round": 2, "head": HEAD, "findings": [MAJOR, BLOCKER]})
        for f in (MAJOR, BLOCKER):
            self.assertIn(f["detail"], small["output"]["text"])
            self.assertIn(f["rule"], small["output"]["text"])
        self.assertIn("y.py", small["output"]["text"])
        self.assertTrue(small["completed_at"].endswith("Z"))


class MainTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.pr_head = HEAD
        self.posts = []
        self.api_error = None
        self.edits = 0

    def fake_run(self, argv, **kwargs):
        def done(text):
            return subprocess.CompletedProcess(argv, 0, stdout=text, stderr="")
        if argv[0] == "git":
            if "--abbrev-ref" in argv:
                return done("agents/topic\n")
            if "--show-toplevel" in argv:
                return done(str(self.root) + "\n")
            return done(HEAD + "\n")
        if argv[:3] == ["gh", "pr", "edit"]:
            self.edits += 1
            return done("")
        fields = argv[argv.index("--json") + 1]
        if fields == "headRefName":
            return done(json.dumps({"headRefName": "agents/topic"}))
        if fields == "body":
            return done(json.dumps({"body": "text"}))
        return done(json.dumps({"headRefOid": self.pr_head, "url": "https://github.com/SFenton/native-home/pull/7"}))

    def fake_api(self, method, path, bearer, payload=None, timeout=20):
        if self.api_error:
            raise self.api_error
        self.posts.append((method, path, bearer, payload))

    def run_main(self, *extra):
        verdict = self.root / "v.json"
        verdict.write_text(json.dumps(PASS))
        tokens = []

        def fake_token(role, timeout=20, scope="", extra=None):
            tokens.append((role, extra))
            return "tok-unused"
        err, out = io.StringIO(), io.StringIO()
        with mock.patch.object(record.subprocess, "run", self.fake_run), \
                mock.patch.object(record, "reviewer_identity", return_value={"agent_type": "reviewer", "session_id": "s", "agent_id": ""}), \
                mock.patch.object(gh_app_token, "api_request", self.fake_api), \
                mock.patch.object(gh_app_token, "token", fake_token), \
                redirect_stderr(err), redirect_stdout(out):
            rc = record.main([str(verdict), *extra])
        self.tokens = tokens
        return rc, err.getvalue()

    def review_file(self):
        return self.root / "build" / "review" / "agents__topic.json"

    def test_pr_posts_exactly_one_check_with_the_checks_permission(self):
        """Fails if the check is not posted once to repos/<owner>/<name>/check-runs with checks write added to the default permissions."""
        rc, _ = self.run_main("--pr", "7")
        self.assertEqual(rc, 0)
        self.assertEqual(len(self.posts), 1)
        method, path, _bearer, payload = self.posts[0]
        self.assertEqual((method, path), ("POST", "repos/SFenton/native-home/check-runs"))
        self.assertEqual((payload["name"], payload["head_sha"], payload["conclusion"]), ("ai-review", HEAD, "success"))
        self.assertEqual(self.tokens, [("reviewer", {"checks": "write"})])

    def test_without_pr_nothing_is_posted(self):
        """Fails if a lane-only or plain record posts a check."""
        rc, _ = self.run_main()
        self.assertEqual(rc, 0)
        self.assertEqual(self.posts, [])
        self.assertTrue(self.review_file().is_file())

    def test_api_error_exits_3_and_keeps_the_record(self):
        """Fails if a failed post loses the JSON, hides the NOT posted line or returns another code."""
        self.api_error = gh_app_token.AppError("GitHub answered 403")
        rc, err = self.run_main("--pr", "7")
        self.assertEqual(rc, 3)
        self.assertIn("ai-review check NOT posted", err)
        self.assertTrue(self.review_file().is_file())
        self.assertEqual(self.edits, 1)

    def test_a_moved_pr_head_exits_2_and_writes_nothing(self):
        """Fails if a check or file is written for a head that is not this checkout's HEAD."""
        self.pr_head = "b" * 40
        rc, err = self.run_main("--pr", "7")
        self.assertEqual(rc, 2)
        self.assertIn("is not this checkout's HEAD", err)
        self.assertFalse(self.review_file().exists())
        self.assertEqual(self.posts, [])


if __name__ == "__main__":
    unittest.main()
