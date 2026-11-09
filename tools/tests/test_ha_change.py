"""Tests for tools/ha_change.py with a fake ssh runner: no live Home Assistant call."""
from __future__ import annotations

import contextlib
import io
import json
import re
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import ha_change as hc  # noqa: E402


class FakeSsh:
    def __init__(self, check_ok=True, files=None, fail=(), dirs=(), fail_after_writes=None, unreadable=(), check_seq=(),
                 fail_restore=False):
        self.calls, self.files, self.check_ok, self.fail = [], dict(files or {}), check_ok, fail
        self.sigs = {d: "100 1" for d in dirs}  # custom_components directory -> its checksum
        self.writes, self.fail_after_writes, self.unreadable = 0, fail_after_writes, unreadable
        self.after_download = []  # directories the HACS download creates
        self.modify_on_download = []  # existing directories the HACS download changes
        self.tar_fails = False
        # HACS 2.x semantics: HACS keeps its own cached available_version, which only a refresh command moves to GitHub's truth
        self.repos = {"1": {"id": "1", "full_name": "a/b", "available_version": "old2222", "installed_version": "old1111", "installed": True},
                      "2": {"id": "2", "full_name": "SFenton/ha-fenton-push", "available_version": "old2222",
                            "installed_version": "old1111", "installed": True}}
        self.github = {"a/b": "abc1234", "SFenton/ha-fenton-push": "abc1234"}  # GitHub head (short sha) per repo
        self.releases = {}  # repo -> latest release tag
        self.ws_error = None  # HACS error text for the download command
        self.download_noop = False  # a download that "succeeds" but leaves the old version installed
        self.ws_seen, self.ws_msgs, self.sent_versions = [], [], []
        self.entry_state = "loaded"  # state of the fenton_home config entry
        self.github_ids = {}  # repo name on GitHub -> numeric repo id (HACS's own id); absent means gh cannot read it
        self.tars, self.listing_fails, self.no_components_dir, self.fail_restore, self.check_seq = [], False, False, fail_restore, list(check_seq)

    def ws(self, msg):
        """The HACS websocket commands: list, refresh (moves available to GitHub's truth) and download (installs available)."""
        repos = self.repos
        if msg["type"] == "config_entries/get":
            return [{"domain": msg["domain"], "state": self.entry_state}]
        if msg["type"] == "hacs/repositories/list":
            return [dict(r) for r in repos.values()]
        repo = repos[msg["repository"]]
        if msg["type"] == "hacs/repository/refresh":
            repo["available_version"] = self.releases.get(repo["full_name"]) or self.github[repo["full_name"]]
        elif msg["type"] == "hacs/repository/download" and not self.ws_error:
            sent = msg.get("version")
            self.sent_versions.append(sent)
            if sent == "main":  # HACS's own UI path: the default branch installs the head commit; installed commit = head
                sent = self.github[repo["full_name"]]
            elif sent and sent != self.releases.get(repo["full_name"]) and not re.fullmatch(r"[0-9a-f]{40}", sent):
                # HACS 2.0.5: archive/refs/tags|heads/<short sha>.zip both 404; the download is refused here
                self.ws_error = "Failed to download zipball"; return {}
            if not self.download_noop:
                repo["installed_version"], repo["installed"] = sent or repo["available_version"], True
            # the HA update entity is on while installed != available (AwesomeVersion compare, update/__init__.py:361-368)
            repo["update_on"] = repo["installed_version"] != repo["available_version"]
            for name in self.after_download:
                self.sigs[name] = "200 2"
            for name in self.modify_on_download:
                self.sigs[name] = "300 3"
        return {}

    @property
    def dirs(self):
        return list(self.sigs)

    def __call__(self, args, input=None, timeout=900):
        cmd = args[-1]
        if args[0] == "gh":  # local GitHub read: the truth HACS is compared with
            repo = args[2].split("/")[1] + "/" + args[2].split("/")[2]
            if args[-1] == ".default_branch":
                return subprocess.CompletedProcess(args, 0, "main\n", "")
            if args[-1] == ".id":
                gid = self.github_ids.get(repo)
                return subprocess.CompletedProcess(args, 0 if gid else 1, (gid or "") + "\n", "" if gid else "Not Found")
            if "releases/latest" in args[2]:
                tag = self.releases.get(repo)
                return subprocess.CompletedProcess(args, 0 if tag else 1, (tag or "") + "\n", "")
            return subprocess.CompletedProcess(args, 0, self.github[repo] + "0" * 33 + "\n", "")
        self.calls.append((cmd, input))
        rc, out = 0, ""
        if cmd.startswith("if [ -e ") and any(u in cmd for u in self.unreadable):
            rc, out = 255, "ssh: connection reset"
        elif cmd.startswith("if [ -e "):
            path = cmd.split()[3].strip("'")
            rc, out = (0, self.files[path]) if path in self.files else (3, "")
        elif cmd.startswith("if [ -d ") and "cksum" in cmd:
            if self.listing_fails:
                rc, out = 255, "ssh: connection reset"
            elif self.no_components_dir:
                rc = 3
            else:
                out = "\n".join(f"{name} {sig}" for name, sig in self.sigs.items())
        elif cmd.startswith("mkdir -p /root/ha-changes") and self.tar_fails:
            rc, out = 2, "tar: no space left"
        elif cmd.startswith("mkdir -p /root/ha-changes"):
            self.tars.append(dict(self.sigs))
        elif cmd.startswith("rm -rf /config/custom_components/") and " && tar " in cmd:
            name = cmd.split("custom_components/")[1].split()[0].strip("'")
            if self.fail_restore:
                rc, out = 1, "tar: boom"
            else:
                self.sigs[name] = self.tars[-1][name]
        elif cmd.startswith("rm -rf /config/custom_components/"):
            self.sigs.pop(cmd.rsplit("/", 1)[1].strip("'"), None)
        elif cmd.startswith("rm -f ") and any(f in cmd for f in self.fail):
            rc, out = 1, "boom"
        elif cmd.startswith("rm -f "):
            self.files.pop(cmd.split()[2].strip("'"), None)
        elif cmd.startswith("python3 - "):
            import shlex as _shlex
            msg = json.loads(_shlex.split(cmd)[2])
            self.ws_seen.append(msg["type"])
            self.ws_msgs.append(msg)
            out = json.dumps({"success": True, "result": self.ws(msg), "error": ""})
            if msg["type"] == "hacs/repository/download" and self.ws_error:
                out = json.dumps({"success": False, "result": None, "error": "error: " + self.ws_error})
        elif self.fail_after_writes is not None and cmd.startswith("mkdir -p") and self.writes >= self.fail_after_writes:
            rc, out = 1, "boom"
        elif any(f in cmd for f in self.fail):
            rc, out = 1, "boom"
        elif cmd.startswith("ha backups new"):
            out = json.dumps({"result": "ok", "data": {"slug": "abcd1234"}})
        elif cmd == "ha core check":
            ok = self.check_seq.pop(0) if self.check_seq else self.check_ok
            rc, out = (0, "Command completed successfully.") if ok else (1, "Error: invalid config")
        elif cmd.startswith("mkdir -p") and " cat > " in cmd:
            self.writes += 1
            self.files[cmd.split("cat > ")[1].strip("'")] = input
        elif cmd.startswith("cat > "):
            self.files[cmd.split()[2].strip("'")] = input
        elif cmd.startswith("cat "):
            path = cmd.split()[1].strip("'")
            rc, out = (0, self.files[path]) if path in self.files else (1, "")
        return subprocess.CompletedProcess(args, rc, out, "")


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)
        self.log = self.dir / "log" / "ha.jsonl"
        self.msgs = []
        subprocess.run(["git", "init", "-q", str(self.dir)], check=True)  # git_ignored fails closed outside a repository

    def make(self, ssh):
        return hc.HaChange(run=ssh, log_path=self.log, now=lambda: 1700000000, out=self.msgs.append, roots=[self.dir])

    def local(self, name, text):
        p = self.dir / name
        p.write_text(text)
        return str(p)

    def entries(self):
        return [json.loads(x) for x in self.log.read_text().splitlines()]

    def cmds(self, ssh):
        return [c for c, _ in ssh.calls]


