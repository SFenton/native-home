"""Tests for tools/studio_publish.py against an in-process stub Studio (loopback, ephemeral port) that mimics the compare-and-set routes.

The opt-in contract test runs the real Studio only on a scratch port above 4815 (never 4800, 4801, 4819 or 4880) and is skipped
unless ``STUDIO_CHECKOUT`` and ``STUDIO_CONTRACT_PORT`` are set.
"""
import builtins
import hashlib
import io
import json
import os
import sys
import tempfile
import threading
import unittest
from contextlib import redirect_stderr, redirect_stdout
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from unittest import mock

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
sys.path.insert(0, str(TOOLS / "hooks"))
import studio_publish as sp  # noqa: E402
import studio_guard  # noqa: E402

TOKEN = "stub-token-SECRET-0123456789abcdefABCDEF"
SENTINEL = "SENTINEL-house-value-9917"


def sha(doc):
    return hashlib.sha256(json.dumps(doc, sort_keys=True).encode()).hexdigest()


class StubStudio:
    """The Studio's draft, publication and Home Assistant history, behind the five routes the tool uses."""

    def __init__(self, document, token=None):
        self.draft = {"revision": 5, "publisherId": "pub-1", "document": document}
        self.live_doc = json.loads(json.dumps(document))
        self.history = {1: {"revision": 1, "doc": self.live_doc, "envelopeSha256": sha(self.live_doc)}}
        self.live_rev = 1
        self.token = token
        self.calls = []
        self.fail_publish = 0
        self.age_out = False
        self.throttle = 0
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), self._handler())
        self.port = self.server.server_address[1]
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def close(self):
        self.server.shutdown()
        self.server.server_close()

    @property
    def base(self):
        return f"http://127.0.0.1:{self.port}"

    def owner_saves(self, document):
        self.draft = {**self.draft, "revision": self.draft["revision"] + 1, "document": document}

    def _publication(self):
        current = self.history[self.live_rev]
        return {"current": {"revision": current["revision"], "envelopeSha256": current["envelopeSha256"]},
                "history": [{"revision": r} for r in self.history], "draftIsLive": self.draft["document"] == self.live_doc}

    def _handler(self):
        stub = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def reply(self, status, body=None):
                raw = json.dumps(body if body is not None else {}).encode()
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(raw)))
                self.end_headers()
                self.wfile.write(raw)

            def route(self, method):
                path = self.path
                length = int(self.headers.get("Content-Length") or 0)
                body = json.loads(self.rfile.read(length)) if length else None
                stub.calls.append((method, path, self.headers.get("Authorization"), body))
                if stub.token and self.headers.get("Authorization") != "Bearer " + stub.token:
                    return self.reply(401)
                if stub.throttle > 0:
                    stub.throttle -= 1
                    return self.reply(429)
                d = stub.draft
                if (method, path) == ("GET", "/native/api/draft"):
                    return self.reply(200, d)
                if (method, path) == ("PUT", "/native/api/draft"):
                    if body["expectedRevision"] != d["revision"]:
                        return self.reply(409, {"currentRevision": d["revision"]})
                    if body["document"].get("reject"):
                        return self.reply(422, {"error": "invalid"})
                    stub.draft = {**d, "revision": d["revision"] + 1, "document": body["document"]}
                    return self.reply(200, stub.draft)
                if (method, path) == ("GET", "/native/api/ha/open-check"):
                    return self.reply(200, {"action": "start" if d["document"] == stub.live_doc else "ask"})
                if (method, path) == ("GET", "/native/api/ha/publication"):
                    return self.reply(200, stub._publication())
                if (method, path) == ("POST", "/native/api/validate"):
                    return self.reply(200, {"valid": not body["document"].get("invalid"), "capabilities": []})
                if (method, path) == ("POST", "/native/api/ha/publish"):
                    if stub.fail_publish:
                        stub.fail_publish -= 1
                        return self.reply(502)
                    if body["expectedRevision"] != d["revision"]:
                        return self.reply(409, {"currentRevision": d["revision"]})
                    stub.live_rev += 1
                    stub.live_doc = json.loads(json.dumps(d["document"]))
                    stub.history[stub.live_rev] = {"revision": stub.live_rev, "doc": stub.live_doc, "envelopeSha256": sha(stub.live_doc)}
                    return self.reply(200, {"epoch": 1, "revision": stub.live_rev, "envelopeSha256": sha(stub.live_doc)})
                if (method, path) == ("POST", "/native/api/ha/rollback"):
                    entry = stub.history.get(body["revision"])
                    if entry is None or stub.age_out:
                        return self.reply(404)
                    stub.live_rev += 1
                    stub.live_doc = json.loads(json.dumps(entry["doc"]))
                    stub.history[stub.live_rev] = {"revision": stub.live_rev, "doc": stub.live_doc, "envelopeSha256": entry["envelopeSha256"]}
                    return self.reply(200, {"revision": stub.live_rev})
                return self.reply(404)

            def do_GET(self):
                self.route("GET")

            def do_PUT(self):
                self.route("PUT")

            def do_POST(self):
                self.route("POST")

        return Handler


