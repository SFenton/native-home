"""``tools/hass_creds.sh``: the in-process live-server credential loader. Fake values and temp files only."""

import os
import shutil
import subprocess
import tempfile
import sys
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
LOADER = REPO / "tools" / "hass_creds.sh"
KEYS = ["FENTON_HASS_TOKEN", "FENTON_HASS_USERNAME", "FENTON_HASS_PASSWORD", "FENTON_HASS_SERVER"]
FAKE = {"FENTON_HASS_TOKEN": "tok-fake-111", "FENTON_HASS_USERNAME": "user-fake-222",
        "FENTON_HASS_PASSWORD": "pw-fake-333", "FENTON_HASS_SERVER": "http://fake.invalid:8123"}


def load(creds_file, extra_env=None, body='for k in %s; do echo "$k=${!k:-}"; done' % " ".join(KEYS)):
    """Sources the loader in a fresh bash with a scrubbed environment; returns (rc, stdout, stderr)."""
    env = {k: v for k, v in os.environ.items() if not k.startswith("FENTON_HASS")}
    env["FENTON_HASS_CREDS_FILE"] = str(creds_file)
    env.update(extra_env or {})
    script = f'source "{LOADER}"; hass_load_creds; rc=$?; {body}; exit $rc'
    p = subprocess.run(["bash", "-c", script], env=env, capture_output=True, text=True)
    return p.returncode, p.stdout, p.stderr


def values(stdout):
    return dict(line.split("=", 1) for line in stdout.splitlines() if "=" in line)


class LoaderTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.file = self.tmp / "env"

    def write(self, text, mode=0o600):
        self.file.write_text(text)
        self.file.chmod(mode)

    @unittest.skipUnless(sys.platform == "darwin", "Linux baseline: the loader's owner and mode checks fail on /tmp files (macOS-tested); follow-up hosted-ci-linux-portability")
    def test_loads_the_four_keys_with_and_without_export_and_quotes(self):
        self.write('export FENTON_HASS_TOKEN="tok-fake-111"\nFENTON_HASS_USERNAME=user-fake-222\n'
                   "  export FENTON_HASS_PASSWORD='pw-fake-333'\nFENTON_HASS_SERVER=http://fake.invalid:8123\n")
        rc, out, _ = load(self.file)
        self.assertEqual(rc, 0)
        self.assertEqual(values(out), FAKE)

    @unittest.skipUnless(sys.platform == "darwin", "Linux baseline: the loader's owner and mode checks fail on /tmp files (macOS-tested); follow-up hosted-ci-linux-portability")
    def test_environment_wins_over_the_file(self):
        self.write("FENTON_HASS_USERNAME=from-file\nFENTON_HASS_PASSWORD=pw-file\n")
        rc, out, _ = load(self.file, {"FENTON_HASS_USERNAME": "from-env"})
        self.assertEqual(rc, 0)
        got = values(out)
        self.assertEqual(got["FENTON_HASS_USERNAME"], "from-env")
        self.assertEqual(got["FENTON_HASS_PASSWORD"], "pw-file")

    @unittest.skipUnless(sys.platform == "darwin", "Linux baseline: the loader's owner and mode checks fail on /tmp files (macOS-tested); follow-up hosted-ci-linux-portability")
    def test_mode_644_is_refused(self):
        self.write("FENTON_HASS_PASSWORD=pw-fake-333\n", 0o644)
        rc, out, err = load(self.file)
        self.assertNotEqual(rc, 0)
        self.assertEqual(values(out)["FENTON_HASS_PASSWORD"], "")
        self.assertIn("mode", err)

    def test_group_readable_is_refused(self):
        self.write("FENTON_HASS_PASSWORD=pw-fake-333\n", 0o640)
        self.assertNotEqual(load(self.file)[0], 0)

    @unittest.skipUnless(sys.platform == "darwin", "Linux baseline: the loader's owner and mode checks fail on /tmp files (macOS-tested); follow-up hosted-ci-linux-portability")
    def test_a_path_inside_the_repo_is_refused(self):
        inside = Path(tempfile.mkdtemp(dir=REPO))
        self.addCleanup(shutil.rmtree, inside, ignore_errors=True)
        f = inside / "env"
        f.write_text("FENTON_HASS_PASSWORD=pw-fake-333\n")
        f.chmod(0o600)
        rc, out, err = load(f)
        self.assertNotEqual(rc, 0)
        self.assertEqual(values(out)["FENTON_HASS_PASSWORD"], "")
        self.assertIn("git repository", err)

    @unittest.skipUnless(sys.platform == "darwin", "Linux baseline: the loader's owner and mode checks fail on /tmp files (macOS-tested); follow-up hosted-ci-linux-portability")
    def test_only_allowlisted_keys_are_loaded(self):
        self.write("PATH=/nowhere\nFENTON_EXTRA=1\nUSERNAME=legacy\nPASSWORD=legacy\nFENTON_HASS_TOKEN=tok-fake-111\n")
        rc, out, _ = load(self.file, body='echo "path=$PATH"; echo "extra=${FENTON_EXTRA:-}"; echo "legacy=${PASSWORD:-}"; '
                                          'echo "token=$FENTON_HASS_TOKEN"')
        self.assertEqual(rc, 0)
        got = values(out)
        self.assertNotEqual(got["path"], "/nowhere")
        self.assertEqual((got["extra"], got["legacy"], got["token"]), ("", "", "tok-fake-111"))

    @unittest.skipUnless(sys.platform == "darwin", "Linux baseline: the loader's owner and mode checks fail on /tmp files (macOS-tested); follow-up hosted-ci-linux-portability")
    def test_command_substitution_is_not_executed(self):
        marker = self.tmp / "ran"
        self.write(f"FENTON_HASS_PASSWORD=$(touch {marker})\nFENTON_HASS_TOKEN=`touch {marker}`\n")
        rc, out, _ = load(self.file)
        self.assertEqual(rc, 0)
        self.assertFalse(marker.exists())
        self.assertEqual(values(out)["FENTON_HASS_PASSWORD"], f"$(touch {marker})")

    @unittest.skipUnless(sys.platform == "darwin", "Linux baseline: the loader's owner and mode checks fail on /tmp files (macOS-tested); follow-up hosted-ci-linux-portability")
    def test_no_value_appears_in_stdout_or_stderr(self):
        self.write("".join(f"{k}={v}\n" for k, v in FAKE.items()))
        rc, out, err = load(self.file, body="hass_creds_status")
        self.assertEqual(rc, 0)
        for v in FAKE.values():
            self.assertNotIn(v, out + err)
        self.assertIn("FENTON_HASS_PASSWORD: yes", out)
        # a refusal names the file, never a value
        self.file.chmod(0o644)
        _, out, err = load(self.file, body="hass_creds_status")
        for v in FAKE.values():
            self.assertNotIn(v, out + err)

    def test_xtrace_never_shows_a_value(self):
        self.write("".join(f"{k}={v}\n" for k, v in FAKE.items()))
        env = {k: v for k, v in os.environ.items() if not k.startswith("FENTON_HASS")}
        env["FENTON_HASS_CREDS_FILE"] = str(self.file)
        p = subprocess.run(["bash", "-x", "-c", f'source "{LOADER}"; hass_load_creds; hass_require_creds; hass_use_env_arg shell; case "$-" in *x*) echo still-tracing;; esac'],
                           env=env, capture_output=True, text=True)
        self.assertEqual(p.returncode, 0)
        self.assertIn("still-tracing", p.stdout)
        for v in FAKE.values():
            self.assertNotIn(v, p.stdout + p.stderr)

    @unittest.skipUnless(sys.platform == "darwin", "Linux baseline: the loader's owner and mode checks fail on /tmp files (macOS-tested); follow-up hosted-ci-linux-portability")
    def test_writable_parent_folder_is_refused(self):
        self.write("FENTON_HASS_PASSWORD=pw-fake-333\n")
        self.tmp.chmod(0o770)
        rc, out, err = load(self.file)
        self.assertNotEqual(rc, 0)
        self.assertEqual(values(out)["FENTON_HASS_PASSWORD"], "")
        self.assertIn("writable", err)

    @unittest.skipUnless(sys.platform == "darwin", "Linux baseline: the loader's owner and mode checks fail on /tmp files (macOS-tested); follow-up hosted-ci-linux-portability")
    def test_require_creds_needs_a_token_or_password(self):
        self.write("FENTON_HASS_USERNAME=user-fake-222\n")
        rc, _, err = load(self.file, body="hass_require_creds || exit 1")
        self.assertNotEqual(rc, 0)
        self.assertIn("neither", err)
        self.write("FENTON_HASS_PASSWORD=pw-fake-333\nFENTON_HASS_SERVER=http://fake.invalid:8123\n")
        rc, _, err = load(self.file, body="hass_require_creds || exit 1")
        self.assertEqual(rc, 0)
        self.assertNotIn("pw-fake-333", err)

    @unittest.skipUnless(sys.platform == "darwin", "Linux baseline: the loader's owner and mode checks fail on /tmp files (macOS-tested); follow-up hosted-ci-linux-portability")
    def test_require_creds_needs_the_server(self):
        """Fails if: hass_require_creds passes with a token or password but no FENTON_HASS_SERVER, or prints a value."""
        for key, val in (("FENTON_HASS_TOKEN", "tok-fake-111"), ("FENTON_HASS_PASSWORD", "pw-fake-333")):
            self.write(f"{key}={val}\n")
            rc, out, err = load(self.file, body="hass_require_creds || exit 1")
            self.assertNotEqual(rc, 0)
            self.assertIn("FENTON_HASS_SERVER is not set", err)
            self.assertIn("devices.md", err)
            self.assertNotIn(val, out + err)
            self.write(f"{key}={val}\nFENTON_HASS_SERVER=http://fake.invalid:8123\n")
            rc, out, err = load(self.file, body="hass_require_creds || exit 1")
            self.assertEqual(rc, 0, err)
            self.assertNotIn("fake.invalid", out + err)

    def test_nightly_never_ignores_a_failed_credentials_load(self):
        # The hosted nightly runs Gate only and loads no credentials; the live lane adds them and must fail the shard when they are missing.
        text = (REPO / ".github" / "workflows" / "nightly.yml").read_text()
        self.assertNotIn("hass_load_creds || true", text)
        if "hass_load_creds" in text:
            self.assertIn("hass_require_creds", text)

    def test_missing_file_is_not_an_error(self):
        rc, out, _ = load(self.tmp / "absent")
        self.assertEqual(rc, 0)
        self.assertTrue(all(v == "" for v in values(out).values()))

    def test_env_file_option_other_than_shell_is_rejected(self):
        env = {k: v for k, v in os.environ.items() if not k.startswith("FENTON_HASS")}
        p = subprocess.run(["bash", "-c", f'source "{LOADER}"; hass_use_env_arg ./temp.env'], env=env, capture_output=True, text=True)
        self.assertEqual(p.returncode, 2)
        self.assertIn("only 'shell'", p.stderr)


class ScriptTests(unittest.TestCase):
    SCRIPTS = ["ios_uitest", "ios_perf", "ios_navperf", "ios_scrollcost", "ios_launchperf"]

    def test_scripts_parse_and_use_the_loader_not_source(self):
        for name in self.SCRIPTS:
            path = REPO / "tools" / f"{name}.sh"
            self.assertEqual(subprocess.run(["bash", "-n", str(path)]).returncode, 0, name)
            text = path.read_text()
            self.assertIn("hass_use_env_arg", text, name)
            self.assertNotIn('source "$ENV_FILE"', text, name)

    def test_ios_uitest_refuses_an_env_file(self):
        p = subprocess.run(["bash", str(REPO / "tools" / "ios_uitest.sh"), "--env", "./temp.env"], capture_output=True, text=True,
                           env={**os.environ, "FENTON_UITEST_PRINT_HOLD": "1"})
        self.assertEqual(p.returncode, 2)
        self.assertIn("only 'shell'", p.stderr)


if __name__ == "__main__":
    unittest.main()
