"""Tests for tools/test_ha/: the package generator against the DemoHouse document, verify.py, the VM definition and the scripts.

The DemoHouse document is read from the committed Swift source (apple/Sources/HassDemoHouse/DemoHouseDocument.swift), so these
tests need neither Swift nor a live Home Assistant. No real house values appear here; the checks are structural.
"""
from __future__ import annotations

import ast
import contextlib
import io
import json
import os
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TEST_HA = ROOT / "tools" / "test_ha"
sys.path.insert(0, str(TEST_HA))
import gen_demo_package as gen  # noqa: E402
import verify  # noqa: E402

DOCUMENT_SWIFT = ROOT / "apple/Sources/HassDemoHouse/DemoHouseDocument.swift"
RESTING = {"light": "off", "switch": "off", "fan": "off", "input_boolean": "off", "binary_sensor": "off", "sensor": "0",
           "number": "0", "input_number": "0", "lock": "locked", "cover": "closed", "alarm_control_panel": "disarmed",
           "climate": "off", "vacuum": "docked", "media_player": "off", "person": "home", "weather": "sunny", "camera": "idle",
           "script": "off", "todo": "0", "schedule": "off", "select": "unknown", "input_select": "unknown"}


def demo_document() -> dict:
    text = DOCUMENT_SWIFT.read_text()
    return json.loads(re.search(r'"""\n(.*?)\n\s*"""', text, re.S).group(1))


def ids_in(document) -> list:
    found = set()

    def walk(node):
        if isinstance(node, str):
            if gen.ENTITY_ID.match(node):
                found.add(node)
        elif isinstance(node, list):
            for item in node:
                walk(item)
        elif isinstance(node, dict):
            for key, value in node.items():
                if gen.ENTITY_ID.match(key):
                    found.add(key)
                walk(value)

    walk(document)
    return sorted(found)


def demo_export() -> dict:
    document = demo_document()
    entities = [{"entity_id": i, "state": RESTING.get(i.split(".")[0], "unknown"), "attributes": {}} for i in ids_in(document)]
    return {"version": 1, "document": document, "entities": entities}


class GeneratorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.export = demo_export()
        cls.pkg = gen.build(cls.export)

    def test_every_id_has_exactly_one_source(self):
        ids = {e["entity_id"] for e in self.export["entities"]}
        self.assertGreater(len(ids), 600)
        self.assertEqual(set(self.pkg.sources), ids)

    def test_counts_by_source_cover_everything(self):
        info = gen.summary(self.pkg)
        self.assertEqual(info["total"], len(self.export["entities"]))
        self.assertEqual(sum(info["by_source"].values()), info["total"])
        # the plan: the native and template route covers all but the todo, valve, camera and remote ids
        self.assertEqual(info["by_source"]["component"], sum(1 for i in self.pkg.sources if i.split(".")[0] in gen.COMPONENT_DOMAINS))
        self.assertGreaterEqual(info["total"] - info["by_source"]["component"], 600)

    def test_domains_go_to_the_expected_sources(self):
        for entity_id, source in self.pkg.sources.items():
            domain = entity_id.split(".")[0]
            expected = ("helper" if domain in gen.HELPER_DOMAINS else "template" if domain in gen.TEMPLATE_DOMAINS
                        else "extra" if domain in gen.EXTRA_TEMPLATE_DOMAINS else "component" if domain in gen.COMPONENT_DOMAINS
                        else domain)
            self.assertEqual(source, expected, entity_id)

    def test_component_data_matches_the_ids(self):
        for domain in gen.COMPONENT_DOMAINS:
            ids = sorted(f"{domain}.{e['object_id']}" for e in self.pkg.component[domain])
            self.assertEqual(ids, sorted(i for i in self.pkg.sources if i.startswith(domain + ".")))

    def test_helpers_use_the_object_ids_and_backing_never_collides(self):
        ids = set(self.pkg.sources)
        for domain in gen.HELPER_DOMAINS:
            for obj in self.pkg.helpers[domain]:
                if obj.startswith("demo_state_"):
                    self.assertNotIn(f"{domain}.{obj}", ids)
                else:
                    self.assertIn(f"{domain}.{obj}", ids)
        self.assertEqual(gen.summary(self.pkg)["backing_helpers"], sum(
            1 for i in ids if i.split(".")[0] in gen.BACKED))

    def test_template_names_slug_to_their_ids(self):
        for item in self.pkg.templates + self.pkg.extra:
            (domain, entries), = item.items()
            for entry in entries:
                self.assertEqual(gen.slug(entry["name"]), entry["default_entity_id"].split(".", 1)[1])
                self.assertEqual(entry["default_entity_id"].split(".")[0], domain)
                self.assertIn(entry["default_entity_id"], self.pkg.sources)

    def test_template_only_keys_are_never_lists_or_dicts(self):
        count = 0
        for item in self.pkg.templates + self.pkg.extra:
            (domain, entries), = item.items()
            for entry in entries:
                for key, value in entry.items():
                    if key in gen.TEMPLATE_STRING_KEYS:
                        count += 1
                        self.assertNotIsInstance(value, (list, dict), f"{domain}.{key}")
        self.assertGreater(count, 500)
        select = next(e for item in self.pkg.templates for e in item.get("select", []))
        self.assertEqual(select["options"], "{{ ['Option 1', 'Option 2'] }}")
        climate = next(e for item in self.pkg.extra for e in item.get("climate", []))
        self.assertEqual(climate["hvac_modes"], "{{ ['off', 'heat', 'cool'] }}")

    def test_media_player_is_served_by_the_component_not_a_template(self):
        self.assertTrue(any(i.startswith("media_player.") for i in self.pkg.sources))
        for item in self.pkg.templates + self.pkg.extra:
            self.assertNotIn("media_player", item)
        self.assertEqual(self.pkg.sources[next(i for i in self.pkg.sources if i.startswith("media_player."))], "component")

    def test_summary_reports_served_by_platform(self):
        served = gen.summary(self.pkg)["served_by"]
        self.assertEqual(sum(sum(d.values()) for d in served.values()), len(self.pkg.sources))
        self.assertIn("select", served["template"])
        self.assertIn("climate", served["extra"])
        self.assertIn("media_player", served["component"])

    def test_scripts_include_the_bare_service_ids(self):
        bare = gen.bare_script_ids(self.export["document"])
        self.assertGreaterEqual(len(bare), 25)
        self.assertNotIn("demo_bedroom_1_humidifier", bare)  # a schedule id, not a script
        for obj in bare:
            self.assertIn(obj, self.pkg.scripts)
        self.assertEqual(len(self.pkg.automations), 3)

    def test_no_real_values_only_demo_names(self):
        text = gen.package_yaml(self.pkg) + gen.extra_yaml(self.pkg) + gen.house_json(self.export)
        self.assertNotRegex(text, r"https?://")
        self.assertNotRegex(text, r"\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b")
        self.assertNotRegex(text, r"[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}")
        for entity_id in self.pkg.sources:
            self.assertRegex(entity_id, gen.ENTITY_ID)

    def test_resting_state_comes_from_the_export(self):
        export = demo_export()
        for entity in export["entities"]:
            if entity["entity_id"].startswith("binary_sensor."):
                entity["state"] = "on"
        pkg = gen.build(export)
        sensors = [e for item in pkg.templates for e in item.get("binary_sensor", [])]
        self.assertTrue(sensors and all(s["state"] == "{{ true }}" for s in sensors))

    def test_house_json_is_the_document_within_the_limit(self):
        text = gen.house_json(self.export)
        self.assertEqual(json.loads(text), self.export["document"])
        self.assertLessEqual(len(text.encode()), gen.HOUSE_BYTE_LIMIT)
        big = {"version": 1, "document": {"x": "a" * (gen.HOUSE_BYTE_LIMIT + 1)}, "entities": []}
        with self.assertRaises(gen.GenError):
            gen.house_json(big)

    def test_unknown_domain_stops_the_run(self):
        export = {"version": 1, "document": {}, "entities": [{"entity_id": "garbage.demo_x", "state": "x", "attributes": {}}]}
        with self.assertRaises(gen.GenError):
            gen.build(export)

    def test_write_all_writes_the_four_outputs(self):
        with tempfile.TemporaryDirectory() as tmp:
            gen.write_all(self.export, Path(tmp))
            for rel in ("config/packages/demo_house.yaml", "config/packages/demo_house_extra.yaml", "config/fenton_home/house.json",
                        "config/custom_components/fenton_demo/demo_data.json"):
                self.assertTrue((Path(tmp) / rel).stat().st_size > 0, rel)

    def test_main_reports_a_summary_and_errors(self):
        with tempfile.TemporaryDirectory() as tmp:
            export = Path(tmp) / "e.json"
            export.write_text(json.dumps(self.export))
            out, err = io.StringIO(), io.StringIO()
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                self.assertEqual(gen.main(["--export", str(export), "--out", str(Path(tmp) / "o")]), 0)
                self.assertEqual(gen.main(["--export", str(Path(tmp) / "missing.json")]), 1)
            self.assertEqual(json.loads(out.getvalue())["total"], len(self.export["entities"]))
            self.assertIn("gen_demo_package:", err.getvalue())

    def test_load_export_rejects_bad_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            for body in ('{"version": 2, "document": {}, "entities": []}', '{"version": 1}',
                         '{"version": 1, "document": {}, "entities": [{"entity_id": "light.kitchen"}]}', "not json"):
                path = Path(tmp) / "x.json"
                path.write_text(body)
                with self.assertRaises(gen.GenError, msg=body):
                    gen.load_export(path)

    def test_dump_emits_block_yaml_with_json_scalars(self):
        lines = gen.dump({"a": {"b": [1, "x: y", {"c": True, "d": [] }]}, "e": None, "f": {}})
        self.assertEqual(lines, ['a:', '  b:', '    - 1', '    - "x: y"', '    - c: true', '      d: []', 'e: null', 'f: {}'])

    def test_generated_templates_use_jinja_only_in_strings(self):
        text = gen.package_yaml(self.pkg)
        self.assertIn("is_state('input_boolean.demo_state_light_", text)
        for line in text.splitlines():
            if "{{" in line:
                self.assertRegex(line, r'"[^"]*\{\{[^"]*\}\}[^"]*"')

    def test_number_and_title_helpers(self):
        self.assertEqual(gen.number_of("x", 3), 3)
        self.assertEqual(gen.number_of("2.5"), 2.5)
        self.assertEqual(gen.title("demo_bedroom_1_alarm_1"), "Demo Bedroom 1 Alarm 1")
        self.assertEqual(gen.slug("Demo Bedroom 1 Alarm 1"), "demo_bedroom_1_alarm_1")

    def test_committed_export_if_present_matches_the_source_document(self):
        path = ROOT / "build/ha/demo-house.json"
        if not path.exists():
            self.skipTest("no exported file (tools/test_ha/export_demo_house.sh)")
        export = gen.load_export(path)
        self.assertEqual(export["document"], demo_document())
        self.assertEqual(sorted(e["entity_id"] for e in export["entities"]), ids_in(demo_document()))
        self.assertEqual(set(gen.build(export).sources), {e["entity_id"] for e in export["entities"]})