BASE_DOC = {"id": "doc-1", "title": "Home", "tiles": [{"id": "t1", "label": "Lamp"}], "other": {"keep": 1}}


def candidate():
    doc = json.loads(json.dumps(BASE_DOC))
    doc["tiles"][0]["label"] = SENTINEL
    return doc


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.log = self.root / "log.jsonl"
        self.stub = StubStudio(json.loads(json.dumps(BASE_DOC)))
        self.addCleanup(self.stub.close)
        self.addCleanup(self.tmp.cleanup)
        self.dir = self.root / "build" / "studio-publish" / "c1"
        self.dir.mkdir(parents=True)
        (self.root / "shots").mkdir()
        for name in ("before.png", "after.png"):
            (self.root / "shots" / name).write_bytes(b"png")
        self.write_bundle()

    def write_bundle(self, doc=None, scope=("/tiles/0/label",), revision=5, evidence_for=None):
        doc = doc if doc is not None else candidate()
        change = {"id": "c1", "task": "templates", "studio": {"publisherId": "pub-1", "documentId": "doc-1"},
                  "base": {"draftRevision": revision, "document": BASE_DOC, "liveRevision": 1, "liveEnvelopeSha256": sha(BASE_DOC)},
                  "document": doc, "scope": list(scope), "summary": "label"}
        (self.dir / "change.json").write_text(json.dumps(change))
        evidence = {"candidateSha256": sp.doc_sha256(evidence_for if evidence_for is not None else doc), "validation": {"result": "pass"},
                    "screenshots": {"before": ["shots/before.png"], "after": ["shots/after.png"]}, "checks": [{"id": "pair", "result": "pass"}]}
        (self.dir / "evidence.json").write_text(json.dumps(evidence))

    def run_cli(self, *args, env=None, base=True):
        argv = ["--log", str(self.log), *args]
        if base:
            argv += ["--base", self.stub.base]
        out, err = io.StringIO(), io.StringIO()
        full_env = {"HOME": str(self.root), **(env or {})}
        with redirect_stdout(out), redirect_stderr(err):
            code = sp.main(argv, root=self.root, env=full_env, sleep=lambda s: None)
        self.output = out.getvalue() + err.getvalue()
        return code

    def record(self):
        return json.loads((self.dir / "record.json").read_text())

    def log_text(self):
        return self.log.read_text() if self.log.exists() else ""


