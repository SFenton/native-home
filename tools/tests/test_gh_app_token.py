"""``tools/gh_app_token.py`` (JWT, token cache, status CLI) and ``pr_note.py --as`` routing, all with temp fixtures."""

import ast
import base64
import io
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
sys.path.insert(0, str(TOOLS / "tests"))
import gh_app_token  # noqa: E402
import pr_note  # noqa: E402
from test_pr_note import Base  # noqa: E402

TOKEN = "ghs_123456_FAKE_INSTALLATION_TOKEN"
SLUG = "s-h-verifier"


def make_apps_dir(root: Path, roles=("verifier",)) -> Path:
    """A temp apps folder with a throwaway 2048-bit key per role and an ``apps.json``."""
    folder = root / "github-apps"
    folder.mkdir()
    apps = {}
    for n, role in enumerate(roles, 1):
        subprocess.run(["openssl", "genrsa", "-out", str(folder / f"{role}.pem"), "2048"], check=True,
                       capture_output=True)
        apps[role] = {"app_id": 100 + n, "installation_id": 200 + n}
    (folder / "apps.json").write_text(json.dumps({"repo": "SFenton/Fenton-HASS-Native", "apps": apps}))
    return folder


def b64d(part: str) -> bytes:
    return base64.urlsafe_b64decode(part + "=" * (-len(part) % 4))


class AppsDirCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.folder = make_apps_dir(Path(self.tmp.name))
        patcher = mock.patch.dict(os.environ, {"FENTON_HASS_APPS_DIR": str(self.folder)})
        patcher.start()
        self.addCleanup(patcher.stop)
        gh_app_token._CACHE.clear()
        gh_app_token._INSTALLATIONS.clear()
        self.addCleanup(gh_app_token._CACHE.clear)


class JwtTests(AppsDirCase):
    def test_claims_and_signature_verify_with_the_public_key(self):
        now = 1_800_000_000
        text = gh_app_token.jwt("verifier", now=now)
        head, claims, sig = text.split(".")
        self.assertEqual(json.loads(b64d(head)), {"alg": "RS256", "typ": "JWT"})
        self.assertEqual(json.loads(b64d(claims)), {"iat": now - 60, "exp": now + 540, "iss": "101"})
        pub = Path(self.tmp.name) / "pub.pem"
        subprocess.run(["openssl", "rsa", "-in", str(self.folder / "verifier.pem"), "-pubout", "-out", str(pub)],
                       check=True, capture_output=True)
        sigfile = Path(self.tmp.name) / "sig"
        sigfile.write_bytes(b64d(sig))
        done = subprocess.run(["openssl", "dgst", "-sha256", "-verify", str(pub), "-signature", str(sigfile)],
                              input=f"{head}.{claims}".encode(), capture_output=True)
        self.assertEqual(done.returncode, 0, done.stderr)

    def test_expiry_is_within_ten_minutes(self):
        claims = json.loads(b64d(gh_app_token.jwt("verifier").split(".")[1]))
        self.assertLessEqual(claims["exp"] - claims["iat"], 600)

    def test_unknown_role_and_missing_key_are_refused(self):
        with self.assertRaises(gh_app_token.AppError):
            gh_app_token.key_path("nobody")
        (self.folder / "verifier.pem").unlink()
        self.assertFalse(gh_app_token.available("verifier"))
        with self.assertRaises(gh_app_token.AppError):
            gh_app_token.jwt("verifier")