class PathTests(unittest.TestCase):
    def test_refuses_secrets_storage_escape_and_outside(self):
        for bad in ("secrets.yaml", "/config/.storage/auth", "/config/../etc/passwd", "/etc/passwd", "/config/x.bak",
                    "/config/deps/a", "/config"):
            with self.assertRaises(hc.ChangeError, msg=bad):
                hc.clean_remote(bad)

    def test_relative_paths_land_in_config(self):
        self.assertEqual(hc.clean_remote("packages/a.yaml"), "/config/packages/a.yaml")

    def test_reload_mapping(self):
        self.assertEqual(hc.reload_for(["/config/automations.yaml"]), [("automation", "reload")])
        self.assertEqual(hc.reload_for(["/config/packages/x.yaml"]), [hc.RELOAD_ALL])
        self.assertIsNone(hc.reload_for(["/config/configuration.yaml"]))
        self.assertIsNone(hc.reload_for(["/config/automations.yaml", "/config/custom_components/a/x.py"]))


class BackupCheckTests(Base):
    def test_backup_prints_slug_and_rejects_odd_names(self):
        ssh = FakeSsh()
        self.assertEqual(self.make(ssh).backup("pre change"), "abcd1234")
        with self.assertRaises(hc.ChangeError):
            self.make(ssh).backup("a; rm -rf /")

    def test_backup_without_slug_stops(self):
        def bad(args, input=None, timeout=900):
            return subprocess.CompletedProcess(args, 0, "{}", "")
        with self.assertRaises(hc.ChangeError):
            self.make(bad).backup("x")

    def test_check_fails_on_error(self):
        with self.assertRaises(hc.ChangeError):
            self.make(FakeSsh(check_ok=False)).check()
        self.make(FakeSsh()).check()


class ApplyTests(Base):
    def test_apply_backs_up_writes_checks_then_reloads(self):
        ssh = FakeSsh(files={"/config/automations.yaml": "old"})
        lf = self.local("a.yaml", "- alias: x\n")
        slug = self.make(ssh).apply([f"{lf}:automations.yaml"], "add x")
        self.assertEqual(slug, "abcd1234")
        cmds = self.cmds(ssh)
        order = [next(i for i, c in enumerate(cmds) if m in c)
                 for m in ("ha backups new", "cat > ", "ha core check", "automation/reload")]
        self.assertEqual(order, sorted(order))
        self.assertEqual(ssh.files["/config/automations.yaml"], "- alias: x\n")
        self.assertNotIn("ha core restart", cmds)
        e = self.entries()[-1]
        self.assertEqual((e["result"], e["backup"], e["reason"], e["security"]), ("ok", "abcd1234", "add x", False))
        self.assertNotIn("alias", json.dumps(e))

    def test_failed_check_restores_previous_and_does_not_reload(self):
        ssh = FakeSsh(check_ok=False, files={"/config/automations.yaml": "old"})
        lf = self.local("a.yaml", "bad")
        with self.assertRaises(hc.ChangeError):
            self.make(ssh).apply([f"{lf}:automations.yaml"], "r")
        self.assertEqual(ssh.files["/config/automations.yaml"], "old")
        self.assertFalse(any("reload" in c or "restart" in c for c in self.cmds(ssh)))
        self.assertEqual([e["result"] for e in self.entries()], ["check_failed_restored"])

    def test_failed_check_removes_a_new_file(self):
        ssh = FakeSsh(check_ok=False)
        lf = self.local("a.yaml", "bad")
        with self.assertRaises(hc.ChangeError):
            self.make(ssh).apply([f"{lf}:packages/new.yaml"], "r")
        self.assertTrue(any(c.startswith("rm -f") for c in self.cmds(ssh)))

    def test_configuration_yaml_restarts_only_after_a_passing_check(self):
        ssh = FakeSsh()
        lf = self.local("c.yaml", "x: 1\n")
        self.make(ssh).apply([f"{lf}:configuration.yaml"], "r")
        cmds = self.cmds(ssh)
        self.assertLess(cmds.index("ha core check"), cmds.index("ha core restart"))

    def test_security_devices_are_flagged_and_noted(self):
        ssh = FakeSsh()
        lf = self.local("s.yaml", "action: lock.unlock\ntarget: {entity_id: lock.front_door}\n")
        self.make(ssh).apply([f"{lf}:packages/s.yaml"], "r")
        self.assertTrue(self.entries()[-1]["security"])
        self.assertTrue(any("SECURITY" in m for m in self.msgs))

    def test_refusals_touch_nothing(self):
        ssh = FakeSsh()
        lf = self.local("s.yaml", "x")
        for pair, reason in ((f"{lf}:secrets.yaml", "r"), ("nope:automations.yaml", "r"), (f"{lf}", "r"),
                             (f"{lf}:automations.yaml", " ")):
            with self.assertRaises(hc.ChangeError):
                self.make(ssh).apply([pair], reason)
        self.assertEqual(ssh.calls, [])

    def test_refuses_the_credentials_folder(self):
        ssh = FakeSsh()
        d = self.dir / ".config" / "fenton-hass"
        d.mkdir(parents=True)
        (d / "env").write_text("x")
        with self.assertRaises(hc.ChangeError):
            self.make(ssh).apply([f"{d / 'env'}:automations.yaml"], "r")

    def test_write_failure_is_logged(self):
        ssh = FakeSsh(fail=("cat > ",))
        lf = self.local("a.yaml", "x")
        with self.assertRaises(hc.ChangeError):
            self.make(ssh).apply([f"{lf}:automations.yaml"], "r")
        self.assertEqual(self.entries()[-1]["result"], "write_failed_restored")


