"""Tests for tools/house_scan.py: detection, the allowlist, recorded debt, the local denylist and counts-only output.

Sample house data is assembled from parts so this file does not trip the scan it tests.
"""

from __future__ import annotations

import contextlib
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import house_scan  # noqa: E402

CFG = house_scan.load_config(Path("/nonexistent/house_scan.json"))


def ent(domain: str, object_id: str) -> str:
    """A ``domain.object_id`` literal built at run time so this file carries none."""
    return domain + "." + object_id


ATTIC = ent("light", "attic_lamp")
CELLAR = ent("sensor", "cellar_temp")
IP = ".".join(["10", "9", "8", "20"])
CGNAT = ".".join(["100", "101", "2", "3"])
PUBLIC_IP = ".".join(["8", "8", "8", "8"])
VIN = "1HGCM" + "82633A" + "004352"
SHA = "a1b2c3d4e5" * 4
MD5 = "0123456789abcdef" * 2
REPO = "fenton-hass-" + "requests"
SECRET_TERM = "zebrafish"  # a made-up denylist term, not a real name


def rules(text: str, path: str = "a.md", cfg=CFG, denylist=(), known=None):
    return [h.rule for h in house_scan.scan_text(path, text, cfg, denylist, known)]


class DetectionTests(unittest.TestCase):
    def test_an_entity_id_literal_is_flagged(self):
        self.assertEqual(rules(f"The light is {ATTIC} today."), ["entity"])

    def test_every_hit_carries_path_line_and_rule_only(self):
        hit = house_scan.scan_text("x/y.md", f"ok\n{ent('sensor', 'attic_temp')}", CFG)[0]
        self.assertEqual(tuple(hit), ("x/y.md", 2, "entity"))

    def test_private_addresses_are_flagged_and_public_ones_are_not(self):
        self.assertEqual(rules(f"host {IP} and {CGNAT}"), ["ipv4", "ipv4"])
        self.assertEqual(rules(f"dns {PUBLIC_IP}"), [])

    def test_tailnet_and_local_hosts_are_flagged_but_example_local_is_not(self):
        self.assertEqual(rules("box." + "tail1234" + ".ts.net"), ["tailnet"])
        self.assertEqual(rules("http://attic" + ".local:8123"), ["localhost"])
        self.assertEqual(rules("http://example" + ".local:8123"), [])

    def test_dot_local_in_paths_and_identifiers_is_not_a_host(self):
        self.assertEqual(rules("settings" + ".local.json and ~/.local/bin and Dates.local(x)"), [])

    def test_a_vin_shaped_string_is_flagged(self):
        self.assertEqual(rules(f"vin {VIN}"), ["vin"])
        self.assertEqual(rules("UPPERCASEWORDONLYX"), [])

    def test_hex_strings_of_32_and_40_digits_are_flagged(self):
        self.assertEqual(rules(f"token {SHA}"), ["hex"])
        self.assertEqual(rules(f"token {MD5}"), ["hex"])
        self.assertEqual(rules("token " + "0123456789abcdef" * 3), [])  # 48 digits is neither

    def test_known_non_secret_hex_is_skipped(self):
        self.assertEqual(rules(f"commit {SHA}", known={SHA}), [])
        self.assertEqual(rules(f"uses: org/action@{SHA}"), [])
        self.assertEqual(rules("sha " + "0" * 40), [])
        allow = house_scan.Config(CFG.object_id_prefixes, CFG.object_id_words, CFG.object_ids, CFG.hosts, {MD5}, (), (), [])
        self.assertEqual(rules(f"id {MD5}", cfg=allow), [])
        self.assertEqual(rules(f"id {MD5}", path="fx/a.json", cfg=house_scan.Config(
            CFG.object_id_prefixes, CFG.object_id_words, CFG.object_ids, CFG.hosts, set(), ("fx/",), (), [])), [])

    def test_the_private_request_repository_name_is_flagged(self):
        self.assertEqual(rules(f"Owner/{REPO.upper()}"), ["reponame"])
        self.assertEqual(rules("example-owner/example-requests"), [])

    def test_in_code_an_id_counts_only_inside_a_string(self):
        self.assertEqual(rules("let a = light.isOn", path="a.swift"), [])
        self.assertEqual(rules(f'let a = "{ATTIC}"', path="a.swift"), ["entity"])
        self.assertEqual(rules(f"x = '{CELLAR}'", path="a.py"), ["entity"])