class VerifyTests(unittest.TestCase):
    def states(self, ids, state="off"):
        return [{"entity_id": i, "state": state, "attributes": {}} for i in ids]

    def test_all_present_is_clean(self):
        ids = ["light.demo_a", "sensor.demo_b"]
        self.assertEqual(verify.check_states(ids, self.states(ids)), [])

    def test_missing_and_unavailable_are_reported(self):
        ids = ["light.demo_a", "sensor.demo_b", "todo.demo_c"]
        states = self.states(ids[:2]) + [{"entity_id": "todo.demo_c", "state": "unavailable"}]
        problems = verify.check_states(ids, states[:2] + states[2:])
        self.assertIn("no usable state ('unavailable'): todo.demo_c", problems)
        problems = verify.check_states(ids, self.states(ids[:1]))
        self.assertIn("missing: sensor.demo_b", problems)
        self.assertIn("count: found 1 of 3 demo ids", problems)

    def test_unknown_state_counts_as_present_and_extra_entities_are_ignored(self):
        ids = ["select.demo_a"]
        self.assertEqual(verify.check_states(ids, self.states(ids + ["light.demo_other"], "unknown")), [])

    def test_against_the_demo_house_with_one_removed(self):
        export = demo_export()
        ids = verify.expected_ids(export)
        self.assertEqual(verify.check_states(ids, self.states(ids)), [])
        self.assertEqual(len(verify.check_states(ids, self.states(ids[1:]))), 2)

    def test_check_house(self):
        document = {"schema": 2, "x": 1}
        self.assertEqual(verify.check_house(document, document), [])
        self.assertEqual(verify.check_house({"config": document}, document), [])
        self.assertEqual(len(verify.check_house({"schema": 1}, document)), 1)
        # the live shape: schema lifted out of the document into the wrapper
        self.assertEqual(verify.check_house({"schema": 2, "hash": "h", "config": {"a": 1}}, {"schema": 2, "a": 1}), [])

    def test_empty_input_text_is_a_usable_state(self):
        states = [{"entity_id": "input_text.demo_a", "state": ""}, {"entity_id": "light.demo_b", "state": ""}]
        problems = verify.check_states(["input_text.demo_a", "light.demo_b"], states)
        self.assertEqual(problems, ["no usable state (''): light.demo_b"])

    def test_frames_round_trip_through_a_fake_socket(self):
        class Sock:
            def __init__(self, data):
                self.data, self.sent = data, b""

            def recv(self, n):
                chunk, self.data = self.data[:n], self.data[n:]
                return chunk

            def sendall(self, data):
                self.sent += data

        def server(payload, opcode=1, fin=True):  # unmasked server frame
            import struct
            head = bytes([(0x80 if fin else 0) | opcode])
            n = len(payload)
            head += bytes([n]) if n < 126 else bytes([126]) + struct.pack(">H", n) if n < 65536 else bytes([127]) + struct.pack(">Q", n)
            return head + payload

        big = b"x" * 70000
        data = server(b"he", fin=False) + server(b"llo", opcode=0) + server(b"p", opcode=9) + server(big) + server(b"y" * 300)
        sock = Sock(data)
        self.assertEqual(verify.read_message(sock), "hello")
        self.assertEqual(verify.read_message(sock), big.decode())
        self.assertEqual(sock.sent[0] & 0x0F, 10)  # the ping was answered with a pong
        self.assertEqual(verify.read_message(sock), "y" * 300)
        with self.assertRaises(ConnectionError):
            verify.read_message(Sock(server(b"", opcode=8)))
        with self.assertRaises(ConnectionError):
            verify.read_message(Sock(b""))

    def test_client_frames_are_masked(self):
        for size in (5, 200, 70000):
            raw = verify.frame(b"a" * size)
            self.assertEqual(raw[0], 0x81)
            self.assertTrue(raw[1] & 0x80)

    def test_call_returns_the_matching_result_and_raises_on_failure(self):
        replies = [json.dumps({"id": 9, "success": True, "result": "other"}), json.dumps({"id": 1, "success": True, "result": [1]}),
                   json.dumps({"id": 2, "success": False, "error": {"code": "unknown_command"}})]
        original = verify.read_message
        verify.read_message = lambda sock: replies.pop(0)
        try:
            class Sock:
                def sendall(self, data):
                    pass
            self.assertEqual(verify.call(Sock(), 1, {"type": "get_states"}), [1])
            with self.assertRaises(ConnectionError) as ctx:
                verify.call(Sock(), 2, {"type": "x"})
            self.assertIn("unknown_command", str(ctx.exception))
        finally:
            verify.read_message = original

    def run_main(self, argv, env=None):
        out, err = io.StringIO(), io.StringIO()
        saved = dict(os.environ)
        os.environ.pop("FENTON_TEST_HA_URL", None)
        os.environ.pop("FENTON_TEST_HA_TOKEN", None)
        os.environ.update(env or {})
        try:
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                code = verify.main(argv)
        finally:
            os.environ.clear()
            os.environ.update(saved)
        return code, out.getvalue(), err.getvalue()

    def test_main_offline_and_without_credentials(self):
        export = demo_export()
        ids = verify.expected_ids(export)
        with tempfile.TemporaryDirectory() as tmp:
            ex, st = Path(tmp) / "e.json", Path(tmp) / "s.json"
            ex.write_text(json.dumps(export))
            st.write_text(json.dumps(self.states(ids)))
            code, out, _ = self.run_main(["--export", str(ex), "--states", str(st)])
            self.assertEqual(code, 0)
            self.assertIn(f"{len(ids)} of {len(ids)} ids present", out)
            st.write_text(json.dumps(self.states(ids[3:])))
            code, out, _ = self.run_main(["--export", str(ex), "--states", str(st)])
            self.assertEqual(code, 1)
            self.assertIn("missing: " + ids[0], out)
            code, _, err = self.run_main(["--export", str(ex)])
            self.assertEqual(code, 1)
            self.assertIn("FENTON_TEST_HA_URL", err)
            self.assertEqual(self.run_main(["--export", str(Path(tmp) / "none.json"), "--states", str(st)])[0], 1)

    def test_a_token_never_appears_in_an_error(self):
        token = "tok" + "x" * 40
        code, out, err = self.run_main(["--export", str(ROOT / "build/ha/none.json")],
                                       {"FENTON_TEST_HA_URL": "http://127.0.0.1:9", "FENTON_TEST_HA_TOKEN": token})
        self.assertEqual(code, 1)
        self.assertNotIn(token, out + err)