class ApplyRollbackTests(Base):
    """A multi-file apply is all or nothing, and a failed rollback is never reported as restored."""

    def two(self):
        return [f"{self.local('a.yaml', 'NEW-A')}:automations.yaml", f"{self.local('b.yaml', 'NEW-B')}:scripts.yaml"]

    def test_a_write_failing_after_the_first_rolls_every_target_back(self):
        ssh = FakeSsh(files={"/config/automations.yaml": "OLD-A", "/config/scripts.yaml": "OLD-B"}, fail_after_writes=1)
        with self.assertRaises(hc.ChangeError):
            self.make(ssh).apply(self.two(), "r")
        self.assertEqual(ssh.files, {"/config/automations.yaml": "OLD-A", "/config/scripts.yaml": "OLD-B"})
        self.assertEqual(self.entries()[-1]["result"], "write_failed_restored")
        self.assertFalse(any("reload" in c or "restart" in c for c in self.cmds(ssh)))

    def test_a_new_file_is_removed_when_a_later_write_fails(self):
        ssh = FakeSsh(files={"/config/scripts.yaml": "OLD-B"}, fail_after_writes=1)
        with self.assertRaises(hc.ChangeError):
            self.make(ssh).apply(self.two(), "r")
        self.assertNotIn("/config/automations.yaml", ssh.files)
        self.assertEqual(ssh.files["/config/scripts.yaml"], "OLD-B")

    def test_an_unreadable_target_aborts_before_any_write_and_never_removes_it(self):
        ssh = FakeSsh(files={"/config/automations.yaml": "OLD-A", "/config/scripts.yaml": "OLD-B"}, unreadable=("scripts.yaml",))
        with self.assertRaises(hc.ChangeError) as cm:
            self.make(ssh).apply(self.two(), "r")
        self.assertIn("could not read", str(cm.exception))
        self.assertEqual(ssh.writes, 0)
        self.assertFalse(any(c.startswith("rm ") for c in self.cmds(ssh)))
        self.assertEqual(ssh.files["/config/scripts.yaml"], "OLD-B")
        self.assertEqual(self.entries()[-1]["result"], "failed")

    def test_a_failing_rollback_is_logged_and_never_reported_as_restored(self):
        ssh = FakeSsh(check_ok=False, files={"/config/automations.yaml": "OLD-A"}, fail=("rm -f",))
        orig = ssh.__call__

        def failing(args, input=None, timeout=900):
            if args[-1].startswith("cat > /config/automations.yaml") and input == "OLD-A":
                return subprocess.CompletedProcess(args, 1, "", "disk full")
            return orig(args, input, timeout)
        with self.assertRaises(hc.ChangeError) as cm:
            self.make(failing).apply([f"{self.local('a.yaml', 'NEW-A')}:automations.yaml",
                                      f"{self.local('c.yaml', 'NEW-C')}:packages/new.yaml"], "r")
        self.assertIn("ROLLBACK FAILED", str(cm.exception))
        results = [e["result"] for e in self.entries()]
        self.assertEqual(results, ["rollback_failed"])
        self.assertIn("automations.yaml", self.entries()[-1]["detail"])
        self.assertNotIn("check_failed_restored", results)

    def test_main_exits_non_zero_when_the_rollback_failed(self):
        ssh = FakeSsh(check_ok=False, files={"/config/automations.yaml": "OLD-A"})
        orig = ssh.__call__

        def failing(args, input=None, timeout=900):
            if args[-1].startswith("cat > ") and input == "OLD-A":
                return subprocess.CompletedProcess(args, 1, "", "disk full")
            return orig(args, input, timeout)
        lf = self.local("a.yaml", "NEW")
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            code = hc.main(["apply", "--files", f"{lf}:automations.yaml", "--reason", "r"], change=self.make(failing))
        self.assertEqual(code, 1)
        self.assertIn("ROLLBACK FAILED", err.getvalue())


class SourceAndTargetTests(Base):
    """Only files inside the checkout go up; nothing goes under /config/www."""

    def test_a_file_outside_the_roots_is_refused_even_when_readable(self):
        outside = tempfile.TemporaryDirectory()
        self.addCleanup(outside.cleanup)
        secret = Path(outside.name) / "id_ed25519_mesh"
        secret.write_text("KEY")
        ssh = FakeSsh()
        with self.assertRaises(hc.ChangeError) as cm:
            self.make(ssh).apply([f"{secret}:packages/x.yaml"], "r")
        self.assertIn("inside this checkout", str(cm.exception))
        self.assertEqual(ssh.calls, [])

    def test_dot_directories_and_dot_files_are_refused(self):
        for rel in (".ssh/key", ".claude/token", ".config/gh/hosts.yml", "sub/.env", ".git/config"):
            with self.subTest(rel=rel):
                path = self.dir / rel
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("x")
                ssh = FakeSsh()
                with self.assertRaises(hc.ChangeError):
                    self.make(ssh).apply([f"{path}:packages/x.yaml"], "r")
                self.assertEqual(ssh.calls, [])

    def test_a_symlink_out_of_the_checkout_is_refused(self):
        outside = tempfile.TemporaryDirectory()
        self.addCleanup(outside.cleanup)
        target = Path(outside.name) / "token"
        target.write_text("T")
        link = self.dir / "link.yaml"
        link.symlink_to(target)
        with self.assertRaises(hc.ChangeError):
            self.make(FakeSsh()).apply([f"{link}:packages/x.yaml"], "r")

    def test_build_ha_scratch_files_inside_the_checkout_go_up(self):
        scratch = self.dir / "build" / "ha"
        scratch.mkdir(parents=True)
        (scratch / "a.yaml").write_text("- alias: x\n")
        ssh = FakeSsh()
        self.make(ssh).apply([f"{scratch / 'a.yaml'}:automations.yaml"], "r")
        self.assertEqual(ssh.files["/config/automations.yaml"], "- alias: x\n")

    def test_secret_looking_names_are_refused_even_without_a_dot(self):
        for name in ("prod.env", "AuthKey_ABC.p8", "cert.p12", "tls.pem", "x.key", "app.mobileprovision", "dist.cer", "id_ed25519_mesh"):
            with self.subTest(name=name):
                (self.dir / name).write_text("x")
                ssh = FakeSsh()
                with self.assertRaises(hc.ChangeError):
                    self.make(ssh).apply([f"{self.dir / name}:packages/x.yaml"], "r")
                self.assertEqual(ssh.calls, [])

    def test_git_ignored_files_are_refused_except_under_build_ha(self):
        subprocess.run(["git", "init", "-q", str(self.dir)], check=True)
        (self.dir / ".gitignore").write_text("secrets_dump.yaml\nbuild/\n")
        (self.dir / "secrets_dump.yaml").write_text("x")
        (self.dir / "tracked.yaml").write_text("- alias: x\n")
        (self.dir / "build" / "ha").mkdir(parents=True)
        (self.dir / "build" / "ha" / "a.yaml").write_text("- alias: y\n")
        (self.dir / "build" / "other.yaml").write_text("z")
        with self.assertRaises(hc.ChangeError) as cm:
            self.make(FakeSsh()).apply([f"{self.dir / 'secrets_dump.yaml'}:packages/x.yaml"], "r")
        self.assertIn("git ignores", str(cm.exception))
        with self.assertRaises(hc.ChangeError):
            self.make(FakeSsh()).apply([f"{self.dir / 'build' / 'other.yaml'}:packages/x.yaml"], "r")
        for name in ("tracked.yaml", "build/ha/a.yaml"):
            ssh = FakeSsh()
            self.make(ssh).apply([f"{self.dir / name}:packages/x.yaml"], "r")
            self.assertIn("/config/packages/x.yaml", ssh.files)

    def test_git_ignored_refuses_when_git_cannot_say(self):
        f = self.dir / "a.yaml"
        f.write_text("x")
        for rc in (0, 128, 2):
            with mock.patch.object(hc.subprocess, "run", return_value=subprocess.CompletedProcess([], rc)):
                self.assertTrue(hc.git_ignored(self.dir, Path("a.yaml")), rc)
        with mock.patch.object(hc.subprocess, "run", return_value=subprocess.CompletedProcess([], 1)):
            self.assertFalse(hc.git_ignored(self.dir, Path("a.yaml")))
        for exc in (subprocess.TimeoutExpired("git", 20), OSError("no git")):
            with mock.patch.object(hc.subprocess, "run", side_effect=exc):
                self.assertTrue(hc.git_ignored(self.dir, Path("a.yaml")))
                with self.assertRaises(hc.ChangeError):
                    self.make(FakeSsh()).apply([f"{f}:packages/x.yaml"], "r")

    def test_www_is_never_a_target(self):
        for bad in ("www/a.txt", "/config/www/a.txt", "www"):
            with self.assertRaises(hc.ChangeError, msg=bad):
                hc.clean_remote(bad)
        self.assertEqual(hc.clean_remote("packages/www/a.yaml"), "/config/packages/www/a.yaml")

    def test_the_reason_is_redacted_in_the_log(self):
        ssh = FakeSsh()
        lf = self.local("a.yaml", "x")
        self.make(ssh).apply([f"{lf}:automations.yaml"], "fix using token=abcdef1234567890abcdef1234567890xyz")
        self.assertNotIn("abcdef1234567890", self.entries()[-1]["reason"])