class FlowTests(Base):
    def test_happy_path_check_apply_publish_and_log(self):
        """Fails if: the check, apply and publish do not move the draft and the live revision by one each, or a mode other than 600 holds the prior copy."""
        self.assertEqual(self.run_cli("check", str(self.dir)), 0)
        self.assertEqual(self.run_cli("apply", str(self.dir), "--reason", "t", "--publish"), 0, self.output)
        self.assertEqual(self.stub.draft["revision"], 6)
        self.assertEqual(self.stub.live_rev, 2)
        self.assertEqual(self.record()["state"], "published")
        self.assertEqual(oct((self.dir / "prior.json").stat().st_mode & 0o777), "0o600")
        self.assertEqual(json.loads((self.dir / "prior.json").read_text())["document"], BASE_DOC)
        self.assertIn('"result": "published"', self.log_text())

    def test_check_reads_open_check_first(self):
        """Fails if: the first request is not open-check (the scope guard must come before anything else)."""
        self.run_cli("check", str(self.dir))
        self.assertEqual(self.stub.calls[0][1], "/native/api/ha/open-check")

    def test_409_on_put_stops_with_stale_base_and_no_retry(self):
        """Fails if: a 409 on the draft write is retried, the draft changes, or the exit code is not 3."""
        orig = self.stub.draft

        def moved(*_a):
            self.stub.owner_saves(BASE_DOC)  # the owner saves between the check and the write
        real = sp.Publisher.read_state

        def read_then_move(inner):
            state = real(inner)
            moved()
            return state
        with mock.patch.object(sp.Publisher, "read_state", read_then_move):
            code = self.run_cli("apply", str(self.dir), "--reason", "t")
        self.assertEqual(code, 3, self.output)
        self.assertIn("stale_base", self.output)
        self.assertEqual(sum(1 for c in self.stub.calls if c[0] == "PUT"), 1)
        self.assertEqual(self.stub.draft["revision"], orig["revision"] + 1)
        self.assertEqual(self.stub.draft["document"], BASE_DOC)
        self.assertEqual(self.record()["state"], "refused")

    def test_stale_base_at_check_and_rebase_identical(self):
        """Fails if: a moved revision passes without the flag, or a moved revision with an equal document is refused with the flag."""
        self.stub.owner_saves(BASE_DOC)
        self.assertEqual(self.run_cli("check", str(self.dir)), 3)
        self.assertEqual(self.run_cli("apply", str(self.dir), "--reason", "t", "--rebase-identical"), 0, self.output)
        self.assertEqual(self.stub.draft["revision"], 7)

    def test_422_leaves_draft_untouched(self):
        """Fails if: a rejected write is reported as applied or changes the draft."""
        doc = candidate()
        doc["reject"] = True
        self.write_bundle(doc=doc, scope=("/tiles/0/label", "/reject"))
        self.assertEqual(self.run_cli("apply", str(self.dir), "--reason", "t"), 1)
        self.assertIn("rejected", self.output)
        self.assertEqual(self.stub.draft["document"], BASE_DOC)

    def test_invalid_candidate_refused_by_validate(self):
        """Fails if: a candidate the Studio's validate refuses reaches the draft."""
        doc = candidate()
        doc["invalid"] = True
        self.write_bundle(doc=doc, scope=("/tiles/0/label", "/invalid"))
        self.assertEqual(self.run_cli("apply", str(self.dir), "--reason", "t"), 1)
        self.assertIn("invalid", self.output)
        self.assertEqual(self.stub.draft["revision"], 5)

    def test_not_live_refusal_writes_nothing(self):
        """Fails if: the tool writes or publishes while the owner has unpublished edits (the draft is not what the app serves)."""
        edited = json.loads(json.dumps(BASE_DOC))
        edited["other"]["keep"] = 2
        self.stub.owner_saves(edited)
        code = self.run_cli("apply", str(self.dir), "--reason", "t", "--publish")
        self.assertEqual(code, 3)
        self.assertIn("owner_edits", self.output)
        self.assertFalse([c for c in self.stub.calls if c[0] in ("PUT",) or c[1].endswith("/ha/publish")])

    def test_owner_saves_between_apply_and_publish(self):
        """Fails if: publish ships a draft the owner edited after the apply, or alters that draft."""
        self.assertEqual(self.run_cli("apply", str(self.dir), "--reason", "t"), 0)
        self.stub.owner_saves({**candidate(), "extra": 1})
        self.assertEqual(self.run_cli("publish", str(self.dir), "--reason", "t"), 3)
        self.assertEqual(self.stub.live_rev, 1)
        self.assertEqual(self.stub.draft["document"]["extra"], 1)

    def test_wrong_studio_and_bad_base(self):
        """Fails if: a different publisherId passes, or a non-loopback, a port 4800 or a 4819 base is accepted without the bundle naming it."""
        self.stub.draft["publisherId"] = "someone-else"
        self.assertEqual(self.run_cli("check", str(self.dir)), 1)
        self.assertIn("wrong_studio", self.output)
        for bad in ("http://example.com:4801", "http://127.0.0.1:4800", "http://localhost:4819", "https://127.0.0.1:4801", "http://127.0.0.1"):
            with self.assertRaises(sp.Refusal, msg=bad):
                sp.check_base(bad, None)
        self.assertEqual(sp.check_base("http://127.0.0.1:4801", None), "http://127.0.0.1:4801")
        self.assertEqual(sp.check_base("http://localhost:4800", "http://localhost:4800"), "http://localhost:4800")

    def test_ha_moved_refused(self):
        """Fails if: a live publication that moved since the bundle was built is accepted."""
        self.stub.live_rev = 2
        self.stub.history[2] = {"revision": 2, "doc": BASE_DOC, "envelopeSha256": "x"}
        self.assertEqual(self.run_cli("check", str(self.dir)), 1)
        self.assertIn("ha_moved", self.output)

    def test_publish_failure_stays_applied_and_resumes(self):
        """Fails if: a Home Assistant failure after the apply loses the applied state, or a second publish does not resume."""
        self.stub.fail_publish = 1
        self.assertEqual(self.run_cli("apply", str(self.dir), "--reason", "t", "--publish"), 1)
        self.assertIn("ha_unreachable", self.output)
        self.assertEqual(self.record()["state"], "applied")
        self.assertEqual(self.run_cli("publish", str(self.dir), "--reason", "t"), 0, self.output)
        self.assertEqual(self.stub.live_rev, 2)
        self.assertEqual(self.run_cli("apply", str(self.dir), "--reason", "t"), 0)  # idempotent
        self.assertEqual(sum(1 for c in self.stub.calls if c[0] == "PUT"), 1)

    def test_429_retries_once_with_backoff(self):
        """Fails if: a 429 is not retried, or is retried more than once."""
        self.stub.throttle = 1
        self.assertEqual(self.run_cli("status", "--json"), 0, self.output)
        self.stub.throttle = 2
        self.assertEqual(self.run_cli("status", "--json"), 1)