class InstanceDefinitionTests(unittest.TestCase):
    def test_vm_definition_matches_the_plan(self):
        xml = (TEST_HA / "vm.xml.tmpl").read_text()
        body = re.sub(r"<!--.*?-->", "", xml, flags=re.S)
        for needle in ('<vcpu placement="static">2</vcpu>', "<shares>256</shares>", '<memory unit="KiB">3145728</memory>',
                       'bridge="nm-bridge"', 'firmware="efi"', 'name="secure-boot"', "org.qemu.guest_agent.0", "@UUID@", "@MAC@", "@DISK@",
                       "pc-i440fx-noble-v2", "tpm-crb", 'bus="ps2"', "ich9-ehci1", "/var/lib/libvirt/qemu/nvram/@NAME@_VARS.fd"):
            self.assertIn(needle, body)
        for absent in ("<graphics", "<hostdev", "autostart", "<sound"):
            self.assertNotIn(absent, body)

    def test_pin_has_a_sha256(self):
        pin = dict(line.split("=", 1) for line in (TEST_HA / "haos.pin").read_text().splitlines() if "=" in line and not line.startswith("#"))
        self.assertRegex(pin["HAOS_SHA256"], r"^[0-9a-f]{64}$")
        self.assertIn(pin["HAOS_VERSION"], pin["HAOS_URL"])

    def test_scripts_parse_and_rebuild_dry_run_touches_nothing(self):
        for name in ("rebuild.sh", "provision.sh", "export_demo_house.sh"):
            self.assertEqual(subprocess.run(["bash", "-n", str(TEST_HA / name)]).returncode, 0, name)
        with tempfile.TemporaryDirectory() as tmp:
            shim = Path(tmp) / "ssh"
            shim.write_text("#!/bin/sh\necho ssh was called >&2\nexit 99\n")
            shim.chmod(0o755)
            env = dict(os.environ, PATH=f"{tmp}:{os.environ['PATH']}")
            proc = subprocess.run(["bash", str(TEST_HA / "rebuild.sh"), "--dry-run"], capture_output=True, text=True, env=env)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertNotIn("ssh was called", proc.stderr)
        self.assertIn("<name>homeassistant-test</name>", proc.stdout)
        self.assertNotRegex(proc.stdout, r"@[A-Z]+@")
        self.assertIn("/home/sfenton/KVM/homeassistant-test/haos-test.qcow2", proc.stdout)
        self.assertIn("autostart stays off", proc.stdout)
        self.assertEqual(subprocess.run(["bash", str(TEST_HA / "rebuild.sh"), "--bogus"], capture_output=True).returncode, 2)

    def test_rebuild_refuses_an_existing_vm_and_keeps_the_mac_out_of_output(self):
        text = (TEST_HA / "rebuild.sh").read_text()
        self.assertIn("pass --destroy to replace it", text)
        self.assertIn("[ ! -e '$DISK' ]", text)
        self.assertIn("test-vm.mac", text)
        mac_file = ROOT / "build/ha/test-vm.mac"
        fake = "52:54:00:aa:bb:cc"
        proc = subprocess.run(["bash", str(TEST_HA / "rebuild.sh"), "--dry-run"], capture_output=True, text=True,
                              env={"PATH": os.defpath, "HOME": str(Path.home()), "TEST_HA_MAC": fake})
        self.assertNotIn(fake, proc.stdout + proc.stderr)
        self.assertIn("xx:xx:xx:xx:xx:xx", proc.stdout)
        if mac_file.exists():
            proc = subprocess.run(["bash", str(TEST_HA / "rebuild.sh"), "--dry-run"], capture_output=True, text=True)
            self.assertNotIn(mac_file.read_text().strip(), proc.stdout + proc.stderr)

    def test_destroy_names_only_the_test_vm(self):
        text = (TEST_HA / "rebuild.sh").read_text()
        self.assertIn('NAME="homeassistant-test"', text)
        self.assertNotRegex(text, r"destroy (homeassistant|openclaw)\b")

    def test_orchestrator_patch_guards_every_call(self):
        text = (TEST_HA / "orchestrator.patch").read_text()
        added = [l[1:].strip() for l in text.splitlines() if l.startswith("+") and not l.startswith("+++")]
        calls = [l for l in added if re.match(r"(start|stop)_test_ha_vm\b", l) and "()" not in l]
        guarded = [l for l in calls if "|| log_warn" in l]
        self.assertEqual(len(guarded), 2)
        self.assertEqual(len(calls) - len(guarded), 2)  # the start-test-vm / stop-test-vm subcommands
        self.assertTrue(text.startswith("--- a/compose_orchestrator.sh\n+++ b/compose_orchestrator.sh\n"))
        self.assertLess(text.index(" start_ha_vm\n"), text.index("+    start_test_ha_vm ||"))
        self.assertLess(text.index("stop_openclaw_vm\n"), text.index("+    stop_test_ha_vm ||"))

    def test_ssh_template_is_a_separate_alias_without_real_values(self):
        text = (TEST_HA / "ssh_config.template").read_text()
        self.assertIn("Host hass-test", text)
        self.assertNotRegex(text, r"\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b")
        self.assertNotIn("Host hass\n", text)

    def test_configuration_template_has_no_apns_and_no_secrets(self):
        text = (TEST_HA / "configuration.yaml.tmpl").read_text()
        self.assertIn("packages: !include_dir_named packages", text)
        self.assertIn("fenton_home:", text)
        code = "\n".join(l for l in text.lower().splitlines() if not l.lstrip().startswith("#"))
        self.assertNotRegex(code, r"apns|token|password|secret")


