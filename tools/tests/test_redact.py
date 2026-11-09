"""tools/redact.py and its use by bg_run, retro_digest (the archive side is in tools/triage/tests)."""

from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import redact  # noqa: E402
import retro_digest  # noqa: E402

JWT = "eyJ" + "hbGciOiJIUzI1NiJ9" + "." + "eyJpc3MiOiJmYWtlIn0" + "." + "c2lnbmF0dXJlZmFrZQ"
#: (fake secret, text containing it). The secret must not survive redact().
SHAPES = [
    (JWT, f"token {JWT} end"),
    ("fakebearervalue123", "Bearer fakebearervalue123"),
    ("fakeauthvalue456", "Authorization: fakeauthvalue456"),
    ("fakeauthbasic789", 'curl -H "Authorization: Basic fakeauthbasic789"'),
    ("hunter2pass", "see https://admin:hunter2pass@ha.example.com/api"),
    ("fakequerytoken1", "GET /x?token=fakequerytoken1&a=1"),
    ("fakequerykey22", "GET /x?a=1&key=fakequerykey22"),
    ("fakeaccess333", "GET /x?access_token=fakeaccess333"),
    ("fakepassword44", "POST /x?password=fakepassword44"),
    ("0123456789abcdef0123456789abcdef", "hex 0123456789abcdef0123456789abcdef"),
    ("QWxhZGRpbjpvcGVuIHNlc2FtZQ0123456789ABCD", "b64 QWxhZGRpbjpvcGVuIHNlc2FtZQ0123456789ABCD=="),
    ("sk-" + "f" * 24, "key sk-" + "f" * 24),
    ("ghp_" + "g" * 30, "gh ghp_" + "g" * 30),
    ("gho_" + "h" * 30, "gh gho_" + "h" * 30),
    ("github_pat_" + "i" * 30, "pat github_pat_" + "i" * 30),
    ("fakeapikeyvalue5", "TYPESAFE_API_KEY=fakeapikeyvalue5"),
    ("fakehasstoken66", 'export FENTON_HASS_TOKEN="fakehasstoken66"'),
    ("fakehasspass77", "FENTON_HASS_PASSWORD: fakehasspass77"),
]


class RedactTests(unittest.TestCase):
    def test_short_header_values_are_masked(self):
        for secret, text in (("sid1", "Set-Cookie: sid1"), ("a=b", "Set-Cookie: a=b; Path=/"), ("zq9", "Proxy-Authorization: zq9"),
                             ("abc12", "Proxy-Authorization: Basic abc12"), ("tk", "Bearer tk"), ("q", "authorization: Bearer q")):
            with self.subTest(text=text):
                out = redact.redact(text)
                self.assertNotIn(secret, out.replace("Basic", "").replace("Bearer", ""))
                self.assertIn("[redacted]", out)

    def test_both_layers_agree_on_key_names(self):
        for name in ("passWord", "PassWord", "pass_word", "pass-word", "session_id", "sessionId", "SessionID", "session-id",
                     "apiKey", "api-key", "API_KEY", "accessToken", "client_secret", "signingKey", "db_pwd", "pw"):
            with self.subTest(name=name):
                self.assertTrue(redact.is_secret_key(name))
                self.assertEqual(redact.redact_json({name: "valueone1"}), {name: "[redacted]"})
                self.assertNotIn("valueone1", redact.redact(f"{name}=valueone1"))
                self.assertNotIn("valueone1", redact.redact(f'{{"{name}": "valueone1"}}'))
        for name in ("monkey", "turkey", "a_session", "tokens", "title"):
            with self.subTest(name=name):
                self.assertFalse(redact.is_secret_key(name))

    def test_every_shape_is_masked(self):
        for secret, text in SHAPES:
            with self.subTest(secret=secret[:12]):
                out = redact.redact(text)
                self.assertNotIn(secret, out)
                self.assertIn("[redacted]", out)

    def test_ordinary_text_is_untouched(self):
        for text in ("tools/triage/prompts/worker.md changed", "x = y and key is unset", "build/handoff/topic.md",
                     "a_long_function_name_without_digits_in_it_at_all"):
            self.assertEqual(redact.redact(text), text)

    def test_redacted_json_stays_json(self):
        doc = json.dumps({"a": "TYPESAFE_API_KEY=fakeapikeyvalue5", "b": "Authorization: Bearer fakebearervalue123",
                          "c": f"https://u:pw@h/?token=zzzzzz&x=1 {JWT}"})
        data = json.loads(redact.redact(doc))
        self.assertNotIn("fakeapikeyvalue5", data["a"])
        self.assertIn("x=1", data["c"])

    def test_copy_redacted(self):
        with TemporaryDirectory() as tmp:
            src, dest = Path(tmp) / "a.md", Path(tmp) / "out" / "a.md"
            src.write_text("note " + JWT)
            redact.copy_redacted(src, dest)
            self.assertNotIn("eyJ", dest.read_text())