class ScopeAndEvidenceTests(Base):
    def test_scope_violation(self):
        """Fails if: a difference outside the declared scope is applied (a stale base merged by accident)."""
        doc = candidate()
        doc["other"]["keep"] = 99
        self.write_bundle(doc=doc)
        self.assertEqual(self.run_cli("check", str(self.dir)), 1)
        self.assertIn("scope_violation", self.output)
        self.assertEqual(self.run_cli("apply", str(self.dir), "--reason", "t"), 1)
        self.assertEqual(self.stub.draft["revision"], 5)

    def test_scope_is_whole_segments(self):
        """Fails if: scope `/tiles/1` admits `/tiles/10`, or a boolean counts as equal to a number."""
        self.assertTrue(sp.in_scope("/tiles/1/x", ["/tiles/1"]))
        self.assertFalse(sp.in_scope("/tiles/10", ["/tiles/1"]))
        self.assertTrue(sp.diff({"a": True}, {"a": 1}))

    def test_no_change_and_empty_scope(self):
        """Fails if: an identical candidate or an empty scope is applied."""
        self.write_bundle(doc=BASE_DOC)
        self.assertEqual(self.run_cli("check", str(self.dir)), 1)
        self.assertIn("no_change", self.output)
        self.write_bundle(scope=())
        self.assertEqual(self.run_cli("check", str(self.dir)), 1)
        self.assertIn("scope_violation", self.output)

    def test_duplicate_key_and_oversize_refused_before_sending(self):
        """Fails if: a bundle with a duplicate key or over the size limit sends any request."""
        (self.dir / "change.json").write_text('{"id": "c1", "id": "c2"}')
        self.assertEqual(self.run_cli("check", str(self.dir)), 1)
        (self.dir / "change.json").write_text(" " * (sp.MAX_BYTES + 10))
        self.assertEqual(self.run_cli("check", str(self.dir)), 1)
        self.assertEqual(self.stub.calls, [])

    def test_evidence_missing_failing_or_bound_elsewhere_refuses(self):
        """Fails if: apply or publish goes ahead with evidence that is absent, failing, or bound to another document."""
        self.write_bundle(evidence_for={"id": "doc-1", "other": 1})
        self.assertEqual(self.run_cli("apply", str(self.dir), "--reason", "t"), 1)
        self.assertIn("evidence_unbound", self.output)
        self.write_bundle()
        evidence = json.loads((self.dir / "evidence.json").read_text())
        evidence["checks"][0]["result"] = "fail"
        (self.dir / "evidence.json").write_text(json.dumps(evidence))
        self.assertEqual(self.run_cli("apply", str(self.dir), "--reason", "t"), 1)
        self.assertIn("evidence_failed", self.output)
        evidence["checks"][0]["result"] = "pass"
        evidence["screenshots"]["after"] = ["shots/missing.png"]
        (self.dir / "evidence.json").write_text(json.dumps(evidence))
        self.assertEqual(self.run_cli("apply", str(self.dir), "--reason", "t"), 1)
        self.assertIn("evidence_missing", self.output)
        (self.dir / "evidence.json").unlink()
        self.assertEqual(self.run_cli("apply", str(self.dir), "--reason", "t"), 1)
        self.assertEqual(self.stub.draft["revision"], 5)

    def test_security_flag(self):
        """Fails if: a change that mentions a lock is not flagged in the log."""
        doc = candidate()
        doc["tiles"][0]["entity"] = "lock.front_door"
        self.write_bundle(doc=doc, scope=("/tiles/0",))
        self.assertEqual(self.run_cli("apply", str(self.dir), "--reason", "t"), 0, self.output)
        self.assertIn('"security": true', self.log_text())

    def test_change_dir_must_be_under_build_studio_publish(self):
        """Fails if: a directory outside build/studio-publish is accepted as a bundle."""
        other = self.root / "elsewhere"
        other.mkdir()
        self.assertEqual(self.run_cli("check", str(other)), 1)
        self.assertIn("bad_bundle", self.output)


