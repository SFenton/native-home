"""``tools/gh_apps_setup.py serve``: manifests, the code exchange against a stub GitHub, and what is never written."""

import http.client
import http.server
import io
import json
import os
import re
import stat
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.parse
import urllib.request
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
sys.path.insert(0, str(TOOLS / "tests"))
import gh_app_token  # noqa: E402
import gh_apps_setup  # noqa: E402
import pr_note  # noqa: E402
from test_gh_app_token import make_apps_dir  # noqa: E402

REAL_VERIFY = gh_app_token.verify_installation
FAKE_KEY = "-----BEGIN RSA PRIVATE KEY-----\nFAKEKEYMATERIAL0123456789\n-----END RSA PRIVATE KEY-----\n"
CLIENT_SECRET = "client-secret-DO-NOT-STORE"
WEBHOOK_SECRET = "webhook-secret-DO-NOT-STORE"


class FakeGitHub(http.server.BaseHTTPRequestHandler):
    """Stub for ``POST /app-manifests/{code}/conversions`` and ``GET /app/installations``."""

    seen = []

    def log_message(self, *args):
        pass

    def do_POST(self):
        FakeGitHub.seen.append((self.path, self.headers.get("Accept")))
        m = re.match(r"^/app-manifests/([^/]+)/conversions$", self.path)
        if not m or m.group(1) != "goodcode":
            self.send_response(404)
            self.end_headers()
            return
        body = json.dumps({"id": 4242, "slug": "s-h-coder-x", "client_id": "Iv1.abc", "client_secret": CLIENT_SECRET,
                           "webhook_secret": WEBHOOK_SECRET, "pem": FAKE_KEY}).encode()
        self.send_response(201)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.folder = Path(self.tmp.name) / "github-apps"
        for patcher in (mock.patch.dict(os.environ, {"FENTON_HASS_APPS_DIR": str(self.folder), "HOME": self.tmp.name, "GITHUB_REPOSITORY": "owner/private-app"}),):
            patcher.start()
            self.addCleanup(patcher.stop)
        self.fake = http.server.HTTPServer(("127.0.0.1", 0), FakeGitHub)
        threading.Thread(target=self.fake.serve_forever, daemon=True).start()
        self.addCleanup(self.fake.server_close)
        self.addCleanup(self.fake.shutdown)
        p = mock.patch.object(gh_apps_setup, "CONVERT_BASE", f"http://127.0.0.1:{self.fake.server_address[1]}")
        p.start()
        self.addCleanup(p.stop)
        FakeGitHub.seen = []
        v = mock.patch.object(gh_app_token, "verify_installation", return_value=True)
        self.verify = v.start()
        self.addCleanup(v.stop)
        gh_apps_setup.PENDING.clear()
        self.addCleanup(gh_apps_setup.PENDING.clear)
        self.server = gh_apps_setup.SetupServer(0)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)

    def get(self, path):
        """GET without following redirects; returns ``(status, location, body)``."""
        class NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, *a, **k):
                return None
        opener = urllib.request.build_opener(NoRedirect)
        try:
            with opener.open(f"http://127.0.0.1:{self.server.port}{path}", timeout=10) as r:
                return r.status, r.headers.get("Location"), r.read().decode()
        except urllib.error.HTTPError as exc:
            return exc.code, exc.headers.get("Location"), exc.read().decode()

    def created(self, role="coder", code="goodcode", state=None):
        q = urllib.parse.urlencode({"role": role, "code": code, "state": self.server.state if state is None else state})
        return self.get(f"/created?{q}")

    def config(self):
        return json.loads((self.folder / "apps.json").read_text())


class ManifestTests(unittest.TestCase):
    def test_manifest_fields(self):
        for role in gh_app_token.ROLES:
            m = gh_apps_setup.manifest(role, 8765)
            self.assertEqual(m["redirect_url"], f"http://127.0.0.1:8765/created?role={role}")
            self.assertEqual(m["setup_url"], f"http://127.0.0.1:8765/installed?role={role}")
            self.assertIs(m["public"], False)
            self.assertIs(m["hook_attributes"]["active"], False)
            self.assertEqual(m["default_permissions"], {"issues": "write", "pull_requests": "read", "metadata": "read"})
            self.assertTrue(m["name"].startswith("S+H "))

    def test_old_static_mode_says_use_serve(self):
        err = io.StringIO()
        with redirect_stderr(err):
            self.assertEqual(gh_apps_setup.main([]), 2)
        self.assertIn("serve", err.getvalue())