class TokenTests(AppsDirCase):
    def fake_api(self, calls):
        def api(method, path, bearer, payload=None, timeout=None):
            calls.append((method, path, payload))
            if path.startswith("app/installations/") and method == "GET":
                return {"account": {"login": "SFenton"}}
            if path.endswith("/access_tokens"):
                return {"token": TOKEN, "expires_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() + 3600))}
            return {"slug": SLUG}
        return api

    def test_token_is_minted_once_and_cached_in_memory(self):
        calls = []
        with mock.patch.object(gh_app_token, "api_request", self.fake_api(calls)):
            self.assertEqual(gh_app_token.token("verifier"), TOKEN)
            self.assertEqual(gh_app_token.token("verifier"), TOKEN)
        self.assertEqual(calls[0][:2], ("GET", "app/installations/201"))
        calls = [c for c in calls if c[0] == "POST"]
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0][:2], ("POST", "app/installations/201/access_tokens"))
        self.assertEqual(calls[0][2], {"permissions": {"issues": "write", "pull_requests": "read"}})
        self.assertNotIn(TOKEN, "".join(p.read_text(errors="ignore") for p in self.folder.iterdir()))

    def test_near_expiry_token_is_minted_again(self):
        calls = []
        with mock.patch.object(gh_app_token, "api_request", self.fake_api(calls)):
            gh_app_token.token("verifier")
            gh_app_token._CACHE["verifier"] = (TOKEN, time.time() + 30)
            gh_app_token.token("verifier")
        self.assertEqual(len([c for c in calls if c[0] == "POST"]), 2)

    def test_api_request_turns_http_and_json_errors_into_apperror(self):
        import http.client
        for exc in (http.client.IncompleteRead(b"x"), http.client.BadStatusLine("x")):
            with mock.patch.object(gh_app_token.urllib.request, "urlopen", side_effect=exc):
                with self.assertRaises(gh_app_token.AppError):
                    gh_app_token.api_request("GET", "app", "b")
        resp = mock.MagicMock()
        resp.__enter__.return_value.read.return_value = b"{not json"
        with mock.patch.object(gh_app_token.urllib.request, "urlopen", return_value=resp):
            with self.assertRaises(gh_app_token.AppError):
                gh_app_token.api_request("GET", "app", "b")

    def test_check_prints_status_only(self):
        out = io.StringIO()
        with mock.patch.object(gh_app_token, "api_request", self.fake_api([])), redirect_stdout(out):
            code = gh_app_token.main(["check", "verifier"])
        self.assertEqual(code, 0)
        self.assertEqual(out.getvalue().strip(), "verifier: key present, app reachable")
        self.assertNotIn(TOKEN, out.getvalue())
        out = io.StringIO()
        with redirect_stdout(out):
            self.assertEqual(gh_app_token.main(["check", "coder"]), 1)
        self.assertIn("key missing", out.getvalue())


class SourceTests(unittest.TestCase):
    """``gh_app_token`` has no path by which a token or key could be printed or written."""

    def setUp(self):
        self.source = (TOOLS / "gh_app_token.py").read_text()
        self.tree = ast.parse(self.source)

    def test_only_status_strings_are_printed(self):
        prints = [n for n in ast.walk(self.tree) if isinstance(n, ast.Call) and getattr(n.func, "id", "") == "print"]
        self.assertEqual(len(prints), 1)
        names = {n.id for n in ast.walk(prints[0]) if isinstance(n, ast.Name)}
        self.assertEqual(names - {"print", "args", "present", "reachable"}, set())

    def test_nothing_is_written(self):
        for bad in ("write_text", "write_bytes", ".write(", "os.open", "sys.stdout", "sys.stderr", "logging", "environ["):
            self.assertNotIn(bad, self.source, bad)
        for n in ast.walk(self.tree):
            if isinstance(n, ast.Call) and getattr(n.func, "id", "") == "open":
                self.fail("open() call")

    def test_error_messages_never_interpolate_a_token(self):
        for n in ast.walk(self.tree):
            if isinstance(n, ast.Raise) and n.exc is not None:
                names = {x.id for x in ast.walk(n.exc) if isinstance(x, ast.Name)}
                self.assertFalse(names & {"value", "reply", "bearer", "cached"}, ast.dump(n))