class RollbackTests(Base):
    def published(self):
        self.assertEqual(self.run_cli("apply", str(self.dir), "--reason", "t", "--publish"), 0, self.output)

    def test_rollback_restores_draft_and_live(self):
        """Fails if: rollback leaves the draft or the live revision on the change, or the live hash differs from the pre-publish one."""
        self.published()
        self.assertEqual(self.run_cli("rollback", str(self.dir), "--reason", "t"), 0, self.output)
        self.assertEqual(self.stub.draft["document"], BASE_DOC)
        self.assertEqual(self.stub.history[self.stub.live_rev]["envelopeSha256"], sha(BASE_DOC))
        self.assertEqual(self.record()["state"], "rolled_back")

    def test_draft_moved_leaves_the_draft(self):
        """Fails if: rollback overwrites a draft the owner has edited since."""
        self.published()
        self.stub.owner_saves({**candidate(), "owner": 1})
        self.assertEqual(self.run_cli("rollback", str(self.dir), "--reason", "t"), 0, self.output)
        self.assertEqual(self.stub.draft["document"]["owner"], 1)
        self.assertIn("draft_moved", self.output)

    def test_aged_out_revision_republishes_prior_document(self):
        """Fails if: a 404 from ha/rollback leaves the change live."""
        self.published()
        self.stub.age_out = True
        self.assertEqual(self.run_cli("rollback", str(self.dir), "--reason", "t"), 0, self.output)
        self.assertEqual(self.stub.live_doc, BASE_DOC)
        self.assertEqual(self.stub.draft["document"], BASE_DOC)

    def test_aged_out_with_moved_draft_fails_loudly(self):
        """Fails if: an aged-out entry and a moved draft are reported as a success."""
        self.published()
        self.stub.age_out = True
        self.stub.owner_saves({**candidate(), "owner": 1})
        self.assertEqual(self.run_cli("rollback", str(self.dir), "--reason", "t"), 1)
        self.assertIn("rollback_failed", self.output)

    def test_live_only_and_draft_only(self):
        """Fails if: --live-only touches the draft or --draft-only touches the live publication."""
        self.published()
        self.assertEqual(self.run_cli("rollback", str(self.dir), "--reason", "t", "--live-only"), 0, self.output)
        self.assertEqual(self.stub.draft["document"], candidate())
        self.assertEqual(self.stub.live_doc, BASE_DOC)
        self.assertEqual(self.run_cli("rollback", str(self.dir), "--reason", "t", "--draft-only"), 0, self.output)
        self.assertEqual(self.stub.draft["document"], BASE_DOC)
        self.assertEqual(self.record()["state"], "rolled_back")

    def test_rollback_of_applied_only_restores_draft(self):
        """Fails if: rolling back an unpublished apply calls the live rollback route."""
        self.assertEqual(self.run_cli("apply", str(self.dir), "--reason", "t"), 0)
        self.assertEqual(self.run_cli("rollback", str(self.dir), "--reason", "t"), 0, self.output)
        self.assertEqual(self.stub.draft["document"], BASE_DOC)
        self.assertFalse([c for c in self.stub.calls if c[1].endswith("/ha/rollback")])