#: Fake secrets in many shapes, each a template taking the secret.
FORMS = [
    "Bearer {s}", "Authorization: Basic {s}", "password={s}", "token={s}", "key={s}", "secret={s}",
    "curl --data password={s}", "-d 'password={s}&u=x'", '-d "token={s}"', "tool --password {s}",
    "tool --token {s}", "mysql -u root -p {s}", "mysql --user=root -p {s}", '"password": "{s}"', "password: {s}",
    "api_key: {s}", "FENTON_HASS_TOKEN={s}", "sk-{s}{s}", "ghp_{s}{s}", "https://u:{s}@h.example.com/x",
]
SECRET = "Hunter2pwFake9"
PREFIXES = ["", "x\n", "x\t", "x\u00e9", '"', "'", "( ", "\\n"]


class AppCredentialTests(unittest.TestCase):
    """GitHub App tokens and PEM private-key blocks never leave a session (owner, 2026-11-04)."""

    PEM = ("-----BEGIN RSA PRIVATE KEY-----\nMIIEowIBAAKCAQEAfakefakefakefake\nQmFzZTY0Ym9keWxpbmUyMDEyMzQ1Njc4\n"
           "-----END RSA PRIVATE KEY-----")

    def test_each_token_type_is_masked(self):
        for token in ("ghs_" + "aB3" * 12, "ghu_" + "aB3" * 12, "gho_" + "aB3" * 12, "ghp_" + "aB3" * 12, "github_pat_" + "11AB" * 10):
            for text in (f"token {token} end", f"x\n{token}", f"GH_TOKEN={token}", f'{{"note": "got {token}"}}', f"({token})"):
                with self.subTest(text=text):
                    self.assertNotIn(token, redact.redact(text))
                    self.assertNotIn(token, redact.redact_lines(text))

    def test_pem_blocks_are_masked_whole(self):
        for kind in ("RSA PRIVATE KEY", "PRIVATE KEY", "EC PRIVATE KEY", "OPENSSH PRIVATE KEY", "ENCRYPTED PRIVATE KEY"):
            pem = self.PEM.replace("RSA PRIVATE KEY", kind)
            self.assertEqual(redact.redact(f"before\n{pem}\nafter"), "before\n[redacted]\nafter", kind)
        self.assertNotIn("MIIEow", redact.redact(self.PEM.replace("\n-----END RSA PRIVATE KEY-----", "")))  # cut off: masked to the end

    def test_pem_in_json_and_jsonl(self):
        out = redact.redact_lines(json.dumps({"text": f"key:\n{self.PEM}\nok"}))
        self.assertNotIn("MIIEow", out)
        self.assertNotIn("QmFzZTY0", out)
        json.loads(out)
        self.assertNotIn("MIIEow", redact.redact_file_text(json.dumps({"n": f"a {self.PEM}"}), ".json"))

    def test_multi_line_pem_in_logs_is_masked_whole(self):
        lines = ["".join(chr(65 + (i * 7 + j) % 26) if j % 5 else "+/"[j % 2] for j in range(64)) for i in range(25)]
        pem = "-----BEGIN RSA PRIVATE KEY-----\n" + "\n".join(lines) + "\n-----END RSA PRIVATE KEY-----"
        cut = pem.rsplit("\n", 1)[0]
        for eol in ("\n", "\r\n"):
            for text in (f"head\n{pem}\ntail", f"head\n{pem}", f"head\n{cut}\n"):  # whole, nothing after it, cut off before END
                text = text.replace("\n", eol)
                out = redact.redact_lines(text)
                for line in (lines[0], lines[3], lines[12], lines[24]):
                    self.assertNotIn(line, out, eol)
                self.assertTrue(out.startswith("head"))
        with TemporaryDirectory() as tmp:
            src = Path(tmp) / "w.log"
            src.write_text("a\r\n" + pem.replace("\n", "\r\n") + "\r\nb\n")
            dest = Path(tmp) / "out" / "w.log"
            redact.copy_redacted(src, dest)
            got = dest.read_text()
            self.assertNotIn(lines[10], got)
            self.assertIn("[redacted]", got)

    def test_public_key_blocks_and_prose_stay(self):
        text = "-----BEGIN PUBLIC KEY-----\nabc\n-----END PUBLIC KEY-----\nthe private key stays in github-apps"
        self.assertEqual(redact.redact(text), text)