class AsRoleTests(Base):
    """``pr_note --as`` with a throwaway key and a fake GitHub API that edits the fake PR's comments."""

    def setUp(self):
        super().setUp()
        self.apps = make_apps_dir(Path(self.tmp.name))
        p = mock.patch.dict(os.environ, {"FENTON_HASS_APPS_DIR": str(self.apps)})
        p.start()
        self.addCleanup(p.stop)
        gh_app_token._CACHE.clear()
        gh_app_token._INSTALLATIONS.clear()
        self.addCleanup(gh_app_token._CACHE.clear)
        self.rest = []
        p = mock.patch.object(gh_app_token, "api_request", self.api)
        p.start()
        self.addCleanup(p.stop)

    def api(self, method, path, bearer, payload=None, timeout=None):
        self.rest.append((method, path, bearer))
        if path.startswith("app/installations/") and method == "GET":
            return {"account": {"login": "SFenton"}}
        if path.endswith("/access_tokens"):
            return {"token": TOKEN, "expires_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() + 3600))}
        if path == "app":
            return {"slug": SLUG}
        st = self.get()
        bot = {"login": f"{SLUG}[bot]", "type": "Bot"}
        if method == "POST":
            st["comments"].append({"id": 100 + len(st["comments"]), "body": payload["body"], "user": bot})
        else:
            cid = int(path.rsplit("/", 1)[1])
            target = next(c for c in st["comments"] if c["id"] == cid)
            if target["user"]["type"] != "Bot":
                raise gh_app_token.AppError("GitHub answered 403")
            target["body"] = payload["body"]
        self.set_state(comments=st["comments"])
        return {}

    def comments(self):
        return self.get()["comments"]

    def test_no_key_falls_back_to_the_owner_login(self):
        code, out, err = self.post("verdict", "### Verdict\nok", "1", "--as", "coder")
        self.assertEqual((code, out.strip()), (0, "pr_note: posted"))
        self.assertIn("no app identity for coder", err)
        self.assertEqual(self.rest, [])
        self.assertNotIn("user", self.comments()[0])

    def test_without_as_nothing_touches_the_app_api(self):
        self.post("verdict", "### Verdict\nok")
        self.assertEqual(self.rest, [])

    def test_with_a_key_the_comment_is_posted_by_the_app(self):
        code, out, err = self.post("verdict", "### Verdict\nok", "1", "--as", "verifier")
        self.assertEqual(out.strip(), "pr_note: posted")
        self.assertEqual(err, "")
        c = self.comments()[0]
        self.assertEqual(c["user"]["login"], f"{SLUG}[bot]")
        self.assertNotIn("@SFenton", c["body"])
        self.assertNotIn(TOKEN, json.dumps(c) + self.log.read_text())
        posts = [r for r in self.rest if r[0] == "POST" and "comments" in r[1]]
        self.assertEqual(posts[0][1], "repos/SFenton/Fenton-HASS-Native/issues/7/comments")

    def test_app_edits_its_own_comment_then_is_unchanged(self):
        self.post("verdict", "### V\none", "1", "--as", "verifier")
        _c, out, _e = self.post("verdict", "### V\ntwo", "1", "--as", "verifier")
        self.assertEqual(out.strip(), "pr_note: edited")
        _c, out, _e = self.post("verdict", "### V\ntwo", "1", "--as", "verifier")
        self.assertEqual(out.strip(), "pr_note: unchanged")
        self.assertEqual(len(self.comments()), 1)
        self.assertIn("updated", self.comments()[0]["body"])

    def test_handoff_and_owner_start_with_the_mention_but_other_kinds_do_not(self):
        self.post("handoff", "### Handoff\nneeds you", "1", "--as", "verifier")
        self.post("owner", "### Owner\nlook", "1", "--as", "verifier")
        self.post("pick", "### Pick\nB", "1", "--as", "verifier")
        bodies = [c["body"] for c in self.comments()]
        self.assertTrue(bodies[0].startswith("@SFenton\n\n### Handoff"))
        self.assertTrue(bodies[1].startswith("@SFenton\n\n### Owner"))
        self.assertTrue(bodies[2].startswith("### Pick"))

    def test_mention_is_not_doubled_and_not_added_for_the_owner_login(self):
        self.post("handoff", "@SFenton already here", "1", "--as", "verifier")
        self.assertEqual(self.comments()[0]["body"].count("@SFenton"), 1)
        self.post("handoff", "### Handoff\nx", "2")
        self.assertNotIn("@SFenton", self.comments()[1]["body"])

    def test_owner_comment_is_replaced_by_the_app_not_doubled(self):
        self.post("verdict", "### V\nsame text", "1")
        st = self.get()
        st["comments"][0]["user"] = {"login": "SFenton", "type": "User"}
        self.set_state(comments=st["comments"])
        _c, out, _e = self.post("verdict", "### V\nsame text", "1", "--as", "verifier")
        self.assertEqual(out.strip(), "pr_note: replaced")
        cs = self.comments()
        self.assertEqual(len(cs), 1)
        self.assertEqual(cs[0]["user"]["login"], f"{SLUG}[bot]")

    def test_app_comment_is_replaced_by_the_owner_when_the_key_goes_away(self):
        self.post("verdict", "### V\nsame text", "1", "--as", "verifier")
        _c, out, _e = self.post("verdict", "### V\nsame text", "1")
        self.assertEqual(out.strip(), "pr_note: replaced")
        cs = self.comments()
        self.assertEqual(len(cs), 1)
        self.assertNotIn("user", cs[0])

    def test_marker_lookup_ignores_authors_and_picks_the_identitys_own(self):
        self.post("verdict", "### V\nv1", "1", "--as", "verifier")
        tag = pr_note.marker("verdict", "T-x", 1)
        st = self.get()
        st["comments"].append({"id": 900, "body": f"x\n{tag}\n", "user": {"login": "SFenton", "type": "User"}})
        self.set_state(comments=st["comments"])
        _c, out, _e = self.post("verdict", "### V\nv2", "1", "--as", "verifier")
        self.assertEqual(out.strip(), "pr_note: edited")
        self.assertEqual(len(self.comments()), 2)

    def test_resolve_edits_an_owner_written_handoff_as_the_owner(self):
        self.post("handoff", "### Handoff\nx", "1")
        _c, out, _e = self.run_cli("resolve", "--task", "T-x", "--round", "1", "--text", "done", "--as", "verifier")
        self.assertEqual(out.strip(), "pr_note: resolved")
        self.assertTrue(self.comments()[0]["body"].startswith("**Resolved:** done"))

    def test_posted_text_is_redacted(self):
        self.post("verdict", "### V\nkey ghs_123456_abcdef0123456789abcdef0123456789abcdef and gho_abcdefghijklmnopqrstuvwxyz0123456789",
                  "1", "--as", "verifier")
        body = self.comments()[0]["body"]
        self.assertNotIn("abcdef0123456789abcdef0123456789abcdef", body)
        self.assertNotIn("gho_abcdefghijklmnopqrstuvwxyz0123456789", body)

    def test_local_media_stays_on_the_owner_login(self):
        pic = Path(self.tmp.name) / "pic.png"
        pic.write_bytes(b"png")
        self.post("evidence", f"### E\n![a]({pic})", "1", "--as", "verifier", "--class", "iphone")
        self.assertEqual([r for r in self.rest if r[0] == "POST" and "comments" in r[1]], [])
        self.assertIn("user-attachments", self.comments()[0]["body"])

    def test_queued_note_keeps_its_role_for_the_flush(self):
        self.set_state(pr=0)
        self.post("handoff", "### Handoff\nq", "1", "--as", "verifier")
        queued = json.loads(next((pr_note.NOTES_DIR / "T-x" / "queue").glob("*.json")).read_text())
        self.assertEqual(queued["as"], "verifier")
        self.set_state(pr=7)
        self.run_cli("flush", "--task", "T-x", "--as", "verifier")
        self.assertTrue(self.comments()[0]["body"].startswith("@SFenton"))

    def test_mint_failure_falls_back_with_one_line(self):
        def boom(*a, **k):
            raise gh_app_token.AppError("GitHub answered 401 for POST x")
        with mock.patch.object(gh_app_token, "api_request", boom):
            _c, out, err = self.post("verdict", "### V\nok", "1", "--as", "verifier")
        self.assertEqual(out.strip(), "pr_note: posted")
        self.assertIn("failed", err)
        self.assertNotIn("user", self.comments()[0])

    def test_non_apperror_mint_failure_still_posts_as_the_owner(self):
        for n, exc in enumerate((ValueError("bad json"), RuntimeError("odd")), 1):
            with mock.patch.object(gh_app_token, "api_request", mock.Mock(side_effect=exc)):
                _c, out, err = self.post("verdict", f"### V\n{type(exc).__name__}", str(n), "--as", "verifier")
            self.assertEqual(out.strip(), "pr_note: posted")
            self.assertIn("failed", err)
        self.assertEqual(len(self.comments()), 2)

    def test_failure_while_posting_as_the_app_queues_the_note(self):
        real = self.api

        def flaky(method, path, bearer, payload=None, timeout=None):
            if method == "POST" and "comments" in path:
                raise ValueError("truncated")
            return real(method, path, bearer, payload, timeout)
        with mock.patch.object(gh_app_token, "api_request", flaky):
            _c, _o, err = self.post("verdict", "### V\nlost?", "1", "--as", "verifier")
        self.assertIn("not posted", err)
        self.assertEqual(len(list((pr_note.NOTES_DIR / "T-x" / "queue").glob("*.json"))), 1)

    def test_flush_posts_each_note_as_its_own_role(self):
        self.set_state(pr=0)
        self.post("pick", "### Pick\nc", "1", "--as", "coder")
        self.post("handoff", "### H\nv", "1", "--as", "verifier")
        self.set_state(pr=7)
        self.run_cli("flush", "--task", "T-x", "--as", "verifier")
        by_kind = {("pick" if "Pick" in c["body"] else "handoff"): c for c in self.comments()}
        self.assertNotIn("user", by_kind["pick"])  # coder has no key: owner login, not the verifier app
        self.assertEqual(by_kind["handoff"]["user"]["login"], f"{SLUG}[bot]")

    def test_third_party_comments_with_the_marker_survive(self):
        tag = pr_note.marker("verdict", "T-x", 1)
        others = [("coderabbitai[bot]", "Bot"), ("collaborator", "User"), ("s-h-coder[bot]", "Bot")]
        st = self.get()
        for n, (login, kind) in enumerate(others):
            st["comments"].append({"id": 500 + n, "body": f"x\n{tag}\n", "user": {"login": login, "type": kind}})
        self.set_state(comments=st["comments"])
        self.post("verdict", "### V\nmine", "1", "--as", "verifier")
        self.assertEqual(len(self.comments()), 4)
        # and as the owner: only s-h apps' comments are replaceable, the others stay
        self.post("verdict", "### V\nmine", "1")
        logins = [(c.get("user") or {}).get("login") for c in self.comments()]
        self.assertIn("coderabbitai[bot]", logins)
        self.assertIn("collaborator", logins)
        self.assertNotIn(f"{SLUG}[bot]", logins)

    def test_collaborator_comment_is_not_edited_as_the_owners(self):
        tag = pr_note.marker("verdict", "T-x", 1)
        self.set_state(comments=[{"id": 600, "body": f"x\n{tag}\n", "user": {"login": "collaborator", "type": "User"}}])
        _c, out, _e = self.post("verdict", "### V\nmine", "1")
        self.assertEqual(out.strip(), "pr_note: posted")
        self.assertEqual(len(self.comments()), 2)

    def test_marker_quoted_in_a_body_is_not_a_match(self):
        tag = pr_note.marker("verdict", "T-x", 1)
        self.set_state(comments=[{"id": 700, "body": f"> {tag}\nquoting the bot, more text after",
                                  "user": {"login": "SFenton", "type": "User"}}])
        _c, out, _e = self.post("verdict", "### V\nmine", "1", "--as", "verifier")
        self.assertEqual(out.strip(), "pr_note: posted")
        self.assertEqual(len(self.comments()), 2)

    def test_as_choices_are_the_nine_roles(self):
        self.assertEqual(set(pr_note.ROLES), {"orchestrator", "researcher", "designer", "coder", "verifier",
                                              "reviewer", "steward", "menial", "triage"})
        with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            pr_note.main(["post", "verdict", "--task", "T", "--round", "1", "--body-file", "x", "--as", "nobody"])


if __name__ == "__main__":
    unittest.main()