class SecretsAndFilesTests(Base):
    def test_no_token_or_document_text_in_output_log_or_status(self):
        """Fails if: the Studio token or a document value appears in stdout, stderr, the log or status --json."""
        self.stub.token = TOKEN
        env = {sp.TOKEN_ENV: TOKEN}
        texts = []
        self.assertEqual(self.run_cli("status", "--json", env=env), 0, self.output)
        texts.append(self.output)
        self.assertEqual(self.run_cli("check", str(self.dir), env=env), 0, self.output)
        texts.append(self.output)
        self.assertEqual(self.run_cli("apply", str(self.dir), "--reason", "t", "--publish", env=env), 0, self.output)
        texts.append(self.output)
        self.assertEqual(self.run_cli("rollback", str(self.dir), "--reason", "t", env=env), 0, self.output)
        texts.append(self.output)
        texts.append(self.log_text())
        self.assertTrue(any(c[2] == "Bearer " + TOKEN for c in self.stub.calls))
        for text in texts:
            self.assertNotIn(TOKEN, text)
            self.assertNotIn(SENTINEL, text)

    def test_works_without_a_token_and_never_sends_one_unasked(self):
        """Fails if: a Bearer header is sent to a Studio that does not ask for one, or a 401 without a token is not a clean refusal."""
        self.assertEqual(self.run_cli("status", env={sp.TOKEN_ENV: TOKEN}), 0)
        self.assertTrue(all(c[2] is None for c in self.stub.calls))
        self.stub.token = TOKEN
        self.assertEqual(self.run_cli("status"), 1)
        self.assertIn("auth_failed", self.output)
        self.assertNotIn(TOKEN, self.output)

    def test_status_names_no_document(self):
        """Fails if: status prints more than revisions, flags and the last change."""
        self.assertEqual(self.run_cli("status", "--json"), 0)
        info = json.loads(self.output)
        self.assertEqual(set(info), {"draftRevision", "liveRevision", "draftIsLive", "openCheck", "historyRevisions", "lastChange"})

    def test_tool_never_opens_a_path_under_native_v2(self):
        """Fails if: the tool opens any file under the Studio's data directory during a full flow."""
        opened = []
        real = builtins.open

        def spy(path, *args, **kwargs):
            opened.append(str(path))
            return real(path, *args, **kwargs)
        with mock.patch.object(builtins, "open", spy), mock.patch.object(os, "open", wraps=os.open) as osopen:
            self.run_cli("apply", str(self.dir), "--reason", "t", "--publish")
            self.run_cli("rollback", str(self.dir), "--reason", "t")
        paths = opened + [str(c.args[0]) for c in osopen.call_args_list]
        self.assertTrue(paths)
        self.assertFalse([p for p in paths if "native-v2" in p or ".studio.lock" in p], paths)


