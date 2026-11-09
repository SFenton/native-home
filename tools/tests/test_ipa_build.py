"""tools/release/ios_ipa_build.sh: the signing probe and the unstamped-build guard, with stubbed security and codesign."""

import os
import signal
import time
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "release" / "ios_ipa_build.sh"
DEV_SHA = "B" * 40
DEV_IDENTITY = '  2) ' + DEV_SHA + ' "Apple Development: someone@example.com (ABCDE12345)"\n'
OTHER_SHA = "C" * 40
OTHER_IDENTITY = '  3) ' + OTHER_SHA + ' "Apple Development: other@example.com (OTHERTEAM1)"\n'
CERTS = {}
IDENTITY = '  1) A9A5DD4B55B47AD4B5BDB309C549A3AC91533A24 "Apple Distribution: Alex Demo (3Q9X8JX23S)"\n'


class SigningProbeTests(unittest.TestCase):
    def cert(self, ou):
        if ou not in CERTS:
            d = tempfile.mkdtemp()
            subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1", "-keyout", d + "/k",
                            "-out", d + "/c", "-subj", "/OU=%s/CN=test" % ou], capture_output=True, check=True)
            CERTS[ou] = Path(d + "/c").read_text()
        return CERTS[ou]

    def run_probe(self, codesign_body, identities=IDENTITY, timeout="1", args=("--probe-signing",)):
        with tempfile.TemporaryDirectory() as tmp:
            bin_dir = Path(tmp) / "bin"
            bin_dir.mkdir()
            (bin_dir / "team.pem").write_text(self.cert("3Q9X8JX23S"))
            (bin_dir / "other.pem").write_text(self.cert("OTHERTEAM1"))
            # Like `security find-certificate -a -Z -p`: SHA-256 line first, then SHA-1, lowercase here (the script compares case-insensitively).
            blocks = "".join("SHA-256 hash: %s\nSHA-1 hash: %s\n%s" % ("9F" * 32, sha.lower(), (bin_dir / pem).read_text())
                             for sha, pem in ((DEV_SHA, "team.pem"), (OTHER_SHA, "other.pem")))
            (bin_dir / "all.txt").write_text(blocks)
            (bin_dir / "security").write_text(
                "#!/bin/sh\ncase \"$1\" in find-identity) printf '%s' '" + identities + "';;\n"
                "find-certificate) case \"$*\" in *' -a -Z -p'*) cat \"" + str(bin_dir) + "/all.txt\";; *) exit 1;; esac;; esac\n")
            (bin_dir / "codesign").write_text("#!/bin/sh\n" + codesign_body + "\n")
            for stub in bin_dir.iterdir():
                stub.chmod(0o755)
            env = dict(os.environ, PATH="%s:%s" % (bin_dir, os.environ["PATH"]), FENTON_SIGN_PROBE_TIMEOUT=timeout,
                       CODESIGN_BIN=str(bin_dir / "codesign"))
            return subprocess.run(["bash", str(SCRIPT), *args], env=env, capture_output=True, text=True, timeout=60)

    def test_working_codesign_passes(self):
        proc = self.run_probe("exit 0")
        self.assertEqual((proc.returncode, proc.stdout.strip()), (0, "signing ok"), proc.stderr)

    def test_a_prompt_that_never_returns_is_blocked_by_the_timeout(self):
        proc = self.run_probe("sleep 30")
        self.assertEqual(proc.returncode, 4)
        self.assertIn("BLOCKED", proc.stderr)
        self.assertIn("set-key-partition-list", proc.stderr)
        self.assertIn("waited for a prompt", proc.stderr)

    def test_a_failing_codesign_is_blocked(self):
        proc = self.run_probe("exit 1")
        self.assertEqual(proc.returncode, 4)
        self.assertIn("failed", proc.stderr)

    def test_a_failing_versioning_stops_the_build_instead_of_stamping_nothing(self):
        proc = self.run_probe("exit 0", args=("ios/v0000.00.00", "1"))
        self.assertEqual(proc.returncode, 1, proc.stderr)
        self.assertIn("refusing to build an unstamped IPA", proc.stderr)

    def test_a_hanging_development_identity_is_blocked(self):
        proc = self.run_probe('case "$*" in *%s*) sleep 30;; esac' % DEV_SHA, identities=IDENTITY + DEV_IDENTITY)
        self.assertEqual(proc.returncode, 4)
        self.assertIn("Apple Development identity", proc.stderr)
        self.assertIn("set-key-partition-list", proc.stderr)

    def test_a_working_development_identity_passes(self):
        proc = self.run_probe("exit 0", identities=IDENTITY + DEV_IDENTITY)
        self.assertEqual(proc.returncode, 0, proc.stderr)

    def test_another_teams_development_key_cannot_block_the_release(self):
        proc = self.run_probe('case "$*" in *%s*) sleep 30;; esac' % OTHER_SHA, identities=IDENTITY + OTHER_IDENTITY)
        self.assertEqual(proc.returncode, 0, proc.stderr)

    def test_a_skipped_identity_is_logged_by_name_and_reason(self):
        unknown = "D" * 40
        ident = '  4) ' + unknown + ' "Apple Development: ghost@example.com (GHOST00000)"\n'
        proc = self.run_probe("exit 0", identities=IDENTITY + OTHER_IDENTITY + ident)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("skipping Apple Development identity Apple Development: other@example.com", proc.stderr)
        self.assertIn("not for team", proc.stderr)
        self.assertIn("ghost@example.com", proc.stderr)
        self.assertIn("no keychain certificate with this SHA-1", proc.stderr)
        self.assertNotIn("PRIVATE KEY", proc.stderr)

    def test_bad_timeouts_are_refused(self):
        for value in ("0", "-3", "abc", ""):
            with self.subTest(value=value):
                proc = self.run_probe("exit 0", timeout=value)
                self.assertEqual(proc.returncode, 2)
                self.assertIn("positive integer", proc.stderr)

    def test_an_output_directory_outside_build_and_tmp_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = dict(os.environ, FENTON_IPA_OUT="/usr/local/not-mine", TMPDIR=tmp)
            proc = subprocess.run(["bash", str(SCRIPT), "ios/v2610.29.01", "1", "--dry-run"], env=env, capture_output=True, text=True, timeout=60)
        self.assertEqual(proc.returncode, 2)
        self.assertIn("FENTON_IPA_OUT", proc.stderr)

    def test_no_distribution_identity_is_blocked(self):
        proc = self.run_probe("exit 0", identities="  1) ABC \"Apple Development: Someone (XYZ)\"\n")
        self.assertEqual(proc.returncode, 4)
        self.assertIn("no 'Apple Distribution' identity", proc.stderr)