class UnitsTests(unittest.TestCase):
    def test_temperature_follows_the_unit_system(self):
        self.assertEqual(gen.temperature(21), 70)
        self.assertEqual(gen.temperature(21, "metric"), 21)
        with self.assertRaises(gen.GenError):
            gen.temperature(21, "kelvin")

    def test_template_has_no_unit_system_line(self):
        self.assertNotIn("unit_system", (TEST_HA / "configuration.yaml.tmpl").read_text())


class ComponentTests(unittest.TestCase):
    base = TEST_HA / "custom_components" / "fenton_demo"

    def test_every_module_parses_and_defines_its_platform(self):
        for name in ("__init__", "todo", "valve", "camera", "remote", "media_player"):
            tree = ast.parse((self.base / f"{name}.py").read_text())
            if name != "__init__":
                self.assertIn("async_setup_platform", {n.name for n in tree.body if isinstance(n, ast.AsyncFunctionDef)}, name)
        manifest = json.loads((self.base / "manifest.json").read_text())
        self.assertEqual(manifest["domain"], "fenton_demo")
        self.assertEqual(manifest["requirements"], [])

    def test_platforms_match_the_generator_domains(self):
        init = (self.base / "__init__.py").read_text()
        self.assertIn('PLATFORMS = ("todo", "valve", "camera", "remote", "media_player")', init)
        self.assertEqual(tuple(gen.COMPONENT_DOMAINS), ("todo", "valve", "camera", "remote", "media_player", "sun"))

    def test_every_component_domain_is_covered(self):
        init = (self.base / "__init__.py").read_text()
        platforms = re.search(r"PLATFORMS = \(([^)]*)\)", init).group(1)
        states = re.search(r"STATE_DOMAINS = \(([^)]*)\)", init).group(1)
        for domain in gen.COMPONENT_DOMAINS:
            self.assertTrue(f'"{domain}"' in platforms or f'"{domain}"' in states, domain)

    def test_sun_is_a_component_state_not_a_platform(self):
        """DemoHouse's ``sun.demo_sun_1`` cannot come from HA's built-in ``sun.sun``, so fenton_demo writes it as a state."""
        init = (self.base / "__init__.py").read_text()
        self.assertIn('STATE_DOMAINS = ("sun",)', init)
        self.assertNotIn('"sun"', init.split("STATE_DOMAINS")[0].split("PLATFORMS =")[1])

    def test_entity_ids_are_built_from_the_generated_object_ids(self):
        for name, domain in (("todo", "todo"), ("valve", "valve"), ("camera", "camera"), ("remote", "remote"),
                             ("media_player", "media_player")):
            self.assertIn(f'self.entity_id = f"{domain}.{{entry[\'object_id\']}}"', (self.base / f"{name}.py").read_text())


if __name__ == "__main__":
    unittest.main()