class StructuralTests(unittest.TestCase):
    def test_forms_after_every_prefix_as_text_and_json(self):
        for form in FORMS:
            for prefix in PREFIXES:
                text = prefix + form.format(s=SECRET)
                with self.subTest(text=text):
                    self.assertNotIn(SECRET, redact.redact(text))
        for form in FORMS:
            for prefix in ("", "x\n", "x\t", "x\u00e9", "\n"):
                text = prefix + form.format(s=SECRET)
                doc = json.dumps({"summary": text, "n": [text, {"deep": text}]})
                for out in (redact.redact(doc), redact.redact_lines(doc), redact.redact_file_text(doc, ".json")):
                    with self.subTest(doc=doc):
                        data = json.loads(out)  # always valid JSON
                        self.assertNotIn(SECRET, json.dumps(data))
                        self.assertNotIn("]]", out)

    def test_long_run_after_escapes_keeps_json_valid(self):
        sha = "a1b2c3d4" * 5
        for esc in ("\n", "\t", "\u00e9"):
            doc = json.dumps({"summary": "Merged." + esc + sha})
            out = redact.redact(doc)
            self.assertNotIn(sha, out)
            json.loads(out)
        self.assertNotIn(sha, redact.redact_lines(json.dumps({"s": "x\n" + sha})))

    def test_secret_keys_are_masked_whole_whatever_the_type(self):
        obj = {"Password": "p", "api-key": 12345, "Token": {"a": ["b"]}, "authorization": None, "session": [1],
               "nest": [{"refresh_token": "rt", "cookie": "c", "ok": "plain", "FENTON_HASS_TOKEN": "t"}], "count": 3}
        out = redact.redact_json(obj)
        for key in ("Password", "api-key", "Token", "authorization", "session"):
            self.assertEqual(out[key], "[redacted]")
        self.assertEqual(out["nest"][0]["refresh_token"], "[redacted]")
        self.assertEqual(out["nest"][0]["cookie"], "[redacted]")
        self.assertEqual(out["nest"][0]["FENTON_HASS_TOKEN"], "[redacted]")
        self.assertEqual(out["nest"][0]["ok"], "plain")
        self.assertEqual(out["count"], 3)

    def test_other_strings_are_text_scrubbed(self):
        out = redact.redact_json({"note": "use token=" + SECRET + " now", "n": [f"Bearer {SECRET}"]})
        self.assertNotIn(SECRET, json.dumps(out))

    def test_masks_leave_no_stray_text(self):
        self.assertEqual(redact.redact("FENTON_HASS_TOKEN=" + JWT), "FENTON_HASS_TOKEN=[redacted]")
        self.assertEqual(redact.redact("FENTON_HASS_PASSWORD='p a s s' next"), "FENTON_HASS_PASSWORD='[redacted]' next")
        self.assertEqual(redact.redact('{"password": "abc def"}'), '{"password": "[redacted]"}')
        self.assertEqual(redact.redact("password=abc&u=1"), "password=[redacted]&u=1")
        once = redact.redact("token=" + SECRET)
        self.assertEqual(redact.redact(once), once)
        self.assertNotIn("]]", redact.redact("Authorization: Bearer " + SECRET))

    def test_ordinary_text_and_urls_unchanged(self):
        for text in ("key is unset", "the monkey=3 is fine", "tokens=3 used", "see https://example.com/a/b?x=1&y=2",
                     "git push origin main", "ssh -p 22 host", "mysql -p", "build/runs/label.digest", "Keyboard: ok",
                     "Merged.\\nNext step", "password reset flow works"):
            self.assertEqual(redact.redact(text), text)

    def test_copy_redacted_round_trip(self):
        sha = "a1b2c3d4" * 5
        record = {"summary": "Merged.\n" + sha, "password": "pw", "x": f"Bearer {SECRET}", "n": 1}
        with TemporaryDirectory() as tmp:
            base = Path(tmp)
            (base / "a.json").write_text(json.dumps(record))
            (base / "b.jsonl").write_text(json.dumps(record) + "\nnot json token=" + SECRET + "\n\n" + json.dumps(record))
            (base / "c.log").write_text(json.dumps(record) + "\nplain password=" + SECRET + "\n")
            (base / "bad.json").write_text('{"oops": "token=' + SECRET)
            for name in ("a.json", "b.jsonl", "c.log", "bad.json"):
                redact.copy_redacted(base / name, base / "out" / name)
                self.assertNotIn(SECRET, (base / "out" / name).read_text())
            data = json.loads((base / "out" / "a.json").read_text())
            self.assertEqual((data["password"], data["n"]), ("[redacted]", 1))
            self.assertNotIn(sha, json.dumps(data))
            lines = (base / "out" / "b.jsonl").read_text().split("\n")
            self.assertEqual(json.loads(lines[0])["n"], 1)
            self.assertEqual(lines[1], "not json token=[redacted]")
            self.assertEqual(lines[2], "")
            self.assertEqual(json.loads(lines[3])["password"], "[redacted]")
            json.loads((base / "out" / "c.log").read_text().split("\n")[0])