class ServerTests(Base):
    def test_binds_loopback_only(self):
        self.assertEqual(self.server.server_address[0], "127.0.0.1")

    def test_page_lists_nine_roles_with_state_and_post_forms(self):
        status, _loc, page = self.get("/")
        self.assertEqual(status, 200)
        self.assertEqual(len(re.findall(r'<form method="post" action="https://github.com/settings/apps/new\?state=', page)), 9)
        self.assertIn(urllib.parse.quote(self.server.state), page)
        self.assertEqual(page.count("(not created)"), 9)

    def test_state_mismatch_is_refused(self):
        status, _loc, _body = self.created(state="wrong")
        self.assertEqual(status, 403)
        self.assertEqual(FakeGitHub.seen, [])
        self.assertFalse(self.folder.exists() and (self.folder / "coder.pem").exists())

    def test_unknown_role_is_refused(self):
        status, _loc, _body = self.created(role="admin")
        self.assertEqual(status, 400)
        self.assertEqual(FakeGitHub.seen, [])
        status, _loc, _body = self.get("/installed?role=admin&installation_id=5")
        self.assertEqual(status, 400)

    def test_created_writes_key_at_600_and_redirects_to_install(self):
        status, location, body = self.created()
        self.assertEqual(status, 302)
        self.assertEqual(location, "https://github.com/apps/s-h-coder-x/installations/new")
        self.assertEqual(FakeGitHub.seen, [("/app-manifests/goodcode/conversions", "application/vnd.github+json")])
        key = self.folder / "coder.pem"
        self.assertEqual(key.read_text(), FAKE_KEY)
        self.assertEqual(stat.S_IMODE(key.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(self.folder.stat().st_mode), 0o700)
        self.assertEqual(self.config(), {"repo": "owner/private-app",
                                         "apps": {"coder": {"app_id": 4242, "slug": "s-h-coder-x", "client_id": "Iv1.abc"}}})
        self.assertEqual([p.name for p in self.folder.iterdir() if p.name.startswith(".")], [])

    def test_secrets_are_never_written_or_shown(self):
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            _s, _l, body = self.created()
            _s2, _l2, page = self.get("/")
            _s3, _l3, bad = self.created(code="badcode")
        hidden = ("FAKEKEYMATERIAL", "BEGIN RSA", CLIENT_SECRET, WEBHOOK_SECRET)
        for text in (out.getvalue(), err.getvalue(), body, page, bad):
            for needle in hidden:
                self.assertNotIn(needle, text)
        for path in self.folder.iterdir():
            if path.name != "coder.pem":
                for needle in hidden:
                    self.assertNotIn(needle, path.read_text())
        self.assertIn("refused the code", bad)
        self.assertNotIn("badcode", bad)

    def test_apps_json_is_merged_not_clobbered(self):
        make_apps_dir_into(self.folder, ("verifier",))
        self.created()
        data = self.config()
        self.assertEqual(data["apps"]["verifier"], {"app_id": 101, "installation_id": 201})
        self.assertEqual(data["apps"]["coder"]["app_id"], 4242)

    def test_installed_records_the_id_and_shows_next_step(self):
        self.created(role="steward")
        status, _loc, page = self.get("/installed?role=steward&installation_id=777&setup_action=install")
        self.assertEqual(status, 200)
        self.assertEqual(self.config()["apps"]["steward"]["installation_id"], 777)
        self.assertEqual(self.config()["apps"]["steward"]["app_id"], 4242)
        self.assertIn(gh_apps_setup.REQUEST_REPO_LABEL, page)
        self.assertIn("optional", page)
        self.assertEqual(gh_apps_setup.role_state("steward"), "installed")

    def test_installed_requires_numeric_id_and_a_created_app(self):
        self.assertEqual(self.get("/installed?role=coder&installation_id=5")[0], 400)
        self.created()
        self.assertEqual(self.get("/installed?role=coder&installation_id=abc")[0], 400)

    def test_created_role_offers_only_the_install_link(self):
        self.created()
        _s, _l, page = self.get("/")
        self.assertIn("https://github.com/apps/s-h-coder-x/installations/new", page)
        self.assertEqual(page.count("<form"), 8)

    def test_summary_has_ids_only_and_finishes_when_all_installed(self):
        for role in gh_app_token.ROLES:
            gh_apps_setup.record(role, app_id=1, installation_id=2)
        self.server.check_done()
        self.assertTrue(self.server.finished.is_set())
        lines = gh_apps_setup.summary()
        self.assertEqual(len(lines), 9)
        self.assertEqual(lines[0], "orchestrator: installed (app_id 1, installation_id 2)")

    def test_spoofed_installation_is_ignored_and_does_not_finish(self):
        for role in gh_app_token.ROLES:
            gh_apps_setup.record(role, app_id=1)
        self.verify.return_value = False
        status, _loc, page = self.get("/installed?role=coder&installation_id=999")
        self.assertEqual(status, 400)
        self.assertIn("ignored", page)
        self.assertNotIn("installation_id", self.config()["apps"]["coder"])
        self.assertFalse(self.server.finished.is_set())
        self.assertEqual(self.verify.call_args.args, ("coder", 999))

    def test_unconfirmable_installation_records_nothing(self):
        self.created()
        self.verify.side_effect = gh_app_token.AppError("GitHub unreachable")
        status, _loc, _page = self.get("/installed?role=coder&installation_id=5")
        self.assertEqual(status, 502)
        self.assertNotIn("installation_id", self.config()["apps"]["coder"])

    def test_unparseable_apps_json_is_never_overwritten_and_code_is_not_spent(self):
        self.folder.mkdir(parents=True)
        (self.folder / "apps.json").write_text("{not json")
        status, _loc, page = self.created()
        self.assertEqual(status, 502)
        self.assertIn("cannot be read", page)
        self.assertEqual((self.folder / "apps.json").read_text(), "{not json")
        self.assertEqual(FakeGitHub.seen, [])
        self.assertFalse((self.folder / "coder.pem").exists())
        with self.assertRaises(gh_apps_setup.SetupError):
            gh_apps_setup.record("coder", app_id=1)
        self.assertEqual((self.folder / "apps.json").read_text(), "{not json")

    def test_wrong_host_header_is_refused_on_every_route(self):
        for path in ("/", "/created?role=coder", "/installed?role=coder", "/nope"):
            for host in ("evil.example", f"evil.example:{self.server.port}", "127.0.0.1"):
                conn = http.client.HTTPConnection("127.0.0.1", self.server.port, timeout=10)
                conn.putrequest("GET", path, skip_host=True)
                conn.putheader("Host", host)
                conn.endheaders()
                self.assertEqual(conn.getresponse().status, 403, (path, host))
                conn.close()
        conn = http.client.HTTPConnection("localhost", self.server.port, timeout=10)
        conn.request("GET", "/")
        self.assertEqual(conn.getresponse().status, 200)

    def test_key_write_failure_tells_the_owner_to_delete_the_app(self):
        with mock.patch.object(gh_apps_setup, "_atomic_write", side_effect=OSError("disk")):
            status, _loc, page = self.created()
        self.assertEqual(status, 502)
        self.assertIn("exists on GitHub", page)
        self.assertIn("https://github.com/settings/apps/s-h-coder-x/advanced", page)
        self.assertNotIn("FAKEKEYMATERIAL", page)

    def test_record_failure_after_the_key_is_retried_on_next_load(self):
        real = gh_apps_setup.record
        with mock.patch.object(gh_apps_setup, "record", side_effect=OSError("disk")):
            status, _loc, page = self.created()
        self.assertEqual(status, 502)
        self.assertIn('&quot;coder&quot;: {', page)
        self.assertTrue((self.folder / "coder.pem").is_file())
        self.assertFalse((self.folder / "apps.json").exists())
        self.get("/")
        self.assertEqual(self.config()["apps"]["coder"]["app_id"], 4242)
        self.assertEqual(gh_apps_setup.PENDING, {})
        self.assertIs(real, gh_apps_setup.record)

    def test_handler_exception_shows_a_plain_error(self):
        err = io.StringIO()
        with mock.patch.object(gh_apps_setup, "render_page", side_effect=RuntimeError("boom with /secret/path")), \
                redirect_stderr(err):
            status, _loc, page = self.get("/")
        self.assertEqual(status, 500)
        self.assertNotIn("Traceback", page)
        self.assertNotIn("boom", page)
        self.assertNotIn("boom", err.getvalue())

    def test_page_tells_the_owner_to_do_one_role_first(self):
        _s, _l, page = self.get("/")
        self.assertIn("one role end to end first", page)


def make_apps_dir_into(folder: Path, roles) -> None:
    """Fill an existing ``folder`` with the standard fixture (key + ids for ``roles``)."""
    with tempfile.TemporaryDirectory() as tmp:
        made = make_apps_dir(Path(tmp), roles)
        folder.mkdir(parents=True, exist_ok=True)
        for item in made.iterdir():
            (folder / item.name).write_bytes(item.read_bytes())


class SlugAndDiscoveryTests(Base):
    def test_pr_note_author_check_uses_recorded_slug(self):
        gh_apps_setup.record("coder", app_id=1, slug="s-h-coder-x")
        self.assertTrue(pr_note.is_app_login("s-h-coder-x[bot]"))
        self.assertFalse(pr_note.is_app_login("s-h-coder[bot]"))
        self.assertTrue(pr_note.is_app_login("s-h-menial[bot]"))
        self.assertFalse(pr_note.is_app_login("someone[bot]"))
        self.assertFalse(pr_note.is_app_login("s-h-coder-x"))

    def test_installation_id_is_looked_up_with_the_jwt_and_cached(self):
        make_apps_dir_into(self.folder, ("verifier",))
        data = json.loads((self.folder / "apps.json").read_text())
        del data["apps"]["verifier"]["installation_id"]
        (self.folder / "apps.json").write_text(json.dumps(data))
        gh_app_token._INSTALLATIONS.clear()
        self.addCleanup(gh_app_token._INSTALLATIONS.clear)
        reply = [{"id": 9, "account": {"login": "someone-else"}}, {"id": 55, "account": {"login": "SFenton"}}]
        with mock.patch.object(gh_app_token, "api_request", return_value=reply) as api:
            self.assertEqual(gh_app_token.installation_id("verifier"), 55)
            self.assertEqual(gh_app_token.installation_id("verifier"), 55)
        self.assertEqual(api.call_count, 1)
        self.assertEqual(api.call_args.args[:2], ("GET", "app/installations"))
        self.assertTrue(gh_app_token.available("verifier"))

    def test_installation_lookup_fails_without_an_sfenton_installation(self):
        make_apps_dir_into(self.folder, ("verifier",))
        data = json.loads((self.folder / "apps.json").read_text())
        del data["apps"]["verifier"]["installation_id"]
        (self.folder / "apps.json").write_text(json.dumps(data))
        gh_app_token._INSTALLATIONS.clear()
        with mock.patch.object(gh_app_token, "api_request", return_value=[{"id": 9, "account": {"login": "x"}}]):
            with self.assertRaises(gh_app_token.AppError):
                gh_app_token.installation_id("verifier")


class InstallationVerifyTests(Base):
    def setUp(self):
        super().setUp()
        make_apps_dir_into(self.folder, ("verifier",))
        gh_app_token._INSTALLATIONS.clear()
        self.addCleanup(gh_app_token._INSTALLATIONS.clear)

    def test_bad_recorded_id_falls_back_to_lookup_and_is_not_reused(self):
        calls = []

        def api(method, path, bearer, payload=None, timeout=None):
            calls.append(path)
            if path == "app/installations/201":
                err = gh_app_token.AppError("GitHub answered 404")
                err.status = 404
                raise err
            if path == "app/installations":
                return [{"id": 77, "account": {"login": "SFenton"}}]
            raise AssertionError(path)

        self.verify.side_effect = None
        with mock.patch.object(gh_app_token, "verify_installation", REAL_VERIFY), \
                mock.patch.object(gh_app_token, "api_request", api):
            self.assertEqual(gh_app_token.installation_id("verifier"), 77)
            self.assertEqual(gh_app_token.installation_id("verifier"), 77)
        self.assertEqual(calls, ["app/installations/201", "app/installations"])

    def test_recorded_id_on_another_account_falls_back(self):
        def api(method, path, bearer, payload=None, timeout=None):
            if path == "app/installations/201":
                return {"account": {"login": "stranger"}}
            return [{"id": 78, "account": {"login": "sfenton"}}]

        with mock.patch.object(gh_app_token, "verify_installation", REAL_VERIFY), \
                mock.patch.object(gh_app_token, "api_request", api):
            self.assertEqual(gh_app_token.installation_id("verifier"), 78)

    def test_good_recorded_id_is_kept(self):
        def api(method, path, bearer, payload=None, timeout=None):
            return {"account": {"login": "SFenton"}}

        with mock.patch.object(gh_app_token, "verify_installation", REAL_VERIFY), \
                mock.patch.object(gh_app_token, "api_request", api):
            self.assertEqual(gh_app_token.installation_id("verifier"), 201)


class SourceTests(unittest.TestCase):
    def test_no_code_path_prints_the_key(self):
        """Every print/log/write-to-stream in the helper uses text that is not the key variable."""
        source = (TOOLS / "gh_apps_setup.py").read_text()
        for line in source.splitlines():
            if re.search(r"\b(print|logging|logger|sys\.stdout|sys\.stderr)\b", line) or "wfile.write" in line:
                self.assertNotRegex(line, r"\bkey\b|\bpem\b|material|client_secret|webhook_secret|result\b", line)
        self.assertNotIn("client_secret\"]", source)
        self.assertNotIn("webhook_secret\"]", source)
        # the only reply fields read are the four named ones
        self.assertEqual(sorted(set(re.findall(r'body\.get\("(\w+)"\)', source))), ["client_id", "id", "pem", "slug"])


if __name__ == "__main__":
    unittest.main()