class ArchiveWatchdogTests(unittest.TestCase):
    """A full (non-dry) run with stubbed xcodebuild, xcodegen, devcap and versioning: no real signing happens."""

    def run_build(self, xcodebuild_body):
        proc = self.start_build(xcodebuild_body)
        out, err = proc.communicate(timeout=60)
        return subprocess.CompletedProcess(proc.args, proc.returncode, out, err)

    def start_build(self, xcodebuild_body):
        if True:
            tmp = tempfile.mkdtemp()
            self.addCleanup(lambda: __import__("shutil").rmtree(tmp, ignore_errors=True))
            bin_dir = Path(tmp) / "bin"
            bin_dir.mkdir()
            stubs = {
                "security": "printf '%s' '" + IDENTITY + "'",
                "codesign": "exit 0",
                "xcodegen": "exit 0",
                "xcodebuild": xcodebuild_body,
            }
            for name, body in stubs.items():
                (bin_dir / name).write_text("#!/bin/sh\n" + body + "\n")
                (bin_dir / name).chmod(0o755)
            (bin_dir / "devcap.py").write_text("import subprocess, sys\nsys.exit(subprocess.call(sys.argv[sys.argv.index('--') + 1:]))\n")
            (bin_dir / "versioning.py").write_text("print('MARKETING_VERSION=1\\nCURRENT_PROJECT_VERSION=2\\nHASS_GIT_SHA=abc')\n")
            env = dict(os.environ, PATH="%s:%s" % (bin_dir, os.environ["PATH"]), FENTON_IDLE_TIMEOUT_SECONDS="2", FENTON_IPA_TEST="1",
                       CODESIGN_BIN=str(bin_dir / "codesign"), FENTON_DEVCAP=str(bin_dir / "devcap.py"),
                       FENTON_VERSIONING=str(bin_dir / "versioning.py"), FENTON_IPA_OUT=str(Path(tmp) / "out"))
            return subprocess.Popen(["bash", str(SCRIPT), "ios/v2610.29.01", "1"], env=env, stdout=subprocess.PIPE,
                                    stderr=subprocess.PIPE, text=True, start_new_session=True)

    def test_test_seams_are_ignored_without_the_test_flag(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = dict(os.environ, FENTON_VERSIONING="/nonexistent/versioning.py", FENTON_IPA_OUT=str(Path(tmp) / "out"),
                       PATH=tmp + ":" + os.environ["PATH"])
            (Path(tmp) / "security").write_text("#!/bin/sh\nexit 0\n")
            (Path(tmp) / "security").chmod(0o755)
            proc = subprocess.run(["bash", str(SCRIPT), "ios/v2610.29.01", "1"], env=env, capture_output=True, text=True, timeout=60)
        self.assertEqual(proc.returncode, 4)  # stopped at the missing identity, not at the bogus override

    def test_a_signal_to_the_watchdog_group_takes_xcodebuild_down_with_it(self):
        with tempfile.TemporaryDirectory() as tmp:
            pidfile = Path(tmp) / "xcb.pid"
            body = 'echo $$ > %s; exec sleep 60' % pidfile
            proc = self.start_build(body)
            for _ in range(100):
                if pidfile.exists() and pidfile.read_text().strip():
                    break
                time.sleep(0.1)
            pid = int(pidfile.read_text())
            os.killpg(proc.pid, signal.SIGTERM)  # what devcap does on a hold overrun: only the watchdog's group
            proc.wait(timeout=30)
            for _ in range(80):
                try:
                    os.kill(pid, 0)
                except ProcessLookupError:
                    break
                time.sleep(0.1)
            else:
                os.kill(pid, signal.SIGKILL)
                self.fail("xcodebuild survived the watchdog being signalled")

    def test_a_finished_build_with_a_lingering_helper_is_not_blocked(self):
        proc = self.run_build('case "$*" in *exportArchive*) exit 1;; *) (sleep 20 &) ; echo done;; esac')
        self.assertEqual(proc.returncode, 1, proc.stderr)
        self.assertNotIn("BLOCKED", proc.stderr)
        self.assertIn("export failed", proc.stderr)

    def test_a_silent_archive_is_killed_and_blocked(self):
        proc = self.run_build("sleep 30")
        self.assertEqual(proc.returncode, 4, proc.stderr)
        self.assertIn("BLOCKED", proc.stderr)
        self.assertIn("xcodebuild archive printed nothing", proc.stderr)
        self.assertIn("set-key-partition-list", proc.stderr)

    def test_a_silent_export_is_killed_and_blocked(self):
        proc = self.run_build('case "$*" in *exportArchive*) sleep 30;; *) echo archiving;; esac')
        self.assertEqual(proc.returncode, 4, proc.stderr)
        self.assertIn("xcodebuild -exportArchive printed nothing", proc.stderr)

    def test_a_chatty_slow_archive_is_not_killed(self):
        proc = self.run_build('case "$*" in *exportArchive*) exit 1;; *) for i in 1 2 3; do echo tick; sleep 1; done;; esac')
        self.assertEqual(proc.returncode, 1, proc.stderr)
        self.assertNotIn("BLOCKED", proc.stderr)
        self.assertIn("export failed", proc.stderr)


if __name__ == "__main__":
    unittest.main()