class SignatureTests(Base):
    """Runs the real signature shell against a temporary directory (the fake ssh cannot check it)."""

    def sigs(self):
        out = subprocess.run(["sh", "-c", hc.signature_script(str(self.dir / "cc"))], capture_output=True, text=True, check=True).stdout
        return dict(line.partition(" ")[::2] for line in out.splitlines())

    def setUp(self):
        super().setUp()
        d = self.dir / "cc" / "integ"
        d.mkdir(parents=True)
        (d / "a.py").write_text("print(1)\n")

    def test_an_added_empty_file_changes_the_signature(self):
        before = self.sigs()
        (self.dir / "cc" / "integ" / "empty.py").write_text("")
        self.assertNotEqual(self.sigs()["integ"], before["integ"])

    def test_a_rename_changes_the_signature(self):
        before = self.sigs()
        (self.dir / "cc" / "integ" / "a.py").rename(self.dir / "cc" / "integ" / "b.py")
        self.assertNotEqual(self.sigs()["integ"], before["integ"])

    def test_names_with_spaces_and_quotes_are_counted_and_do_not_break_the_listing(self):
        before = self.sigs()
        (self.dir / "cc" / "integ" / "my file's \"x\".py").write_text("z")
        (self.dir / "cc" / "with space").mkdir()
        (self.dir / "cc" / "with space" / "f.py").write_text("q")
        after = self.sigs()
        self.assertNotEqual(after["integ"], before["integ"])
        self.assertEqual(self.sigs(), after)

    def test_pycache_is_ignored(self):
        before = self.sigs()
        (self.dir / "cc" / "integ" / "__pycache__").mkdir()
        (self.dir / "cc" / "integ" / "__pycache__" / "a.pyc").write_text("junk")
        self.assertEqual(self.sigs(), before)

    def test_a_missing_directory_exits_3(self):
        proc = subprocess.run(["sh", "-c", hc.signature_script(str(self.dir / "none"))])
        self.assertEqual(proc.returncode, 3)