class AllowlistTests(unittest.TestCase):
    def test_demo_generic_and_test_ids_pass(self):
        for text in ("light.demo_lamp", "sensor.test_probe", "switch.example_plug", "light.turn_on", "weather.md"):
            self.assertEqual(rules(text, cfg=house_scan.load_config()), [], text)

    def test_a_listed_object_id_passes_and_an_unlisted_one_does_not(self):
        listed = house_scan.Config(("demo_",), (), {ATTIC}, set(), set(), (), (), [])
        self.assertEqual(rules(ATTIC, cfg=listed), [])
        self.assertEqual(rules(ent("light", "cellar_lamp"), cfg=listed), ["entity"])

    def test_the_committed_config_loads_and_every_debt_entry_is_complete(self):
        cfg = house_scan.load_config()
        self.assertEqual(house_scan.validate_debt(cfg.debt), [])
        self.assertIn("demo_", cfg.object_id_prefixes)
        self.assertTrue(cfg.debt)

    def test_the_committed_debt_names_the_ledger_checks(self):
        checks = {e["path"]: e["check"] for e in house_scan.load_config().debt}
        for path in (".agents/platforms", ".agents/workflow"):
            self.assertEqual(checks[path], "house-config-runtime:textscrub")
        self.assertEqual(checks["apple/Apps/iOSUITests"], "house-config-runtime:step8scope")
        for cleared in (".agents/design", ".agents/pages"):
            self.assertNotIn(cleared, checks, f"{cleared} has no house data left, so no debt entry")
        self.assertNotIn("apple/Sources", checks, "apple/Sources has no house data left, so no debt entry")
        for cleared in ("contracts/jev", "tools/push_fixtures", "apple/Apps/iOSTests", ".agents/skills"):
            self.assertNotIn(cleared, checks, f"{cleared} is scrubbed, so no debt entry")

    def test_a_missing_config_is_an_empty_one(self):
        self.assertEqual(house_scan.load_config(Path("/nonexistent/x.json")).debt, [])


class DebtTests(unittest.TestCase):
    DEBT = [{"path": "docs", "check": "t:one", "reason": "r", "baseline": {"entity": 1}}, {"path": "docs/deep", "check": "t:two", "reason": "r", "baseline": {}}]

    def test_the_longest_prefix_wins_and_siblings_do_not_match(self):
        self.assertEqual(house_scan.debt_entry("docs/a.md", self.DEBT)["check"], "t:one")
        self.assertEqual(house_scan.debt_entry("docs/deep/a.md", self.DEBT)["check"], "t:two")
        self.assertIsNone(house_scan.debt_entry("docsx/a.md", self.DEBT))
        self.assertIsNone(house_scan.debt_entry("other/a.md", self.DEBT))

    def test_hits_split_into_debt_and_new(self):
        hits = [house_scan.Hit("docs/a.md", 1, "entity"), house_scan.Hit("src/b.py", 2, "ipv4")]
        covered, new = house_scan.split_hits(hits, self.DEBT)
        self.assertEqual(covered, {"docs": {"entity": 1}})
        self.assertEqual(new, [hits[1]])

    def test_an_incomplete_debt_entry_is_reported(self):
        self.assertEqual(house_scan.validate_debt([{"path": "a", "reason": "r"}]), ["debt[0] has no check"])

    def test_baseline_groups_by_prefix(self):
        table = house_scan.baseline([house_scan.Hit("a/b/c.md", 1, "entity"), house_scan.Hit("a/b/d.md", 2, "hex")])
        self.assertEqual(table, {"a/b": {"entity": 1, "hex": 1}})

    def test_render_fails_on_a_new_hit_and_passes_on_debt_only(self):
        cfg = house_scan.Config((), (), set(), set(), set(), (), (), self.DEBT)
        lines, code = house_scan.render([house_scan.Hit("docs/a.md", 1, "entity")], cfg, False, False)
        self.assertEqual(code, 0)
        self.assertIn("1 in recorded debt, 0 new", lines[0])
        lines, code = house_scan.render([house_scan.Hit("src/a.py", 7, "ipv4")], cfg, False, False)
        self.assertEqual(code, 1)
        self.assertIn("src/a.py:7 ipv4", "\n".join(lines))

    def test_render_caps_a_long_list_unless_asked_for_all(self):
        cfg = house_scan.Config((), (), set(), set(), set(), (), (), [])
        hits = [house_scan.Hit("s.py", i, "hex") for i in range(1, 251)]
        lines, _ = house_scan.render(hits, cfg, False, False)
        self.assertIn("50 more", lines[-1])
        lines, _ = house_scan.render(hits, cfg, False, True)
        self.assertNotIn("more", lines[-1])


class DenylistTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name) / "deny.txt"

    def test_with_no_file_the_rule_is_skipped(self):
        self.assertEqual(house_scan.load_denylist({"HOUSE_SCAN_DENYLIST": str(Path(self.tmp.name) / "none.txt")}), [])

    def test_default_paths_are_tried_in_order_and_the_agent_path_is_the_fallback(self):
        """Fails if: the agents' file is ignored when the first default is absent, or beats it when both exist."""
        first, second = Path(self.tmp.name) / "first.txt", Path(self.tmp.name) / "second.txt"
        with mock.patch.object(house_scan, "DENYLIST_DEFAULT", first), mock.patch.object(house_scan, "DENYLIST_AGENT_DEFAULT", second):
            self.assertEqual(house_scan.load_denylist({}), [])
            second.write_text("alpha\nbeta\n")
            self.assertEqual(len(house_scan.load_denylist({})), 2)
            first.write_text("gamma\n")
            self.assertEqual(len(house_scan.load_denylist({})), 1)
            self.assertEqual(len(house_scan.load_denylist({"HOUSE_SCAN_DENYLIST": str(second)})), 2)

    def test_a_list_looser_than_600_warns_on_stderr_with_path_and_mode_only(self):
        """Fails if: a group- or world-readable list loads silently, or the warning prints a term."""
        self.path.write_text(SECRET_TERM + "\n")
        self.path.chmod(0o644)
        with mock.patch("sys.stderr", new_callable=io.StringIO) as err:
            house_scan.load_denylist({"HOUSE_SCAN_DENYLIST": str(self.path)})
        self.assertIn(str(self.path), err.getvalue())
        self.assertIn("644", err.getvalue())
        self.assertNotIn(SECRET_TERM, err.getvalue())
        self.path.chmod(0o600)
        with mock.patch("sys.stderr", new_callable=io.StringIO) as err:
            house_scan.load_denylist({"HOUSE_SCAN_DENYLIST": str(self.path)})
        self.assertEqual(err.getvalue(), "")

    def test_terms_match_whole_words_case_insensitively_and_comments_are_ignored(self):
        self.path.write_text(f"# comment\n\n{SECRET_TERM}\n")
        deny = house_scan.load_denylist({"HOUSE_SCAN_DENYLIST": str(self.path)})
        self.assertEqual(len(deny), 1)
        self.assertEqual(rules(f"Say {SECRET_TERM.upper()} twice, {SECRET_TERM}.", denylist=deny), ["denylist", "denylist"])
        self.assertEqual(rules(f"not{SECRET_TERM}s", denylist=deny), [])

    def test_the_report_never_contains_the_term(self):
        self.path.write_text(SECRET_TERM + "\n")
        deny = house_scan.load_denylist({"HOUSE_SCAN_DENYLIST": str(self.path)})
        hits = house_scan.scan_text("n.md", f"a {SECRET_TERM} b", CFG, deny)
        cfg = house_scan.Config((), (), set(), set(), set(), (), (), [])
        lines, code = house_scan.render(hits, cfg, True, True)
        self.assertEqual(code, 0)
        text = "\n".join(lines)
        self.assertNotIn(SECRET_TERM, text)
        self.assertIn("n.md:1 denylist", text)
        self.assertIn("local denylist on", text)

    def test_denylist_hits_never_count_against_the_baselines_or_the_exit_code(self):
        self.path.write_text(SECRET_TERM + "\n")
        deny = house_scan.load_denylist({"HOUSE_SCAN_DENYLIST": str(self.path)})
        hits = house_scan.scan_text("docs/n.md", f"a {SECRET_TERM} b", CFG, deny)
        debt = [{"path": "docs", "check": "t:x", "reason": "r", "baseline": {}}]
        cfg = house_scan.Config((), (), set(), set(), set(), (), (), debt)
        lines, code = house_scan.render(hits, cfg, True, False)
        self.assertEqual(code, 0, lines)
        self.assertIn("local denylist: 1 hit(s), not counted against the baselines", "\n".join(lines))
        self.assertIn("0 hit(s); 0 in recorded debt, 0 new", lines[0])