class DigestEvidenceTests(unittest.TestCase):
    def test_clip_masks_every_shape(self):
        for secret, text in SHAPES:
            self.assertNotIn(secret, retro_digest.clip(text))

    def test_no_secret_reaches_the_digest_file(self):
        secrets_text = " ".join(t for _, t in SHAPES)
        with TemporaryDirectory() as tmp:
            base = Path(tmp)
            (base / "tasks").mkdir()
            (base / "tasks" / "R-1.json").write_text(json.dumps({"id": "R-1", "brief": secrets_text, "level": "L1",
                                                                  "level_history": [{"from": "L0", "to": "L1", "reason": secrets_text}]}))
            (base / "status.json").write_text(json.dumps({"state": "blocked", "blocked_reason": secrets_text,
                                                          "summary": secrets_text, "owner_reply": secrets_text}))
            (base / "worker.log.tail").write_text(secrets_text + "\nHTTP 401 " + secrets_text + "\n")
            (base / "owner_replies.json").write_text(json.dumps([{"createdAt": "2030-01-01T00:00:00Z", "body": secrets_text}]))
            self.assertEqual(retro_digest.main(["--task", "R-1", "--archive", str(base), "--outcome", "blocked:blocked"]), 0)
            out = (base / "retro" / "R-1.json").read_text()
            for secret, _ in SHAPES:
                self.assertNotIn(secret, out)
            self.assertIn("blocked", out)