class RestartHacsRevertTests(Base):
    def test_restart_checks_first(self):
        ssh = FakeSsh(check_ok=False)
        with self.assertRaises(hc.ChangeError):
            self.make(ssh).restart("r")
        self.assertNotIn("ha core restart", self.cmds(ssh))
        ssh = FakeSsh()
        self.make(ssh).restart("r")
        self.assertEqual(self.cmds(ssh)[-1], "ha core restart")

    def test_hacs_install_backs_up_lists_tars_downloads_checks_then_restarts(self):
        ssh = FakeSsh(dirs=["old_one"])
        self.make(ssh).hacs_install("SFenton/ha-fenton-push", "r")
        cmds = self.cmds(ssh)
        self.assertEqual(ssh.ws_seen[:3], ["hacs/repositories/list", "hacs/repository/refresh", "hacs/repositories/list"])
        self.assertTrue(all(c.startswith("python3 - ") for c in cmds[:3]))
        self.assertIn("ha backups new", cmds[3])
        self.assertIn("cksum", cmds[4])
        self.assertIn("tar -C /config -cf /root/ha-changes/custom_components-", cmds[5])
        self.assertNotIn("/www", cmds[5])
        self.assertTrue(cmds[6].startswith("python3 - "))
        self.assertEqual(ssh.ws_seen[3:], ["hacs/repository/download", "hacs/repositories/list"])
        self.assertEqual(cmds[8:10], ["ha core check", "ha core restart"])
        self.assertTrue(cmds[10].startswith("rm -f /root/ha-changes/custom_components-"))
        self.assertEqual(ssh.repos["2"]["installed_version"], "abc1234")
        self.assertFalse([c for c in cmds if "services/hacs" in c or "update.install" in c or "/states" in c])
        with self.assertRaises(hc.ChangeError):
            self.make(ssh).hacs_install("not a repo", "r")

    def test_hacs_excludes_pycache_and_deletes_the_tarball_after_success_and_after_undo(self):
        ssh = FakeSsh(dirs=["a"])
        self.make(ssh).hacs_install("a/b", "r")
        cmds = self.cmds(ssh)
        self.assertIn("--exclude=__pycache__", [c for c in cmds if "-cf " in c][0])
        tarball = [c for c in cmds if "-cf " in c][0].split("-cf ")[1].split()[0]
        self.assertEqual(cmds[-1], f"rm -f {tarball}")
        ssh = FakeSsh(dirs=["a"], check_seq=[False, True])
        ssh.after_download = ["new"]
        with self.assertRaises(hc.ChangeError):
            self.make(ssh).hacs_install("a/b", "r")
        self.assertTrue(self.cmds(ssh)[-1].startswith("rm -f /root/ha-changes/custom_components-"))

    def test_hacs_keeps_the_tarball_on_rollback_failed(self):
        ssh = FakeSsh(dirs=["a"], check_ok=False)
        ssh.after_download = ["new"]
        with self.assertRaises(hc.ChangeError):
            self.make(ssh).hacs_install("a/b", "r")
        self.assertFalse([c for c in self.cmds(ssh) if c.startswith("rm -f /root/ha-changes")])

    def test_a_failed_tar_stops_before_the_download(self):
        ssh = FakeSsh(dirs=["a"])
        ssh.tar_fails = True
        with self.assertRaises(hc.ChangeError) as cm:
            self.make(ssh).hacs_install("a/b", "r")
        self.assertIn("tar custom_components", str(cm.exception))
        self.assertFalse([c for c in self.cmds(ssh) if "hacs/repository/download" in c])
        self.assertEqual(self.entries()[-1]["result"], "failed")

    def test_hacs_failed_check_removes_the_new_integration_and_rechecks(self):
        ssh = FakeSsh(dirs=["old_one"], check_seq=[False, True])
        ssh.after_download = ["fenton_push"]
        with self.assertRaises(hc.ChangeError) as cm:
            self.make(ssh).hacs_install("SFenton/ha-fenton-push", "r")
        self.assertEqual(ssh.dirs, ["old_one"])
        self.assertIn("removed fenton_push", str(cm.exception))
        self.assertIn("did not restart Core", str(cm.exception))
        cmds = self.cmds(ssh)
        self.assertNotIn("ha core restart", cmds)
        self.assertEqual(cmds.count("ha core check"), 2)
        self.assertEqual(self.entries()[-1]["result"], "check_failed_restored")
        self.assertNotIn("ha backups restore abcd1234", cmds)

    def test_the_download_pins_the_github_target_version(self):
        for release, want in ((None, "main"), ("v2.0.0", "v2.0.0")):
            ssh = FakeSsh(dirs=["a"])
            if release:
                ssh.releases["a/b"] = release
            self.make(ssh).hacs_install("a/b", "r")
            dl = [m for m in ssh.ws_msgs if m["type"] == "hacs/repository/download"]
            self.assertEqual(dl, [{"type": "hacs/repository/download", "repository": "1", "version": want}])

    def test_every_failure_names_the_backup_and_the_tarball_where_they_exist(self):
        ssh = FakeSsh(dirs=["old_one"], check_seq=[False, True])
        ssh.after_download = ["fenton_push"]
        with self.assertRaises(hc.ChangeError) as cm:
            self.make(ssh).hacs_install("SFenton/ha-fenton-push", "r")
        self.assertIn("backup abcd1234", str(cm.exception))
        ssh = FakeSsh(dirs=["fenton_push"], check_seq=[False], fail_restore=True)
        ssh.modify_on_download = ["fenton_push"]
        with self.assertRaises(hc.ChangeError) as cm:
            self.make(ssh).hacs_install("SFenton/ha-fenton-push", "r")
        msg = str(cm.exception)
        self.assertIn("backup abcd1234", msg)
        self.assertIn("tarball /root/ha-changes/custom_components-", msg)

    def test_a_short_sha_is_refused_like_hacs_and_a_full_sha_or_tag_is_honoured(self):
        ssh = FakeSsh(dirs=["a"])
        self.assertTrue(hc.HaChange.same_version("abc1234", "abc1234" + "0" * 33))
        self.assertFalse(hc.HaChange.same_version("v1.2", "v1.20"))  # tags compare exactly, never by prefix
        self.assertFalse(hc.HaChange.same_version("abc1234", "abc12345"))  # neither side is a full sha
        self.assertTrue(hc.HaChange.same_version("V1.2", "v1.2"))
        self.assertFalse(hc.HaChange.same_version("abc1234", "def1234" + "0" * 33))
        msg = {"type": "hacs/repository/download", "repository": "1", "version": "abc1234"}
        ssh.ws(msg)
        self.assertIn("zipball", ssh.ws_error)  # the fake models HACS 2.0.5: a short sha 404s on both archive URLs
        self.assertEqual(ssh.repos["1"]["installed_version"], "old1111")
        self.make(FakeSsh(dirs=["a"])).hacs_install("a/b", "r")  # the tool sends the full sha, so it succeeds

    def test_a_commit_tracked_repo_installs_the_default_branch_and_verifies_hacs_commit_and_leaves_the_update_entity_off(self):
        ssh = FakeSsh(dirs=["a"])
        self.make(ssh).hacs_install("a/b", "r")
        self.assertEqual(ssh.sent_versions, ["main"])
        self.assertEqual(ssh.repos["1"]["installed_version"], "abc1234")
        self.assertFalse(ssh.repos["1"]["update_on"])

    def test_a_download_that_installs_another_commit_than_the_github_head_fails_the_post_check(self):
        ssh = FakeSsh(dirs=["a"])
        orig = ssh.ws

        def other(msg):
            out = orig(msg)
            if msg["type"] == "hacs/repository/download":
                ssh.repos["1"]["installed_version"] = "fff9999"  # HACS's own data says a different commit landed
            return out
        ssh.ws = other
        with self.assertRaises(hc.ChangeError) as cm:
            self.make(ssh).hacs_install("a/b", "r")
        self.assertIn("expected abc1234", str(cm.exception))
        self.assertNotIn("ha core restart", self.cmds(ssh))

    def test_a_release_repo_keeps_the_tag_pin_and_the_update_entity_off(self):
        ssh = FakeSsh(dirs=["a"])
        ssh.releases["a/b"] = "v2.0.0"
        self.make(ssh).hacs_install("a/b", "r")
        self.assertEqual(ssh.sent_versions, ["v2.0.0"])
        self.assertFalse(ssh.repos["1"]["update_on"])

    def test_a_renamed_repo_is_matched_by_github_id(self):
        ssh = FakeSsh(dirs=["a"])
        ssh.repos["1"]["full_name"] = "old-owner/old-name"  # HACS still has the old name
        ssh.github_ids["a/b"] = "1"
        ssh.github["old-owner/old-name"] = ssh.github["a/b"]
        self.assertEqual(self.make(ssh).hacs_entry("a/b")["full_name"], "old-owner/old-name")
        self.make(ssh).hacs_install("a/b", "r")
        self.assertEqual(ssh.repos["1"]["installed_version"], "abc1234")

    def test_a_name_match_wins_and_an_unmatched_id_or_unreadable_github_still_says_add_it(self):
        ssh = FakeSsh()
        ssh.github_ids["a/b"] = "2"  # would point at another repo, but the exact name matches first
        self.assertEqual(self.make(ssh).hacs_entry("a/b")["id"], "1")
        for ids in ({}, {"x/y": "99"}):
            ssh = FakeSsh()
            ssh.github_ids = ids
            with self.assertRaises(hc.ChangeError) as cm:
                self.make(ssh).hacs_entry("x/y")
            self.assertIn("add it as a custom repository", str(cm.exception))

    def test_hacs_failed_check_on_an_update_restores_only_the_changed_directory_from_the_tarball(self):
        ssh = FakeSsh(dirs=["fenton_push", "other_one"], check_seq=[False, True])
        ssh.modify_on_download = ["fenton_push"]
        with self.assertRaises(hc.ChangeError) as cm:
            self.make(ssh).hacs_install("SFenton/ha-fenton-push", "r")
        self.assertEqual(ssh.sigs, {"fenton_push": "100 1", "other_one": "100 1"})
        restores = [c for c in self.cmds(ssh) if " && tar " in c and "-xf" in c]
        self.assertEqual(len(restores), 1)
        self.assertIn("custom_components/fenton_push", restores[0])
        self.assertIn("restored fenton_push", str(cm.exception))
        self.assertEqual(self.entries()[-1]["result"], "check_failed_restored")

    def test_no_path_ever_runs_a_full_backup_restore(self):
        for kw, after, modify, seq in ((dict(), ["new"], [], [False, True]), (dict(dirs=["a"]), [], ["a"], [False, True]),
                                       (dict(dirs=["a"], fail_restore=True), [], ["a"], [False, True]),
                                       (dict(check_ok=False), ["new"], [], None), (dict(), [], [], [True])):
            with self.subTest(kw=kw, after=after, modify=modify):
                ssh = FakeSsh(**{k: v for k, v in kw.items() if k != "fail_restore"}, check_seq=seq or [])
                ssh.fail_restore = kw.get("fail_restore", False)
                ssh.after_download, ssh.modify_on_download = after, modify
                with contextlib.suppress(hc.ChangeError):
                    self.make(ssh).hacs_install("a/b", "r")
                self.assertFalse([c for c in self.cmds(ssh) if c.startswith("ha backups restore")])

    def test_a_failing_partial_restore_is_rollback_failed_and_names_the_manual_revert(self):
        ssh = FakeSsh(dirs=["fenton_push"], check_seq=[False], fail_restore=True)
        ssh.modify_on_download = ["fenton_push"]
        with self.assertRaises(hc.ChangeError) as cm:
            self.make(ssh).hacs_install("SFenton/ha-fenton-push", "r")
        self.assertIn("ROLLBACK FAILED", str(cm.exception))
        self.assertIn("ha_change.py revert abcd1234", str(cm.exception))
        self.assertEqual(self.entries()[-1]["result"], "rollback_failed")
        self.assertFalse([c for c in self.cmds(ssh) if c.startswith("ha backups restore")])

    def test_a_check_that_still_fails_after_the_undo_is_rollback_failed(self):
        ssh = FakeSsh(dirs=["a"], check_ok=False)
        ssh.after_download = ["new"]
        with self.assertRaises(hc.ChangeError) as cm:
            self.make(ssh).hacs_install("a/b", "r")
        self.assertIn("ROLLBACK FAILED", str(cm.exception))
        self.assertEqual(self.entries()[-1]["result"], "rollback_failed")

    def test_a_failed_listing_aborts_before_the_download(self):
        ssh = FakeSsh(dirs=["a", "b"])
        ssh.listing_fails = True
        with self.assertRaises(hc.ChangeError) as cm:
            self.make(ssh).hacs_install("a/b", "r")
        self.assertIn("could not list", str(cm.exception))
        cmds = self.cmds(ssh)
        self.assertFalse([c for c in cmds if "hacs/repository/download" in c or "rm -rf" in c or " -cf " in c])
        self.assertEqual(self.entries()[-1]["result"], "failed")

    def test_a_missing_components_directory_is_an_empty_listing(self):
        ssh = FakeSsh()
        ssh.no_components_dir = True
        self.make(ssh).hacs_install("a/b", "r")
        self.assertIn("ha core restart", self.cmds(ssh))

    def test_resolves_by_full_name_case_insensitively_among_hacs_repositories_only(self):
        ssh = FakeSsh()
        self.assertEqual(self.make(ssh).hacs_entry("sfenton/HA-fenton-push")["id"], "2")
        for name in ("home-assistant/operating-system", "home-assistant/supervisor"):  # non-HACS: never resolvable
            with self.assertRaises(hc.ChangeError) as cm:
                self.make(ssh).hacs_install(name, "r")
            self.assertIn("custom repository", str(cm.exception))
        self.assertFalse([c for c in self.cmds(ssh) if c.startswith("ha ") or " -cf " in c])

    def test_an_unknown_repo_fails_clearly_before_any_backup_or_change(self):
        ssh = FakeSsh()
        with self.assertRaises(hc.ChangeError) as cm:
            self.make(ssh).hacs_install("SFenton/never-added", "r")
        self.assertIn("add it as a custom repository in HACS", str(cm.exception))
        self.assertEqual(ssh.ws_seen, ["hacs/repositories/list"])
        self.assertEqual(self.entries()[-1]["result"], "failed")

    def test_a_prefix_of_another_repo_and_duplicates_are_not_guessed(self):
        ssh = FakeSsh()
        ssh.repos["3"] = {"id": "3", "full_name": "SFenton/ha-fenton-push-extra", "available_version": "x", "installed_version": "x", "installed": True}
        self.assertEqual(self.make(ssh).hacs_entry("SFenton/ha-fenton-push")["id"], "2")
        ssh.repos["4"] = dict(ssh.repos["2"], id="4")
        with self.assertRaises(hc.ChangeError) as cm:
            self.make(ssh).hacs_install("SFenton/ha-fenton-push", "r")
        self.assertIn("refusing to guess", str(cm.exception))

    def test_refresh_is_what_moves_hacs_to_github_and_the_install_uses_the_fresh_target(self):
        ssh = FakeSsh(dirs=["a"])
        self.assertEqual(ssh.repos["1"]["available_version"], "old2222")  # stale until the refresh command
        self.make(ssh).hacs_install("a/b", "r")
        self.assertEqual(ssh.repos["1"]["installed_version"], "abc1234")
        self.assertLess(ssh.ws_seen.index("hacs/repository/refresh"), ssh.ws_seen.index("hacs/repository/download"))

    def test_stale_after_refresh_is_refused_with_no_backup_or_download(self):
        ssh = FakeSsh(dirs=["a"])
        ssh.github["a/b"] = "fe99999"
        ssh.refresh_stuck = True
        orig = ssh.ws

        def stuck(msg):
            if msg["type"] == "hacs/repository/refresh":
                return {}
            return orig(msg)
        ssh.ws = stuck
        with self.assertRaises(hc.ChangeError) as cm:
            self.make(ssh).hacs_install("a/b", "r")
        self.assertIn("still offers old2222", str(cm.exception))
        self.assertIn("fe99999", str(cm.exception))
        self.assertFalse([c for c in self.cmds(ssh) if c.startswith("ha ") or " -cf " in c])
        self.assertNotIn("hacs/repository/download", ssh.ws_seen)

    def test_release_tag_is_the_target_when_the_repo_has_releases(self):
        ssh = FakeSsh(dirs=["a"])
        ssh.releases["a/b"] = "v2.0.0"
        self.make(ssh).hacs_install("a/b", "r")
        self.assertEqual(ssh.repos["1"]["installed_version"], "v2.0.0")

    def test_already_current_after_refresh_stops_without_backup_download_or_restart(self):
        ssh = FakeSsh(dirs=["a"])
        ssh.repos["1"]["installed_version"] = "abc1234"
        self.make(ssh).hacs_install("a/b", "r")
        self.assertIn("hacs/repository/refresh", ssh.ws_seen)
        self.assertFalse([c for c in self.cmds(ssh) if c.startswith("ha ") or " -cf " in c])
        self.assertNotIn("hacs/repository/download", ssh.ws_seen)
        self.assertEqual(self.entries()[-1]["result"], "up_to_date")

    def test_first_time_download_of_a_registered_but_never_installed_repo(self):
        ssh = FakeSsh()
        ssh.repos["1"].update(installed=False, installed_version="")
        ssh.after_download = ["a_b"]
        self.make(ssh).hacs_install("a/b", "r")
        self.assertEqual(ssh.repos["1"]["installed_version"], "abc1234")
        self.assertIn("ha core restart", self.cmds(ssh))

    def test_missing_version_fields_are_never_read_as_up_to_date(self):
        ssh = FakeSsh()
        ssh.repos["1"]["available_version"] = ""
        orig = ssh.ws
        ssh.ws = lambda m: {} if m["type"] == "hacs/repository/refresh" else orig(m)
        with self.assertRaises(hc.ChangeError) as cm:
            self.make(ssh).hacs_install("a/b", "r")
        self.assertIn("no available version", str(cm.exception))
        self.assertFalse([c for c in self.cmds(ssh) if c.startswith("ha ")])

    def test_a_version_mismatch_after_the_download_stops_before_check_and_restart_and_names_backup_and_tarball(self):
        ssh = FakeSsh(dirs=["a"])
        ssh.download_noop = True
        with self.assertRaises(hc.ChangeError) as cm:
            self.make(ssh).hacs_install("a/b", "r")
        msg = str(cm.exception)
        self.assertIn("expected abc1234", msg)
        self.assertIn("backup abcd1234", msg)
        self.assertIn("/root/ha-changes/custom_components-", msg)
        cmds = self.cmds(ssh)
        self.assertNotIn("ha core check", cmds)
        self.assertNotIn("ha core restart", cmds)
        self.assertFalse([c for c in cmds if c.startswith("rm ")])
        self.assertEqual(self.entries()[-1]["result"], "failed")

    def test_hacs_download_error_text_is_surfaced_with_backup_and_tarball(self):
        ssh = FakeSsh(dirs=["a"])
        ssh.ws_error = "Repository has no valid manifest"
        with self.assertRaises(hc.ChangeError) as cm:
            self.make(ssh).hacs_install("a/b", "r")
        self.assertIn("Repository has no valid manifest", str(cm.exception))
        self.assertIn("backup abcd1234", str(cm.exception))
        self.assertIn("kept on the HA host", str(cm.exception))

    def test_a_failure_before_the_tarball_names_only_the_backup(self):
        ssh = FakeSsh(dirs=["a"])
        ssh.tar_fails = True
        with self.assertRaises(hc.ChangeError) as cm:
            self.make(ssh).hacs_install("a/b", "r")
        self.assertIn("backup abcd1234", str(cm.exception))
        self.assertNotIn("kept on the HA host", str(cm.exception))

    def test_github_unreadable_stops_before_hacs_is_touched(self):
        ssh = FakeSsh()
        orig = ssh.__call__

        def bad(args, input=None, timeout=900):
            if args[0] == "gh":
                return subprocess.CompletedProcess(args, 1, "", "gh: not logged in")
            return orig(args, input, timeout)
        with self.assertRaises(hc.ChangeError) as cm:
            hc.HaChange(run=bad, log_path=self.log, now=lambda: 1700000000, out=self.msgs.append, roots=[self.dir]).hacs_install("a/b", "r")
        self.assertIn("could not read the GitHub head", str(cm.exception))
        self.assertNotIn("hacs/repository/refresh", ssh.ws_seen)

    def test_ws_client_errors_and_garbage_are_surfaced(self):
        def make(out, rc=0):
            return hc.HaChange(run=lambda a, input=None, timeout=900: subprocess.CompletedProcess(a, rc, out, ""),
                               log_path=self.log, roots=[self.dir])
        with self.assertRaises(hc.ChangeError) as cm:
            make(json.dumps({"success": False, "result": None, "error": "unauthorized: nope"})).ws_command({"type": "x"}, "w")
        self.assertIn("unauthorized: nope", str(cm.exception))
        with self.assertRaises(hc.ChangeError):
            make("not json").ws_command({"type": "x"}, "w")
        with self.assertRaises(hc.ChangeError):
            make("", rc=1).ws_command({"type": "x"}, "w")

    def test_the_ws_client_is_valid_python_and_never_prints_the_token(self):
        compile(hc.WS_CLIENT, "ws_client", "exec")
        self.assertNotIn("print(os.environ", hc.WS_CLIENT)
        self.assertIn('os.environ["SUPERVISOR_TOKEN"]', hc.WS_CLIENT)

    def test_call_service_surfaces_the_home_assistant_error_body(self):
        def run(a, input=None, timeout=900):
            return subprocess.CompletedProcess(a, 0, '{"message":"Service not found."}\n400', "")
        with self.assertRaises(hc.ChangeError) as cm:
            hc.HaChange(run=run, log_path=self.log, roots=[self.dir]).call_service("x", "y")
        self.assertIn("Service not found", str(cm.exception))

    def test_revert(self):
        ssh = FakeSsh()
        self.make(ssh).revert("abcd1234")
        self.assertEqual(self.cmds(ssh), ["ha backups restore abcd1234"])
        with self.assertRaises(hc.ChangeError):
            self.make(ssh).revert("x; rm")