class RepoScanTests(unittest.TestCase):
    """End to end on a throwaway git repository."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        (self.root / "contracts").mkdir()
        (self.root / "contracts" / "house_scan.json").write_text(json.dumps({
            "allow": {}, "debt": [{"path": "docs", "check": "t:x", "reason": "r", "baseline": {"entity": 1}}]}))
        (self.root / "docs").mkdir()
        (self.root / "docs" / "a.md").write_text(ATTIC + "\n")
        (self.root / "src").mkdir()
        (self.root / "src" / "b.md").write_text("clean\n")
        (self.root / "img.png").write_bytes(b"\x89PNG " + ATTIC.encode())
        (self.root / "bin.md").write_bytes(b"\xff\xfe " + ATTIC.encode())
        subprocess.run(["git", "-C", str(self.root), "add", "-A"], check=True)
        self.nodeny = mock.patch.dict("os.environ", {"HOUSE_SCAN_DENYLIST": str(self.root / "absent.txt")})
        self.nodeny.start()
        self.addCleanup(self.nodeny.stop)

    def run_main(self, *args):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = house_scan.main([*args, "--root", str(self.root)])
        return code, out.getvalue()

    def test_debt_passes_and_binary_files_are_skipped(self):
        code, out = self.run_main("check")
        self.assertEqual(code, 0, out)
        self.assertIn("1 hit(s); 1 in recorded debt, 0 new", out)

    def test_a_new_hit_outside_the_debt_fails_with_a_location_and_no_value(self):
        (self.root / "src" / "c.md").write_text(f"ok\n{CELLAR}\n")
        subprocess.run(["git", "-C", str(self.root), "add", "-A"], check=True)
        code, out = self.run_main("check")
        self.assertEqual(code, 1)
        self.assertIn("src/c.md:2 entity", out)
        self.assertNotIn("cellar", out)

    def test_a_git_object_hash_in_a_doc_is_not_a_secret(self):
        subprocess.run(["git", "-C", str(self.root), "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-qm", "m"], check=True)
        sha = subprocess.run(["git", "-C", str(self.root), "rev-parse", "HEAD"], capture_output=True, text=True, check=True).stdout.strip()
        (self.root / "src" / "d.md").write_text(f"see {sha}\n")
        subprocess.run(["git", "-C", str(self.root), "add", "-A"], check=True)
        code, out = self.run_main("check")
        self.assertEqual(code, 0, out)

    def test_report_and_baseline_exit_zero_and_print_counts(self):
        (self.root / "src" / "c.md").write_text(CELLAR + "\n")
        subprocess.run(["git", "-C", str(self.root), "add", "-A"], check=True)
        code, out = self.run_main("report")
        self.assertEqual(code, 0)
        self.assertIn("1 new", out)
        code, out = self.run_main("baseline")
        self.assertEqual(code, 0)
        self.assertIn("src/c.md: 1 (entity=1)", out)


class RatchetTests(unittest.TestCase):
    """A debt entry is a ceiling: more hits than its baseline fail, fewer ask for the baseline to come down."""

    def entry(self, **kw):
        return {"path": "docs", "check": "t:x", "reason": "r", **kw}

    def cfg(self, debt):
        return house_scan.Config((), (), set(), set(), set(), (), (), debt)

    def test_a_count_above_the_baseline_is_a_problem(self):
        covered = {"docs": house_scan.Counter({"entity": 3})}
        problems, notes = house_scan.ratchet(covered, [self.entry(baseline={"entity": 2})])
        self.assertEqual(len(problems), 1)
        self.assertIn("grew: entity 3 hits, baseline 2", problems[0])
        self.assertEqual(notes, [])

    def test_equal_passes_and_below_asks_for_a_lower_baseline(self):
        covered = {"docs": house_scan.Counter({"entity": 2})}
        self.assertEqual(house_scan.ratchet(covered, [self.entry(baseline={"entity": 2})]), ([], []))
        problems, notes = house_scan.ratchet(covered, [self.entry(baseline={"entity": 5})])
        self.assertEqual(problems, [])
        self.assertIn("down to 2", notes[0])

    def test_a_missing_or_non_integer_baseline_is_a_problem(self):
        for entry in (self.entry(), self.entry(baseline=3), self.entry(baseline={"entity": "3"}), self.entry(baseline={"entity": True})):
            problems, _ = house_scan.ratchet({}, [entry])
            self.assertIn("no per-rule baseline mapping", problems[0])

    def test_swapping_one_kind_of_hit_for_another_fails(self):
        covered = {"docs": house_scan.Counter({"ipv4": 1})}
        problems, notes = house_scan.ratchet(covered, [self.entry(baseline={"entity": 1})])
        self.assertEqual(len(problems), 1)
        self.assertIn("ipv4 1 hits, baseline 0", problems[0])
        self.assertIn("entity is down to 0", notes[0])

    def test_render_fails_when_a_debt_area_grows_and_names_no_value(self):
        hits = [house_scan.Hit("docs/a.md", n, "entity") for n in (1, 2)]
        lines, code = house_scan.render(hits, self.cfg([self.entry(baseline={"entity": 1})]), False, False)
        self.assertEqual(code, 1)
        self.assertIn("grew", "\n".join(lines))

    def test_render_passes_at_the_baseline_and_prints_a_note_below_it(self):
        hits = [house_scan.Hit("docs/a.md", 1, "entity")]
        lines, code = house_scan.render(hits, self.cfg([self.entry(baseline={"entity": 1})]), False, False)
        self.assertEqual(code, 0)
        lines, code = house_scan.render(hits, self.cfg([self.entry(baseline={"entity": 4})]), False, False)
        self.assertEqual(code, 0)
        self.assertIn("note: debt docs entity is down to 1", "\n".join(lines))


class DetectionGapTests(unittest.TestCase):
    """The review's gaps: whole-token allow words, YAML, comments, multi-label hosts, uppercase hex, IPv6, prose."""

    def test_allow_words_match_whole_tokens_not_substrings(self):
        cfg = house_scan.load_config()
        self.assertEqual(rules(ent("sensor", "porch_latest_reading"), cfg=cfg), ["entity"])
        self.assertEqual(rules(ent("update", "porch_installed"), cfg=cfg), ["entity"])
        self.assertEqual(rules(ent("sensor", "porch_test_reading"), cfg=cfg), [])
        self.assertEqual(rules(ent("light", "turn_on"), cfg=cfg), [])

    def test_service_names_match_whole_never_inside_an_object_id(self):
        cfg = house_scan.load_config()
        self.assertEqual(rules(ent("script", "turn_off"), cfg=cfg), [])
        self.assertEqual(rules(ent("light", "porch_toggle"), cfg=cfg), ["entity"])
        self.assertEqual(rules(ent("switch", "turn_on_porch"), cfg=cfg), ["entity"])
        self.assertEqual(rules(ent("sensor", "attic_install_state"), cfg=cfg), ["entity"])

    def test_a_vin_inside_a_lowercase_entity_id_is_found(self):
        cfg = house_scan.load_config()
        self.assertIn("vin", rules(ent("sensor", "map_" + VIN.lower() + "_state"), cfg=cfg))

    def test_an_escaped_dot_cannot_hide_an_id(self):
        escaped = "light\\u002e" + "attic_lamp"
        self.assertEqual(rules(f"the {escaped} lamp", path="a.md"), ["entity"])
        self.assertEqual(rules('{"id": "' + escaped + '"}', path="a.json"), ["entity"])
        self.assertEqual(rules('{"id": "light\\u002E' + 'attic_lamp"}', path="a.json"), ["entity"])
        self.assertEqual(rules('x = "light\\u02e' + 'attic_lamp"', path="a.json"), [], "a short \\u escape is not an escape")

    def test_swift_unicode_escapes_cannot_hide_an_id(self):
        self.assertEqual(rules('let id = "light\\u{2e}' + 'attic_lamp"', path="a.swift"), ["entity"])
        self.assertEqual(rules('let id = "light\\u{002E}' + 'attic_lamp"', path="a.swift"), ["entity"])

    def test_other_escapes_cannot_hide_an_id(self):
        self.assertEqual(rules('x = "light\\x2e' + 'attic_lamp"', path="a.py"), ["entity"])
        self.assertEqual(rules("<string>light&#46;" + "attic_lamp</string>", path="a.plist"), ["entity"])
        self.assertEqual(rules("<string>light&#x2e;" + "attic_lamp</string>", path="a.plist"), ["entity"])
        self.assertEqual(rules("the light&#46;" + "attic_lamp lamp", path="a.md"), ["entity"])

    def test_escaped_quotes_and_backslashes_cannot_move_a_string_boundary_to_hide_an_id(self):
        quoted = '"\\u0022' + ATTIC + '\\u0022"'
        self.assertEqual(rules("let s = " + quoted, path="a.swift"), ["entity"])
        self.assertEqual(rules("s = " + quoted, path="a.py"), ["entity"])
        self.assertEqual(rules('let s = "x\\u005c" + "' + ATTIC + '"', path="a.swift"), ["entity"])

    def test_a_line_without_an_escape_counts_the_same_as_before(self):
        self.assertEqual(rules(f"{ATTIC} and {CELLAR}", path="a.md"), ["entity", "entity"])

    def test_a_mixed_case_run_is_not_a_vin_but_upper_and_lower_are(self):
        mixed = VIN[:5] + VIN[5:].lower()
        self.assertEqual(rules(f"data {mixed}"), [])
        self.assertEqual(rules(f"car {VIN}"), ["vin"])
        self.assertEqual(rules(f"car {VIN.lower()}"), ["vin"])

    def test_the_configs_own_allow_section_may_spell_ids_with_escapes(self):
        escaped = "light\\u002e" + "attic_lamp"
        config = '{\n  "allow": {\n    "object_ids": [\n      "' + escaped + '"\n    ]\n  },\n  "debt": []\n}\n'
        self.assertEqual(rules(config, path="contracts/house_scan.json"), [])
        outside = config.replace('"debt": []', '"note": "' + escaped + '"')
        self.assertEqual(rules(outside, path="contracts/house_scan.json"), ["entity"])
        self.assertEqual(rules(config, path="other/house_scan.json"), ["entity"])

    def test_unquoted_yaml_ids_are_found(self):
        self.assertEqual(rules(f"entity_id: {ATTIC}\n- {CELLAR}", path="a.yaml"), ["entity", "entity"])
        self.assertEqual(rules(f"entity_id: {ATTIC}", path="a.yml"), ["entity"])

    def test_ids_in_swift_and_python_comments_are_found(self):
        self.assertEqual(rules(f"// the {ATTIC} lamp", path="a.swift"), ["entity"])
        self.assertEqual(rules(f"/// see {ATTIC}", path="a.swift"), ["entity"])
        self.assertEqual(rules(f"x = 1  # {ATTIC}", path="a.py"), ["entity"])
        self.assertEqual(rules(f"x = 1  // {ATTIC}", path="a.swift"), ["entity"])

    def test_code_outside_strings_and_comments_is_not_an_id(self):
        self.assertEqual(rules(f"let a = {ent('light', 'isOn')}", path="a.swift"), [])
        self.assertEqual(rules(f"print({ent('zone', 'id')})", path="a.py"), [])

    def test_multi_label_local_hosts_are_found(self):
        self.assertEqual(rules("http://" + "a.b" + ".local/x"), ["localhost"])
        self.assertEqual(rules("http://" + "a.example" + ".local/x"), ["localhost"])
        self.assertEqual(rules("http://example" + ".local/x"), [])

    def test_uppercase_hex_is_found(self):
        self.assertEqual(rules(f"id {SHA.upper()}"), ["hex"])
        self.assertEqual(rules(f"id {MD5.upper()}"), ["hex"])

    def test_an_allowed_exact_address_passes_and_its_neighbour_is_still_flagged(self):
        # synthetic scanner inputs, assembled like the other address cases here so this file carries no literal address
        first, second, eleventh = ".".join(("10", "0", "0", "1")), ".".join(("10", "0", "0", "2")), ".".join(("10", "0", "0", "11"))
        ula, ula_next = "fd" + "00::1", "fd" + "00::2"
        cfg = CFG._replace(addresses=house_scan.parse_addresses([first, ula]))
        self.assertEqual(rules(f"host {first} and {ula}", cfg=cfg), [])
        self.assertEqual(rules(f"host {first}:8123", cfg=cfg), [])
        self.assertEqual(rules(f"host {second}", cfg=cfg), ["ipv4"])
        self.assertEqual(rules(f"host {eleventh}", cfg=cfg), ["ipv4"])
        self.assertEqual(rules(f"host {ula_next}", cfg=cfg), ["ipv6"])
        self.assertEqual(rules(f"host {first}", cfg=CFG), ["ipv4"], "no allow entry, no pass")

    def test_the_allow_list_refuses_ranges_prefixes_and_words(self):
        for bad in ("10." + "0.0.0/8", "10." + "0.0.*", "10." + "0.0", "localhost", ""):
            with self.subTest(entry=bad):
                with self.assertRaises(ValueError):
                    house_scan.parse_addresses([bad])
        self.assertEqual(house_scan.parse_addresses(["FD00" + ":0:0:0:0:0:0:1", ".".join(("192", "168", "0", "1"))]),
                         ("fd" + "00::1", ".".join(("192", "168", "0", "1"))))

    def test_an_escaped_entry_in_the_allow_section_loads_as_the_plain_address(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "house_scan.json"
            path.write_text('{"allow": {"addresses": ["10\\u002e0\\u002e0\\u002e1", "fd00\\u003a\\u003a1"]}}')
            self.assertNotIn(".".join(("10", "0", "0", "1")), path.read_text(), "the file itself never spells the address")
            cfg = house_scan.load_config(path)
            self.assertEqual(cfg.addresses, (".".join(("10", "0", "0", "1")), "fd" + "00::1"))
            self.assertEqual(rules("host " + ".".join(("10", "0", "0", "1")), cfg=cfg), [])

    def test_an_allow_entry_matching_the_private_denylist_is_refused_at_load(self):
        stand_in = ".".join(("198", "51", "100", "7"))  # a documentation-range address standing for a private network's prefix
        with tempfile.TemporaryDirectory() as tmp:
            terms = Path(tmp) / "denylist.txt"
            terms.write_text("# fake private list\n" + ".".join(("198", "51", "100")) + "\n")
            terms.chmod(0o600)
            path = Path(tmp) / "house_scan.json"
            path.write_text(json.dumps({"allow": {"addresses": [stand_in]}}))
            with mock.patch.dict(os.environ, {"HOUSE_SCAN_DENYLIST": str(terms)}):
                with self.assertRaises(ValueError) as caught:
                    house_scan.load_config(path)
                self.assertNotIn(stand_in, str(caught.exception))
            with mock.patch.dict(os.environ, {"HOUSE_SCAN_DENYLIST": str(Path(tmp) / "absent.txt")}):
                self.assertEqual(house_scan.load_config(path).addresses, (stand_in,), "with no list loaded the entry is only checked for shape")

    def test_unique_local_ipv6_and_tailscale_addresses_are_found(self):
        self.assertEqual(rules("addr fd" + "12:3456:789a::1"), ["ipv6"])
        self.assertEqual(rules("addr fd" + "7a:115c:a1e0::5"), ["ipv6"])
        self.assertEqual(rules("addr FC" + "00:1:2::3"), ["ipv6"])
        self.assertEqual(rules("addr " + "2001:db8::1"), [])
        self.assertEqual(rules("time 12:30:45 and mac fd:aa:bb"), [])

    def test_prose_member_names_and_calls_are_not_ids(self):
        for text in (f"the {ent('zone', 'id')} field", f"call {ent('counter', 'values')}()", f"{ent('timer', 'name')} is set",
                     f"({ent('sensor', 'values')})", "group.com" + ".example.app"):
            self.assertEqual(rules(text), [], text)

    def test_interpolations_in_code_strings_are_not_ids(self):
        self.assertEqual(rules('x = f"{' + ent("counter", "total") + '} hits"', path="a.py"), [])

    def test_the_new_rules_scan_a_long_line_quickly(self):
        import time
        line = ("a.b-c" * 4000) + ".ts" + (".x" * 4000)
        start = time.monotonic()
        rules(line)
        self.assertLess(time.monotonic() - start, 2.0)


class SelfScanTests(unittest.TestCase):
    """The repository passes its own lint: nothing outside the recorded debt, none of it grown, in a few seconds."""

    def test_the_repository_has_no_new_house_data(self):
        import time
        start = time.monotonic()
        cfg = house_scan.load_config()
        hits = house_scan.scan_repo(house_scan.ROOT, cfg, [])
        lines, code = house_scan.render(hits, cfg, False, True)
        self.assertEqual(code, 0, "\n".join(lines[:40]))
        self.assertLess(time.monotonic() - start, 30.0)

    def test_the_scanner_and_its_tests_carry_no_hits(self):
        cfg = house_scan.load_config()
        for rel in ("tools/house_scan.py", "tools/tests/test_house_scan.py", "tools/history_secret_scan.sh"):
            text = (house_scan.ROOT / rel).read_text(encoding="utf-8")
            self.assertEqual(house_scan.scan_text(rel, text, cfg, ()), [], rel)


if __name__ == "__main__":
    unittest.main()
