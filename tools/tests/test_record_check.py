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
        self.assertLessEqual(len(payload["output"]["text"]), record.SUMMARY_MAX)
        self.assertGreater(len(payload["output"]["text"]), record.SUMMARY_MAX - 1)  # the oversized finding was cut, not dropped
        small = record.check_payload({"verdict": "changes", "round": 2, "head": HEAD, "findings": [MAJOR, BLOCKER]})
        for f in (MAJOR, BLOCKER):
            self.assertIn(f["detail"], small["output"]["text"])
            self.assertIn(f["rule"], small["output"]["text"])
        self.assertIn("y.py", small["output"]["text"])
        self.assertTrue(small["completed_at"].endswith("Z"))


class PostCheckTests(unittest.TestCase):
    """``record.py --post-check SHA --repo R`` (what ``ship.sh`` runs after a push), with a temp verdict store and fake API."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.store = Path(self.tmp.name)
        self.posts = []
        self.tokens = []
        self.api_error = None

    def verdict(self, sha=HEAD, **over):
        data = {"verdict": "pass", "round": 1, "head": sha, "findings": PASS["findings"],
                "reviewer": {"agent_type": "reviewer", "session_id": "s", "agent_id": ""}}
        data.update(over)
        (self.store / f"agents__topic-{sha[:12]}.json").write_text(json.dumps(data))

    def post(self, sha=HEAD):
        def api(method, path, bearer, payload=None, timeout=20):
            if self.api_error:
                raise self.api_error
            self.posts.append((method, path, bearer, payload))

        def token(role, timeout=20, extra=None):
            self.tokens.append((role, extra))
            return "tok-unused"
        err, out = io.StringIO(), io.StringIO()
        with mock.patch.object(gh_app_token, "api_request", api), mock.patch.object(gh_app_token, "token", token), \
                redirect_stderr(err), redirect_stdout(out):
            rc = record.post_check_for(sha, "SFenton/native-home", self.store)
        return rc, err.getvalue() + out.getvalue()

    def test_a_pass_verdict_posts_one_success_for_the_pushed_sha(self):
        """Fails if the check is not one POST to repos/<owner>/<name>/check-runs, for exactly the pushed sha, with checks write added."""
        self.verdict()
        rc, _ = self.post()
        self.assertEqual(rc, 0)
        self.assertEqual(len(self.posts), 1)
        method, path, bearer, payload = self.posts[0]
        self.assertEqual((method, path, bearer), ("POST", "repos/SFenton/native-home/check-runs", "tok-unused"))
        self.assertEqual((payload["name"], payload["head_sha"], payload["conclusion"]), ("ai-review", HEAD, "success"))
        self.assertEqual(self.tokens, [("reviewer", {"checks": "write"})])

    def test_no_verdict_posts_nothing(self):
        """Fails if a check is posted for a sha with no recorded verdict (or one for another sha)."""
        self.verdict(sha="c" * 40)
        rc, out = self.post()
        self.assertEqual(rc, 3)
        self.assertEqual(self.posts, [])
        self.assertIn("ai-review check NOT posted", out)

    def test_a_verdict_without_a_reviewer_identity_posts_nothing(self):
        """Fails if an unattributed record, or one whose identity is not agent_type reviewer with a session id, can produce a check."""
        for reviewer in (None, {"agent_type": "coder", "session_id": "s"}, {"agent_type": "reviewer", "session_id": ""}, "reviewer"):
            self.verdict(reviewer=reviewer)
            rc, _ = self.post()
            self.assertEqual((rc, self.posts), (3, []), reviewer)

    def test_a_changes_verdict_posts_nothing_even_at_round_two(self):
        """Fails if the server check is greener than the push gate: ``changes`` at round 2 passes check_outcome but not review_verdict.has_pass."""
        self.verdict(verdict="changes", round=2, findings=[MAJOR])
        rc, out = self.post()
        self.assertEqual((rc, self.posts), (3, []))
        self.assertIn("ai-review check NOT posted", out)

    def test_a_record_whose_head_is_another_sha_posts_nothing(self):
        """Fails if the sha check is dropped: a file named for the pushed sha whose recorded head differs must not count."""
        self.verdict(sha=HEAD, head="d" * 40)
        rc, _ = self.post()
        self.assertEqual((rc, self.posts), (3, []))

    def test_a_malformed_record_prints_not_posted_and_exits_3(self):
        """Fails if a malformed record raises a traceback instead of the NOT posted line and exit 3."""
        (self.store / f"agents__topic-{HEAD[:12]}.json").write_text("{not json")
        rc, out = self.post()
        self.assertEqual((rc, self.posts), (3, []))
        self.assertIn("ai-review check NOT posted", out)
        self.verdict(findings=[{"severity": "minor", "detail": "no rule key"}])  # passes the gate's shape rule, breaks the payload
        rc, out = self.post()
        self.assertEqual((rc, self.posts), (3, []))
        self.assertIn("ai-review check NOT posted: unusable verdict record", out)

    def test_api_error_prints_the_message_and_never_the_token(self):
        """Fails if an AppError escapes, the NOT posted line is missing, or a token appears in the output."""
        self.verdict()
        self.api_error = gh_app_token.AppError("GitHub answered 403")
        rc, out = self.post()
        self.assertEqual(rc, 3)
        self.assertIn("ai-review check NOT posted: GitHub answered 403", out)
        self.assertNotIn("tok-unused", out)

    def test_cli_needs_repo(self):
        """Fails if --post-check without --repo posts or crashes."""
        self.assertEqual(record.main(["--post-check", HEAD]), 2)


class ShipWiringTests(unittest.TestCase):
    def test_ship_posts_the_check_after_the_push_and_never_fails_on_it(self):
        """Fails if ship.sh posts before the push, skips the native-home guard, or lets a failed post fail the push."""
        lines = (TOOLS / "ship.sh").read_text().splitlines()
        # The push is one command for plain and --update ships ("${PUSH_ARGS[@]}" holds -q -u and, for --update, the lease), so match it by shape.
        push = next(i for i, line in enumerate(lines) if line.startswith('git push "${PUSH_ARGS[@]}" origin'))
        call = next(i for i, line in enumerate(lines) if "--post-check" in line and not line.lstrip().startswith("#"))
        self.assertGreater(call, push)
        self.assertTrue(lines[call].rstrip().endswith("|| true"))
        self.assertIn("native-home", lines[call - 1])
        self.assertIn("--repo SFenton/native-home", lines[call])



if __name__ == "__main__":
    unittest.main()