class MainTests(Base):
    def run_main(self, argv, ssh):
        err, out = io.StringIO(), io.StringIO()
        with contextlib.redirect_stderr(err), contextlib.redirect_stdout(out):
            code = hc.main(argv, self.make(ssh))
        return code, out.getvalue(), err.getvalue()

    def test_subcommands(self):
        ssh = FakeSsh()
        self.assertEqual(self.run_main(["backup", "n"], ssh)[:2], (0, "abcd1234\n"))
        self.assertEqual(self.run_main(["check"], ssh)[0], 0)
        self.assertEqual(self.run_main(["restart", "--reason", "r"], ssh)[0], 0)
        self.assertEqual(self.run_main(["hacs-install", "a/b", "--reason", "r"], ssh)[0], 0)
        self.assertEqual(self.run_main(["revert", "abcd1234"], ssh)[0], 0)
        lf = self.local("a.yaml", "x")
        self.assertEqual(self.run_main(["apply", "--files", f"{lf}:automations.yaml", "--reason", "r"], ssh)[0], 0)

    def test_host_flag_targets_another_alias_and_is_logged(self):
        ssh, argvs = FakeSsh(), []
        change = self.make(lambda args, input=None, timeout=900: (argvs.append(args), ssh(args, input, timeout))[1])
        code = hc.main(["--host", "hass-test", "restart", "--reason", "r"], change)
        self.assertEqual(code, 0)
        self.assertTrue(argvs and all(a[3] == "hass-test" for a in argvs), argvs[:2])
        self.assertEqual({e["host"] for e in self.entries()}, {"hass-test"})

    def test_default_host_is_hass(self):
        self.assertEqual(hc.HaChange().host, "hass")
        argvs = []
        change = hc.HaChange(run=lambda a, input=None, timeout=900: (argvs.append(a), subprocess.CompletedProcess(a, 0, "", ""))[1],
                             log_path=self.log)
        change.check()
        self.assertEqual(argvs[0][3], "hass")

    def test_host_must_be_an_alias(self):
        for bad in ("-oProxyCommand=x", "a b", "a;b", "", "h/x"):
            with self.assertRaises(hc.ChangeError, msg=bad):
                hc.HaChange(host=bad)
        ssh = FakeSsh()
        code, _, err = self.run_main(["--host=-oFoo", "check"], ssh)
        self.assertEqual(code, 1)
        self.assertIn("ssh alias", err)
        self.assertEqual(ssh.calls, [])

    def test_guardrails_hold_on_another_host(self):
        ssh = FakeSsh()
        change = self.make(ssh)
        change.host = "hass-test"
        hidden = self.local(".hidden.yaml", "x")
        with self.assertRaises(hc.ChangeError):
            change.apply([f"{hidden}:automations.yaml"], "r")
        lock = self.local("l.yaml", "lock.front_door: on")
        change.apply([f"{lock}:automations.yaml"], "r")
        self.assertTrue(any(e["security"] and e["host"] == "hass-test" for e in self.entries()))

    def test_failure_exits_one_without_a_token(self):
        code, _, err = self.run_main(["check"], FakeSsh(check_ok=False))
        self.assertEqual(code, 1)
        self.assertIn("ha_change:", err)

    def test_redact(self):
        self.assertNotIn("abcdef", hc.redact("Authorization: Bearer abcdef"))
        self.assertNotIn("A" * 50, hc.redact("t=" + "A" * 50))


