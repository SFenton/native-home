"""First-install-only Supervisor command, exercising the real remote protocol against a fake SSH/CLI."""
from __future__ import annotations

import base64
import contextlib
import hashlib
import io
import json
import os
import shlex
import subprocess
import sys
import tarfile
import tempfile
import types
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import ha_app_install as app
import ha_change as hc

SLUG = "demo_studio"
EXACT = "local_" + SLUG
SECRET = "demo-private-option"


def manifest():
    return {"name": "Demo Studio", "description": "A test app", "slug": SLUG, "version": "1.2.3",
            "arch": ["amd64", "aarch64"], "ingress": True, "ingress_port": 4800, "panel_admin": True,
            "ports": {"4800/tcp": None}, "options": {"live_actions": False}, "schema": {"live_actions": "bool"}}


class FakeSsh:
    """Run the actual fixed remote Python locally; only the HA CLI and /addons mount are replaced."""

    def __init__(self, addons):
        self.addons = addons
        self.actions, self.commands, self.timeouts = [], [], []
        self.installed = None
        self.store_row = None
        self.fail_cli = {}
        self.hooks = {}
        self.bad_replies = {}
        self.health = {"healthy": True, "supported": True}
        self.list_key = "addons"
        self.ns = {"__name__": "remote_test"}
        exec(app.REMOTE, self.ns)
        self.ns["ADDONS"] = str(addons)
        self.ns["subprocess"] = types.SimpleNamespace(run=self.cli, TimeoutExpired=subprocess.TimeoutExpired)

    def cli(self, args, capture_output, text, timeout):
        assert capture_output and text and args[-1] == "--raw-json"
        cmd = " ".join(args[1:-1])
        self.commands.append(cmd)
        if cmd in self.fail_cli:
            fail = self.fail_cli[cmd]
            if callable(fail):
                return fail(args)
            return subprocess.CompletedProcess(args, 1, SECRET, SECRET)
        data = {}
        if cmd == "supervisor info":
            data = self.health
        elif cmd == "apps":
            data = {self.list_key: [self.installed] if self.installed else []}
        elif cmd == "store":
            data = {self.list_key: [self.store_row] if self.store_row else []}
        elif cmd.startswith("backups new"):
            data = {"slug": "abcd1234"}
        elif cmd == "core check":
            pass
        elif cmd == "store reload":
            if (self.addons / SLUG / "config.yaml").exists():
                cfg = json.loads((self.addons / SLUG / "config.yaml").read_text())
                self.store_row = {"slug": EXACT, "version": None, "version_latest": cfg["version"], "repository": "local",
                                  "available": True, "installed": bool(self.installed)}
            else:
                self.store_row = None
        elif cmd == f"apps install {EXACT}":
            self.installed = {"slug": EXACT, "version": "1.2.3", "state": "stopped", "options": {"password": SECRET}}
        elif cmd == f"apps start {EXACT}":
            self.installed["state"] = "started"
        elif cmd == f"apps stop {EXACT}":
            self.installed["state"] = "stopped"
        elif cmd == f"apps uninstall {EXACT}":
            self.installed = None
        else:
            raise AssertionError("Unexpected HA command: " + cmd)
        return subprocess.CompletedProcess(args, 0, json.dumps({"result": "ok", "data": data, "options": SECRET}), SECRET)

    def __call__(self, args, input=None, timeout=900):
        assert args[:3] == ["ssh", "-o", "BatchMode=yes"]
        parts = shlex.split(args[-1])
        assert parts[:2] == ["python3", "-c"] and parts[2] == app.REMOTE and len(parts) == 4
        action = parts[3]
        self.actions.append(action)
        self.timeouts.append((action, timeout))
        payload = json.loads(input)
        hook = self.hooks.get(action)
        if hook:
            hook(payload)
        if action in self.bad_replies:
            reply = self.bad_replies[action]
            if isinstance(reply, Exception):
                raise reply
            return subprocess.CompletedProcess(args, 0, reply, SECRET)
        reply = self.ns["execute"](action, payload)
        return subprocess.CompletedProcess(args, 0, json.dumps(reply), SECRET)


class InstallTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.source = self.root / "build" / "ha" / "frozen"
        self.source.mkdir(parents=True)
        (self.source / "config.yaml").write_text(json.dumps(manifest()))
        (self.source / "Dockerfile").write_text("FROM scratch\nCOPY src /app\n")
        (self.source / "src").mkdir()
        (self.source / "src" / "run.sh").write_text("#!/bin/sh\nexit 0\n")
        (self.source / "src" / "run.sh").chmod(0o755)
        self.addons = self.root / "addons"
        self.addons.mkdir()
        self.ssh = FakeSsh(self.addons)
        self.output = []
        self.log = self.root / "changes.jsonl"
        self.change = hc.HaChange(run=self.ssh, roots=[self.root], log_path=self.log, out=self.output.append)

    def install(self, **kw):
        return self.change.addon_install(str(kw.pop("source", self.source)), kw.pop("slug", SLUG),
                                         kw.pop("reason", "Install demo"), kw.pop("owner_approved", True), **kw)

    def failure(self, **kw):
        with self.assertRaises(hc.ChangeError) as caught:
            self.install(**kw)
        message = str(caught.exception)
        self.assertNotIn(SECRET, message)
        if self.log.exists():
            self.assertNotIn(SECRET, self.log.read_text())
        self.assertNotIn("core restart", self.ssh.commands)
        self.assertFalse(any(c.startswith("backups restore") for c in self.ssh.commands))
        return message

    def entry(self):
        rows = [json.loads(line) for line in self.log.read_text().splitlines()]
        self.assertEqual(len(rows), 1)
        return rows[0]

    def test_success_is_ordered_backed_up_checked_and_never_restarts_core(self):
        self.assertEqual(self.install(), "abcd1234")
        self.assertEqual(self.ssh.actions, ["preflight", "backup", "check", "upload", "store",
                                            "install", "start", "status", "check"])
        commands = self.ssh.commands
        self.assertLess(commands.index("core check"), commands.index("store reload"))
        self.assertLess(commands.index("store reload"), commands.index(f"apps install {EXACT}"))
        self.assertLess(commands.index(f"apps install {EXACT}"), commands.index(f"apps start {EXACT}"))
        self.assertEqual(commands.count("core check"), 2)
        self.assertEqual(self.ssh.timeouts[self.ssh.actions.index("install")], ("install", 1200))
        self.assertEqual((self.addons / SLUG / "src" / "run.sh").stat().st_mode & 0o777, 0o755)
        self.assertEqual(self.entry()["result"], "ok")
        self.assertEqual(self.entry()["backup"], "abcd1234")
        self.assertEqual(self.entry()["command"], "addon-install")
        self.assertNotIn(SECRET, self.log.read_text() + "".join(self.output))
        self.assertNotIn("Dockerfile", self.log.read_text())
        self.assertNotIn("core restart", commands)
        self.assertFalse(any(c.startswith("apps uninstall") for c in commands))

    def test_opt_in_and_reason_are_required_without_remote_access(self):
        for kwargs in ({"owner_approved": False}, {"reason": " "}):
            with self.subTest(kwargs=kwargs):
                self.failure(**kwargs)
        self.assertEqual(self.ssh.actions, [])

    def test_v2_apps_response_key_is_supported(self):
        self.ssh.list_key = "apps"
        self.assertEqual(self.install(), "abcd1234")

    def test_cli_enforces_opt_in_and_routes_explicit_host(self):
        argv = ["addon-install", "--source", str(self.source), "--slug", SLUG, "--reason", "demo"]
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(hc.main(argv, self.change), 1)
        self.assertEqual(self.ssh.actions, [])
        self.log.unlink()
        self.assertEqual(hc.main(["--host", "hass-test"] + argv + ["--owner-approved"], self.change), 0)
        self.assertEqual(self.entry()["host"], "hass-test")

    def test_bad_slugs_are_refused_before_ssh(self):
        for slug in ("../config", "a__b", "_a", "a-", "a/b", "a;id", "A", "a" * 49):
            with self.subTest(slug=slug):
                self.failure(slug=slug)
        self.assertEqual(self.ssh.actions, [])

    def test_source_must_be_inside_checkout_scratch_without_traversal(self):
        other = self.root / "outside"
        other.mkdir()
        for source in (other, self.source / ".." / "frozen", self.root / "build" / "ha"):
            with self.subTest(source=source):
                self.failure(source=source)
        self.assertEqual(self.ssh.actions, [])

    def test_symlink_source_parent_and_file_are_refused(self):
        alias = self.source.parent / "alias"
        alias.symlink_to(self.source, target_is_directory=True)
        self.failure(source=alias)
        alias.unlink()
        (self.source / "link").symlink_to(self.source / "Dockerfile")
        self.failure()
        (self.source / "link").unlink()
        self.source.rename(self.source.parent / "real")
        self.source.symlink_to(self.source.parent / "real", target_is_directory=True)
        self.failure()
        self.assertEqual(self.ssh.actions, [])

    def test_special_and_hardlinked_files_are_refused_without_reading_them(self):
        path = self.source / "pipe"
        os.mkfifo(path)
        self.failure()
        path.unlink()
        os.link(self.source / "Dockerfile", path)
        self.failure()
        self.assertEqual(self.ssh.actions, [])

    def test_symlink_scratch_ancestor_is_refused(self):
        scratch = self.source.parent
        real = self.root / "other-scratch"
        scratch.rename(real)
        scratch.symlink_to(real, target_is_directory=True)
        self.failure()
        self.assertEqual(self.ssh.actions, [])

    def test_dot_and_secret_looking_files_and_directories_are_refused(self):
        for name in (".env", ".git", "demo.env", "key.pem", "id_ed25519", "secrets.yaml", "credentials.json", "tokens.txt"):
            with self.subTest(name=name):
                path = self.source / name
                path.write_text(SECRET)
                self.failure()
                path.unlink()
        path = self.source / ".hidden"
        path.mkdir()
        self.failure()
        self.assertEqual(self.ssh.actions, [])

    def test_bounded_file_count_bytes_and_archive(self):
        for constant, value in (("MAX_FILES", 2), ("MAX_FILE", 1), ("MAX_BYTES", 1), ("MAX_ARCHIVE", 1)):
            with self.subTest(constant=constant), mock.patch.object(app, constant, value):
                self.failure()
        self.assertEqual(self.ssh.actions, [])

    def test_actual_size_limits_are_inclusive_and_reject_one_extra_byte(self):
        overhead = sum(p.stat().st_size for p in self.source.rglob("*") if p.is_file())
        first, second = self.source / "first.bin", self.source / "second.bin"
        with first.open("wb") as stream:
            stream.truncate(16 * 1024 * 1024)
        with second.open("wb") as stream:
            stream.truncate(16 * 1024 * 1024 - overhead)
        frozen = app.freeze_source(str(self.source), [self.root], hc.SECRET_NAME, SLUG)
        self.assertLessEqual(len(base64.b64decode(frozen["archive"])), 40 * 1024 * 1024)
        del frozen
        with second.open("ab") as stream:
            stream.write(b"x")
        with self.assertRaisesRegex(app.InstallError, "32 MiB"):
            app.freeze_source(str(self.source), [self.root], hc.SECRET_NAME, SLUG)
        second.unlink()
        with first.open("ab") as stream:
            stream.write(b"x")
        with self.assertRaisesRegex(app.InstallError, "16 MiB"):
            app.freeze_source(str(self.source), [self.root], hc.SECRET_NAME, SLUG)

    def test_actual_entry_limit_accepts_2048_and_refuses_2049(self):
        existing = len(list(self.source.rglob("*")))
        for i in range(2048 - existing):
            (self.source / f"empty-{i}").touch()
        app.freeze_source(str(self.source), [self.root], hc.SECRET_NAME, SLUG)
        (self.source / "extra").touch()
        with self.assertRaisesRegex(app.InstallError, "2048"):
            app.freeze_source(str(self.source), [self.root], hc.SECRET_NAME, SLUG)

    def test_missing_dockerfile_and_alternate_manifests_are_refused(self):
        docker = self.source / "Dockerfile"
        docker.write_text("")
        self.failure()
        docker.write_text("FROM scratch\n")
        for name in ("config.yml", "config.json", "build.yaml", "build.json"):
            p = self.source / name
            p.write_text("{}")
            self.failure()
            p.unlink()
        self.assertEqual(self.ssh.actions, [])

    def test_manifest_json_is_strict_and_does_not_echo_unsafe_values(self):
        path = self.source / "config.yaml"
        for body in ("ingress: true\n", '{"ingress": true, "ingress": false}', '{"value": NaN}',
                     '{"value": !!python/object/apply:os.system}', "[]", "null"):
            with self.subTest(body=body):
                path.write_text(body)
                self.failure()
        self.assertEqual(self.ssh.actions, [])

    def test_manifest_refuses_privilege_ports_live_actions_and_nonlocal_images(self):
        changes = [{"ingress": False}, {"panel_admin": False}, {"ingress_port": 4801}, {"slug": "other"},
                   {"ports": {"4800/tcp": 4800}}, {"options": {"live_actions": True}},
                   {"options": {"live_actions": 0}}, {"options": {"live_actions": False, "password": SECRET}},
                   {"schema": {"live_actions": "bool?"}}, {"image": "example/image"},
                   {"map": ["config:rw"]}, {"docker_api": True}, {"hassio_api": True},
                   {"host_network": True}, {"privileged": ["SYS_ADMIN"]}, {"environment": {"TOKEN": SECRET}},
                   {"arch": []}, {"arch": ["amd64", "amd64"]}, {"version": ""}, {"startup": "services"}]
        for update in changes:
            with self.subTest(update=update):
                (self.source / "config.yaml").write_text(json.dumps({**manifest(), **update}))
                self.failure()
        self.assertEqual(self.ssh.actions, [])

    def test_preexisting_app_source_or_store_are_refused_before_backup(self):
        cases = ("app", "directory", "symlink", "dangling_symlink", "store")
        for case in cases:
            with self.subTest(case=case):
                target = self.addons / SLUG
                self.ssh.installed = ({"slug": EXACT, "version": "9.0", "state": "stopped", "options": SECRET}
                                      if case == "app" else None)
                self.ssh.store_row = {"slug": EXACT} if case == "store" else None
                if case == "directory":
                    target.mkdir()
                    (target / "user-data").write_text("keep")
                elif case in ("symlink", "dangling_symlink"):
                    target.symlink_to(self.source if case == "symlink" else self.root / "missing")
                self.ssh.actions.clear()
                self.ssh.commands.clear()
                self.failure()
                self.assertNotIn("backup", self.ssh.actions)
                self.assertFalse(any(c.startswith("apps uninstall") for c in self.ssh.commands))
                if case == "directory":
                    self.assertEqual((target / "user-data").read_text(), "keep")
                    (target / "user-data").unlink()
                    target.rmdir()
                elif target.is_symlink():
                    target.unlink()

    def test_unhealthy_or_unsupported_supervisor_is_refused(self):
        for key in ("healthy", "supported"):
            self.ssh.health[key] = False
            self.failure()
            self.assertNotIn("backup", self.ssh.actions)
            self.ssh.health[key] = True

    def test_source_existence_error_is_not_treated_as_absence(self):
        self.ssh.ns["exists"] = mock.Mock(side_effect=PermissionError(SECRET))
        self.failure()
        self.assertNotIn("backup", self.ssh.actions)
        self.assertFalse((self.addons / SLUG).exists())

    def test_backup_or_initial_check_failure_changes_no_source(self):
        for cmd in ("backups new --name agent-app-" + SLUG, "core check"):
            with self.subTest(cmd=cmd):
                self.ssh.actions.clear()
                self.ssh.fail_cli = {cmd: True}
                message = self.failure()
                self.assertNotIn("upload", self.ssh.actions)
                self.assertFalse((self.addons / SLUG).exists())
                if cmd == "core check":
                    self.assertIn("backup abcd1234", message)

    def test_failed_or_lost_upload_can_remove_only_proven_owned_files(self):
        original = self.ssh.ns["upload"]

        def partial(payload, parent):
            original(payload, parent)
            raise self.ssh.ns["Refused"]("filesystem_or_response")

        self.ssh.ns["upload"] = partial
        message = self.failure()
        self.assertIn("backup abcd1234", message)
        self.assertIn("source /addons/" + SLUG, message)
        self.assertFalse((self.addons / SLUG).exists())
        self.assertEqual(self.entry()["result"], "install_failed_restored")
        self.assertNotIn("install", self.ssh.actions)

    def test_store_failure_removes_source_without_uninstall(self):
        self.ssh.fail_cli["store reload"] = True
        self.failure()
        self.assertFalse((self.addons / SLUG).exists())
        self.assertFalse(any(c.startswith("apps uninstall") for c in self.ssh.commands))
        self.assertEqual(self.entry()["result"], "rollback_failed")  # the post-cleanup store reload also failed

    def test_store_version_or_origin_mismatch_refuses_build(self):
        original = self.ssh.cli

        for field, value in (("version_latest", "0.0.0"), ("repository", "other")):
            with self.subTest(field=field):
                if self.log.exists():
                    self.log.unlink()
                self.ssh.actions.clear()

                def changed(args, **kw):
                    result = original(args, **kw)
                    if args[1:-1] == ["store", "reload"] and self.ssh.store_row:
                        self.ssh.store_row[field] = value
                    return result

                self.ssh.ns["subprocess"].run = changed
                self.failure()
                self.assertNotIn("install", self.ssh.actions)
                self.assertFalse((self.addons / SLUG).exists())
                self.assertEqual(self.entry()["result"], "install_failed_restored")

    def test_async_or_malformed_install_acknowledgment_never_authorizes_uninstall(self):
        self.ssh.fail_cli[f"apps install {EXACT}"] = lambda args: subprocess.CompletedProcess(
            args, 0, json.dumps({"result": "ok", "data": {"job_id": "still-running", "options": SECRET}}), SECRET)
        self.failure()
        self.assertNotIn("uninstall", self.ssh.actions)
        self.assertNotIn("cleanup", self.ssh.actions)
        self.assertTrue((self.addons / SLUG).is_dir())

    def test_install_failure_is_uncertain_and_never_uninstalls(self):
        self.ssh.fail_cli[f"apps install {EXACT}"] = True
        message = self.failure()
        self.assertIn("safe automatic rollback", message)
        self.assertIn("installed=false state=absent", message)
        self.assertIn("backup abcd1234", message)
        self.assertTrue((self.addons / SLUG).is_dir())
        self.assertNotIn("cleanup", self.ssh.actions)
        self.assertNotIn("uninstall", self.ssh.actions)
        self.assertEqual(self.entry()["result"], "rollback_failed")

    def test_lost_install_response_after_creation_keeps_stopped_app_and_source(self):
        def lost(payload):
            reply = self.ssh.ns["execute"]("install", payload)
            self.assertTrue(reply["ok"])
            raise subprocess.TimeoutExpired(["ssh", SECRET], 1200, output=SECRET, stderr=SECRET)

        self.ssh.hooks["install"] = lost
        message = self.failure()
        self.assertIn("installed=true state=stopped", message)
        self.assertTrue((self.addons / SLUG).is_dir())
        self.assertNotIn("uninstall", self.ssh.actions)
        self.assertNotIn("cleanup", self.ssh.actions)

    def test_cli_install_timeout_does_not_claim_ownership(self):
        def timeout(args):
            raise subprocess.TimeoutExpired(args, 900, output=SECRET)
        self.ssh.fail_cli[f"apps install {EXACT}"] = timeout
        self.assertIn("cli_timeout", self.failure())
        self.assertNotIn("uninstall", self.ssh.actions)

    def test_start_failure_uninstalls_only_acknowledged_new_slug(self):
        self.ssh.fail_cli[f"apps start {EXACT}"] = True
        message = self.failure()
        self.assertIn("new app/source removed", message)
        self.assertIsNone(self.ssh.installed)
        self.assertFalse((self.addons / SLUG).exists())
        self.assertEqual(self.entry()["result"], "install_failed_restored")
        self.assertIn(f"apps uninstall {EXACT}", self.ssh.commands)
        self.assertFalse(any("--remove-config" in c for c in self.ssh.commands))
        self.assertEqual(self.entry()["backup"], "abcd1234")

    def test_failed_final_core_check_stops_uninstalls_cleans_and_rechecks(self):
        original = self.ssh.cli
        checks = 0

        def fail_final(args, **kw):
            nonlocal checks
            if args[1:-1] == ["core", "check"]:
                checks += 1
                if checks == 2:
                    return subprocess.CompletedProcess(args, 1, SECRET, SECRET)
            return original(args, **kw)

        self.ssh.ns["subprocess"].run = fail_final
        self.failure()
        self.assertEqual(checks, 3)
        self.assertIn(f"apps stop {EXACT}", self.ssh.commands)
        self.assertIn(f"apps uninstall {EXACT}", self.ssh.commands)
        self.assertFalse((self.addons / SLUG).exists())
        self.assertEqual(self.entry()["result"], "install_failed_restored")

    def test_wrong_installed_version_cannot_authorize_uninstall(self):
        self.ssh.hooks["status"] = lambda _: self.ssh.installed.update(version="9.9.9")
        message = self.failure()
        self.assertIn("version=9.9.9", message)
        self.assertNotIn(f"apps uninstall {EXACT}", self.ssh.commands)
        self.assertTrue((self.addons / SLUG).exists())
        self.assertEqual(self.entry()["result"], "rollback_failed")

    def test_stopped_final_state_is_failure_not_success(self):
        self.ssh.hooks["status"] = lambda _: self.ssh.installed.update(state="stopped") if self.ssh.installed else None
        self.assertIn("final app verification failed", self.failure())
        self.assertEqual(self.entry()["result"], "install_failed_restored")

    def test_source_creation_race_never_overwrites_or_removes_user_data(self):
        def race(_):
            target = self.addons / SLUG
            target.mkdir()
            (target / "user-data").write_text("keep")
        self.ssh.hooks["upload"] = race
        self.failure()
        self.assertEqual((self.addons / SLUG / "user-data").read_text(), "keep")
        self.assertNotIn("install", self.ssh.actions)
        self.assertNotIn(f"apps uninstall {EXACT}", self.ssh.commands)

    def test_concurrent_install_race_never_uninstalls_even_matching_version(self):
        def race(_):
            self.ssh.installed = {"slug": EXACT, "version": "1.2.3", "state": "stopped", "options": SECRET}
        self.ssh.hooks["install"] = race
        self.assertIn("installed=true state=stopped", self.failure())
        self.assertNotIn(f"apps uninstall {EXACT}", self.ssh.commands)
        self.assertTrue((self.addons / SLUG).exists())

    def test_changed_source_or_marker_prevents_rollback_deletion(self):
        for name in ("user-data", ".ha-change-owner", "config.yaml"):
            with self.subTest(name=name):
                target = self.addons / SLUG
                if target.exists():
                    for child in (target / "src").iterdir():
                        child.unlink()
                    (target / "src").rmdir()
                    for child in target.iterdir():
                        child.unlink()
                    target.rmdir()
                self.ssh.installed = self.ssh.store_row = None
                self.ssh.commands.clear()

                def changed(_, name=name):
                    (self.addons / SLUG / name).write_text("keep")
                self.ssh.hooks["start"] = changed
                self.failure()
                self.assertEqual((target / name).read_text(), "keep")
                self.assertNotIn(f"apps uninstall {EXACT}", self.ssh.commands)

    def test_rollback_uninstall_failure_keeps_backup_and_source_and_reports_stopped(self):
        self.ssh.fail_cli = {f"apps start {EXACT}": True, f"apps uninstall {EXACT}": True}
        message = self.failure()
        self.assertIn("backup abcd1234", message)
        self.assertIn("source /addons/" + SLUG, message)
        self.assertIn("installed=true state=stopped", message)
        self.assertTrue((self.addons / SLUG).is_dir())
        self.assertEqual(self.entry()["result"], "rollback_failed")

    def test_rollback_stop_failure_never_uninstalls_running_app(self):
        def fail(_):
            self.ssh.installed["state"] = "started"
            self.ssh.fail_cli[f"apps stop {EXACT}"] = True
            raise OSError(SECRET)
        self.ssh.hooks["start"] = fail
        self.assertIn("installed=true state=started", self.failure())
        self.assertNotIn(f"apps uninstall {EXACT}", self.ssh.commands)

    def test_version_change_during_stop_cannot_authorize_uninstall(self):
        original = self.ssh.cli

        def changed(args, **kw):
            result = original(args, **kw)
            if args[1:-1] == ["apps", "stop", EXACT]:
                self.ssh.installed["version"] = "9.0.0"
            return result

        def fail(_):
            self.ssh.installed["state"] = "started"
            raise OSError("start response lost")

        self.ssh.ns["subprocess"].run = changed
        self.ssh.hooks["start"] = fail
        self.failure()
        self.assertNotIn(f"apps uninstall {EXACT}", self.ssh.commands)

    def test_cleanup_rechecks_file_hash_before_each_unlink(self):
        original = self.ssh.ns["inspect"]

        def changed(payload, fd, partial=False):
            entries = original(payload, fd, partial)
            if partial:
                (self.addons / SLUG / "src" / "run.sh").write_text("new user data")
            return entries

        self.ssh.ns["inspect"] = changed
        self.ssh.fail_cli[f"apps start {EXACT}"] = True
        self.failure()
        self.assertEqual((self.addons / SLUG / "src" / "run.sh").read_text(), "new user data")
        self.assertEqual(self.entry()["result"], "rollback_failed")

    def test_malformed_remote_or_cli_data_never_echoes_raw_options(self):
        self.ssh.bad_replies["preflight"] = json.dumps({"ok": False, "code": SECRET, "options": SECRET})
        self.assertNotIn(SECRET, self.failure())
        self.ssh.bad_replies["preflight"] = SECRET
        self.assertNotIn(SECRET, self.failure())
        self.ssh.bad_replies.clear()
        self.ssh.fail_cli["apps"] = lambda args: subprocess.CompletedProcess(args, 0, json.dumps({
            "result": "ok", "data": {"addons": SECRET}}), SECRET)
        self.assertNotIn(SECRET, self.failure())

    def test_remote_archive_refuses_traversal_symlink_and_duplicate_members(self):
        frozen = app.freeze_source(str(self.source), [self.root], hc.SECRET_NAME, SLUG)
        for kind in ("traversal", "symlink", "duplicate"):
            with self.subTest(kind=kind):
                stream = io.BytesIO()
                with tarfile.open(fileobj=stream, mode="w") as tar:
                    member = tarfile.TarInfo("../escape" if kind == "traversal" else "safe")
                    if kind == "symlink":
                        member.type = tarfile.SYMTYPE
                        member.linkname = "/config"
                    tar.addfile(member)
                    if kind == "duplicate":
                        tar.addfile(member)
                body = stream.getvalue()
                payload = {**frozen, "slug": SLUG, "token": "test",
                           "archive": base64.b64encode(body).decode(), "digest": hashlib.sha256(body).hexdigest()}
                reply = self.ssh.ns["execute"]("upload", payload)
                self.assertFalse(reply["ok"])
                self.assertFalse((self.addons / SLUG).exists())
                self.assertFalse((self.root / "escape").exists())


if __name__ == "__main__":
    unittest.main()