class BreakRedactTests(unittest.TestCase):
    """The reviewer's break script (fake secrets only) as a permanent regression test, plus the r3-1 key names."""

    S = "Hunter2pw"
    O = "opaqueTok12345"
    BJWT = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJmYWtlIn0.Zm9vYmFyYmF6cXV4"
    PREFIXES = {"start": "", "nl": "\n", "tab": "\t", "dq": '"', "sq": "'", "space": "x ", "esc_n": "\\n",
                "esc_t": "\\t", "paren": "(", "colon": "a:", "eq": "a="}

    def shapes(self):
        S, O, J = self.S, self.O, self.BJWT
        bs = "\\"
        return {
            "jwt": (J, J), "bearer": ("Bearer " + O, O), "bearer_lc": ("bearer " + O, O),
            "authz": ("Authorization: " + O, O), "authz_basic": ("Authorization: Basic " + O, O),
            "sk": ("sk-" + "a1" * 12, "a1" * 12), "ghp": ("ghp_" + "Ab3" * 7, "Ab3" * 7),
            "gho": ("gho_" + "Ab3" * 7, "Ab3" * 7), "pat": ("github_pat_" + "Ab3_" * 6, "Ab3_" * 6),
            "password=": ("password=" + S, S), "token=": ("token=" + S, S), "key=": ("key=" + S, S),
            "api_key=": ("api_key=" + S, S), "apikey=": ("apikey=" + S, S),
            "client_secret=": ("client_secret=" + S, S), "--password": ("--password " + S, S),
            "--password=": ("--password=" + S, S), "--token": ("--token " + S, S),
            "-u -p": ("-u user -p " + S, S), "-u -pX": ("-u user -p" + S, S),
            "json_pw": ('"password": "' + S + '"', S), "json_pw_nospace": ('"password":"' + S + '"', S),
            "esc_token": (bs + '"token' + bs + '":' + bs + '"' + S + bs + '"', S),
            "esc2_token": (bs * 3 + '"token' + bs * 3 + '":' + bs * 3 + '"' + S + bs * 3 + '"', S),
            "esc4_password": (bs * 7 + '"password' + bs * 7 + '": ' + bs * 7 + '"' + S + bs * 7 + '"', S),
            "yaml_pw": ("password: " + S, S), "yaml_token": ("token: " + S, S), "yaml_api_key": ("api_key: " + S, S),
            "env_tok": ("FENTON_HASS_TOKEN=" + S, S), "env_pw": ("FENTON_HASS_PASSWORD=" + S, S),
            "env_ts": ("TYPESAFE_API_KEY=" + S, S),
            "json_FHT": ('"FENTON_HASS_TOKEN": "' + S + '"', S), "json_refresh": ('"refresh_token": "' + S + '"', S),
            "export_tok": ("export FENTON_HASS_TOKEN=" + S, S),
            "env_pw_quoted": ("FENTON_HASS_PASSWORD='p a s s " + S + "'", S),
            "url_cred": ("https://user:" + S + "@host/x", S), "query": ("https://h/x?access_token=" + S + "&a=1", S),
            "cookie": ("Cookie: session=" + S, S), "curl_data": ("curl --data password=" + S, S),
            "curl_d_q": ("-d 'password=" + S + "&u=x'", S), "curl_d_dq": ('-d "token=' + S + '"', S),
            "hdr_xapi": ("X-Api-Key: " + S, S), "secret:": ("secret: " + S, S),
            "pw_eq_space": ("password = " + S, S), "PASSWORD": ("PASSWORD=" + S, S),
            "Password:": ("Password: " + S, S),
            # r3-1 names as text
            "accessToken=": ("accessToken=" + S, S), "refreshToken:": ("refreshToken: " + S, S),
            "secret_key=": ("secret_key=" + S, S), "private_key=": ("private_key=" + S, S),
            "privateKey=": ("privateKey=" + S, S), "passphrase=": ("passphrase=" + S, S),
            "pw=": ("pw=" + S, S), "pw:": ("pw: " + S, S),
            "json_accessToken": ('"accessToken": "' + S + '"', S), "json_pw_name": ('"pw":"' + S + '"', S),
            "json_refreshToken": ('"refreshToken":"' + S + '"', S), "json_secret_key": ('"secret_key": "' + S + '"', S),
            "json_private_key": ('"private_key":"' + S + '"', S), "json_passphrase": ('"passphrase":"' + S + '"', S),
            "esc_private_key": (bs + '"private_key' + bs + '":' + bs + '"' + S + bs + '"', S),
            "esc_accessToken": (bs + '"accessToken' + bs + '":' + bs + '"' + S + bs + '"', S),
        }

    def objects(self):
        S, O = self.S, self.O
        return [
            {"env": {"FENTON_HASS_TOKEN": S}}, {"a": [{"refresh_token": S}]}, {"password": S}, {"Token": S},
            {"x": {"api-key": S}}, {"client_secret": S}, {"hass_token": S}, {"access_token": S},
            {"FENTON_HASS_PASSWORD": S}, {"TYPESAFE_API_KEY": S}, {"headers": {"Authorization": "Bearer " + O}},
            {"headers": {"X-Api-Key": S}}, {"credentials": {"username": "u", "pw": S}}, {"secret_key": S},
            {"private_key": S}, {"apiKey": S}, {"accessToken": S}, {"refreshToken": S}, {"passphrase": S},
            {"login": {"password": S}}, {"cmd": "curl -H 'Authorization: Bearer " + O + "'"},
            {"content": "FENTON_HASS_TOKEN=" + S}, {"content": "\n\"password\": \"" + S + "\""},
            {"a": {"b": [{"accessToken": S}]}}, {"x": {"secret_key": S}}, {"pw": S}, {"AccessToken": S},
            {"client-secret": S}, {"Private Key": S},
            {"message": {"role": "assistant", "content": [
                {"type": "tool_use", "name": "Bash", "input": {"accessToken": S, "pw": S, "command": "ls"}}]}},
        ]

    def test_text_shapes_leave_no_secret_and_valid_json(self):
        for name, (shape, secret) in self.shapes().items():
            for pname, prefix in self.PREFIXES.items():
                text = "pre" + prefix + shape + " post" if pname != "start" else shape + " post"
                with self.subTest(shape=name, prefix=pname):
                    self.assertNotIn(secret, redact.redact(text))
                    dumped = json.dumps({"summary": text})
                    for out in (redact.redact(dumped), redact.redact_lines(dumped)):
                        self.assertNotIn(secret, out)
                        json.loads(out)

    def test_json_keys_in_every_container(self):
        for obj in self.objects():
            raw = json.dumps(obj)
            secret = self.S if self.S in raw else self.O
            for label, fn in (("lines", redact.redact_lines), ("json", lambda s: redact.redact_file_text(s, ".json")),
                              ("jsonl", lambda s: redact.redact_file_text(s + "\n" + s + "\n", ".jsonl")),
                              ("text", redact.redact)):
                with self.subTest(obj=obj, via=label):
                    out = fn(raw)
                    self.assertNotIn(secret, out)
                    if label == "json":
                        json.loads(out)
                    else:
                        for line in out.splitlines():
                            if line.strip():
                                json.loads(line)

    def test_stream_json_tool_use_line(self):
        line = json.dumps({"type": "assistant", "message": {"content": [
            {"type": "tool_use", "id": "t1", "name": "Bash",
             "input": {"accessToken": self.S, "refreshToken": self.S, "secret_key": self.S, "private_key": self.S,
                       "passphrase": self.S, "pw": self.S, "command": "ls"}}]}})
        out = redact.redact_lines(line + "\n" + line)
        self.assertNotIn(self.S, out)
        inp = json.loads(out.splitlines()[0])["message"]["content"][0]["input"]
        self.assertEqual(inp["command"], "ls")
        self.assertTrue(all(inp[k] == redact.MASK for k in inp if k != "command"))

    def test_key_names(self):
        for name in ("accessToken", "RefreshToken", "secret_key", "private_key", "privateKey", "passphrase", "pw",
                     "FENTON_HASS_TOKEN", "client_secret", "client-secret", "Api Key", "x-api-key", "sessionToken"):
            self.assertTrue(redact.is_secret_key(name), name)
        for name in ("command", "username", "path", "keyboard", "monkey", "tokens"):
            self.assertFalse(redact.is_secret_key(name), name)

    def test_copy_redacted_round_trips(self):
        S, O, J = self.S, self.O, self.BJWT
        data = {"msg": "done\n" + "a1b2" * 10, "token": S, "nested": {"FENTON_HASS_TOKEN": S, "refresh_token": S},
                "t": "x\nBearer " + O, "u": "\\n" + J}
        cases = [(".json", json.dumps(data, indent=2)), (".jsonl", "\n".join(json.dumps(data) for _ in range(3)) + "\n"),
                 (".log", "line password=" + S + "\n" + json.dumps(data) + "\nAuthorization: Bearer " + O
                  + "\n\t-u u -p " + S + "\n")]
        with TemporaryDirectory() as td:
            for suffix, content in cases:
                src, dst = Path(td) / ("in" + suffix), Path(td) / ("out" + suffix)
                src.write_text(content)
                redact.copy_redacted(src, dst)
                out = dst.read_text()
                for secret in (S, O, J):
                    self.assertNotIn(secret, out, suffix)
                if suffix == ".json":
                    json.loads(out)
                else:
                    for line in out.splitlines():
                        if line.startswith("{"):
                            json.loads(line)


if __name__ == "__main__":
    unittest.main()