if __name__ == "__main__":
    unittest.main()


class HouseConfigReloadTests(Base):
    """``apply`` of fenton_home/house.(yaml|json) reloads through fenton_home.reload_house_config and reads Repairs afterwards."""

    def run_apply(self, ssh, issues, name="house.yaml"):
        src = Path(self.dir) / name
        src.write_text("rooms: []\n")
        orig = ssh.ws
        ssh.ws = lambda m: {"issues": issues} if m["type"] == "repairs/list_issues" else orig(m)
        return self.make(ssh).apply([f"{src}:/config/fenton_home/{name}"], "r")

    def test_reload_for_maps_the_house_files(self):
        for name in ("house.yaml", "house.json"):
            self.assertEqual(hc.reload_for([f"/config/fenton_home/{name}"]), [hc.HOUSE_RELOAD])
        self.assertIsNone(hc.reload_for(["/config/fenton_home/other.yaml"]))

    def test_a_clean_house_apply_reloads_without_a_restart(self):
        for name in ("house.yaml", "house.json"):
            ssh = FakeSsh()
            self.run_apply(ssh, [{"domain": "fenton_home", "issue_id": "something_else"}, {"domain": "x", "issue_id": "house_config_invalid"}], name)
            cmds = self.cmds(ssh)
            self.assertTrue([c for c in cmds if "services/fenton_home/reload_house_config" in c])
            self.assertNotIn("ha core restart", cmds)
            self.assertIn("repairs/list_issues", ssh.ws_seen)
            self.assertEqual(self.entries()[-1]["result"], "ok")

    def test_house_config_invalid_rolls_back_and_reloads_again(self):
        ssh = FakeSsh(files={"/config/fenton_home/house.yaml": "old: 1\n"})
        with self.assertRaises(hc.ChangeError) as cm:
            self.run_apply(ssh, [{"domain": "fenton_home", "issue_id": "house_config_invalid"}])
        self.assertIn("house_config_invalid", str(cm.exception))
        self.assertIn("abcd1234", str(cm.exception))
        self.assertEqual(ssh.files["/config/fenton_home/house.yaml"], "old: 1\n")
        reloads = [c for c in self.cmds(ssh) if "services/fenton_home/reload_house_config" in c]
        self.assertEqual(len(reloads), 2)
        self.assertNotIn("ha core restart", self.cmds(ssh))
        self.assertEqual(self.entries()[-1]["result"], "house_reload_restored")

    def test_house_config_invalid_with_a_failing_rollback_is_rollback_failed(self):
        ssh = FakeSsh(files={"/config/fenton_home/house.yaml": "old: 1\n"})
        orig_call = ssh.__call__

        def run(args, input=None, timeout=900):
            if args[0] != "gh" and args[-1].startswith("cat > ") and input == "old: 1\n":
                return subprocess.CompletedProcess(args, 1, "boom", "")
            return orig_call(args, input, timeout)
        with self.assertRaises(hc.ChangeError) as cm:
            src = Path(self.dir) / "house.yaml"
            src.write_text("rooms: []\n")
            o = ssh.ws
            ssh.ws = lambda m: {"issues": [{"domain": "fenton_home", "issue_id": "house_config_invalid"}]} if m["type"] == "repairs/list_issues" else o(m)
            hc.HaChange(run=run, log_path=self.log, now=lambda: 1700000000, out=self.msgs.append,
                        roots=[self.dir]).apply([f"{src}:/config/fenton_home/house.yaml"], "r")
        self.assertIn("ROLLBACK FAILED", str(cm.exception))
        self.assertEqual(self.entries()[-1]["result"], "rollback_failed")

    def test_an_unloaded_entry_fails_before_any_reload_and_rolls_back(self):
        ssh = FakeSsh(files={"/config/fenton_home/house.yaml": "old: 1\n"})
        ssh.entry_state = "setup_error"
        with self.assertRaises(hc.ChangeError) as cm:
            self.run_apply(ssh, [])
        self.assertIn("not loaded", str(cm.exception))
        self.assertIn("abcd1234", str(cm.exception))
        self.assertEqual(ssh.files["/config/fenton_home/house.yaml"], "old: 1\n")
        self.assertFalse([c for c in self.cmds(ssh) if "reload_house_config" in c])
        self.assertNotIn("ha core restart", self.cmds(ssh))
        self.assertEqual(self.entries()[-1]["result"], "house_reload_restored")

    def test_a_failed_reload_call_rolls_the_files_back(self):
        ssh = FakeSsh(files={"/config/fenton_home/house.yaml": "old: 1\n"})
        orig = ssh.__call__

        def run(args, input=None, timeout=900):
            if args[0] != "gh" and "reload_house_config" in args[-1]:
                return subprocess.CompletedProcess(args, 0, '{"message":"boom"}\n500', "")
            return orig(args, input, timeout)
        src = Path(self.dir) / "house.yaml"
        src.write_text("rooms: []\n")
        with self.assertRaises(hc.ChangeError) as cm:
            hc.HaChange(run=run, log_path=self.log, now=lambda: 1700000000, out=self.msgs.append,
                        roots=[self.dir]).apply([f"{src}:/config/fenton_home/house.yaml"], "r")
        self.assertIn("reloading the house config failed", str(cm.exception))
        self.assertIn("abcd1234", str(cm.exception))
        self.assertEqual(ssh.files["/config/fenton_home/house.yaml"], "old: 1\n")