class GuardRoleTests(unittest.TestCase):
    """The table replays a coder; these cover the roles the table cannot name."""

    def verdict(self, command, agent_type=None, headless=False):
        payload = {"tool_name": "Bash", "tool_input": {"command": command}, "cwd": str(TOOLS.parent)}
        if agent_type:
            payload["agent_type"] = agent_type
        env = {"PATH": os.environ.get("PATH", ""), "HOME": "/nonexistent"}
        if headless:
            env["FENTON_HEADLESS"] = "1"
        with mock.patch.dict(os.environ, env, clear=True), mock.patch.object(sys, "stdin", io.StringIO(json.dumps(payload))), \
                redirect_stderr(io.StringIO()):
            return studio_guard.main([])

    def test_publisher_roles(self):
        """Fails if: the orchestrator or menial cannot run apply, or a reviewer, researcher or headless session can."""
        command = "python3 tools/studio_publish.py apply build/studio-publish/c1 --reason x"
        for role in ("orchestrator", "menial"):
            self.assertEqual(self.verdict(command, role), 0, role)
        for role in ("coder", "reviewer", "researcher", "verifier", "steward", "designer"):
            self.assertEqual(self.verdict(command, role), 2, role)
        self.assertEqual(self.verdict(command, "orchestrator", headless=True), 2)

    def test_file_tools(self):
        """Fails if: a file tool reaches native-v2 or the studio lock, or an ordinary path is blocked."""
        for path, want in (("/x/studio/native-v2/state.json", 2), ("/x/studio/.studio.lock", 2), ("/x/repo/docs/a.md", 0)):
            payload = {"tool_name": "Write", "tool_input": {"file_path": path, "content": "x"}, "agent_type": "coder", "cwd": "/x"}
            with mock.patch.dict(os.environ, {"HOME": "/nonexistent"}, clear=True), mock.patch.object(sys, "stdin", io.StringIO(json.dumps(payload))), \
                    redirect_stderr(io.StringIO()):
                self.assertEqual(studio_guard.main([]), want, path)


@unittest.skipUnless(os.environ.get("STUDIO_CHECKOUT") and os.environ.get("STUDIO_CONTRACT_PORT"), "opt-in: needs a scratch Studio")
class ContractTests(unittest.TestCase):
    """Runs only against a scratch Studio started by the caller from STUDIO_CHECKOUT on a port above 4815 with a scratch data dir."""

    def test_port_is_scratch(self):
        """Fails if: the contract test is pointed at a port that serves the owner (4800, 4801, 4819, 4880) or at or below 4815."""
        port = int(os.environ["STUDIO_CONTRACT_PORT"])
        self.assertGreater(port, 4815)
        self.assertNotIn(port, (4819, 4880))


if __name__ == "__main__":
    unittest.main()
