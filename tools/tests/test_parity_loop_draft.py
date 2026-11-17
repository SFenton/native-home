"""Tests for tools/parity_loop/draft.py over a synthetic ``demo_`` publication (no house data)."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from parity_loop import draft  # noqa: E402


def tile(name: str, layout: str = "anchored-bottom") -> dict:
    return {"id": f"demo_{name}", "type": "navigation-tile", "layout": {"span": 1},
            "props": {"presentation": {"layout": layout, "titleLines": 2}}}


def envelope() -> dict:
    hub = {"id": "demo_hub", "type": "climate-control",
           "props": {"hub": {"modes": [{"value": "off", "icon": "x"}, {"value": "heat", "icon": "x"}]}}}
    grid = {"id": "demo_grid", "type": "tile-grid", "props": {"maxColumns": 2}, "children": [tile("a"), tile("b"), hub]}
    return {"revision": 3, "capabilities": [], "document": {
        "assets": [], "navigation": {"tabs": [{"id": "demo_tab", "label": "T"}]},
        "pages": [{"id": "demo_page", "layout": {"padding": {"top": {"type": "token", "name": "l"}}},
                   "toolbar": {"type": "replace", "groups": []}, "components": [grid]},
                  {"id": "demo_other", "layout": {"padding": {"top": {"type": "token", "name": "m"}}},
                   "toolbar": {"type": "inherit"}, "components": [tile("c")]}],
        "modals": []}}


def run(edits: list) -> dict:
    env = envelope()
    draft.apply_edits(env, edits)
    return env


def find(env: dict, ident: str) -> dict:
    return next(n for _, _, n, _ in draft._all_components(env["document"]) if n["id"] == ident)


class EditTests(unittest.TestCase):
    def test_set_by_id_and_by_where(self) -> None:
        env = run([{"id": "demo_grid", "op": "set", "path": "/props/maxColumns", "value": 4},
                   {"where": {"type": "navigation-tile"}, "op": "set", "path": "/props/presentation/layout", "value": "standard"}])
        self.assertEqual(find(env, "demo_grid")["props"]["maxColumns"], 4)
        self.assertEqual({find(env, f"demo_{n}")["props"]["presentation"]["layout"] for n in "abc"}, {"standard"})

    def test_where_can_be_limited_to_pages_and_a_guard_skips_other_values(self) -> None:
        env = run([{"where": {"type": "navigation-tile", "pageIds": ["demo_page"]}, "op": "set",
                    "path": "/props/presentation/layout", "value": "standard", "ifEquals": "anchored-bottom"}])
        self.assertEqual(find(env, "demo_a")["props"]["presentation"]["layout"], "standard")
        self.assertEqual(find(env, "demo_c")["props"]["presentation"]["layout"], "anchored-bottom")

    def test_page_targets_and_guard(self) -> None:
        env = run([{"page": "*", "op": "set", "path": "/layout/padding/top", "ifEquals": {"type": "token", "name": "l"},
                    "value": {"type": "token", "name": "m"}},
                   {"page": "demo_page", "op": "set", "path": "/toolbar", "value": {"type": "inherit"}}])
        self.assertEqual([p["layout"]["padding"]["top"]["name"] for p in env["document"]["pages"]], ["m", "m"])
        self.assertEqual(env["document"]["pages"][0]["toolbar"], {"type": "inherit"})

    def test_remove_replace_and_wrap(self) -> None:
        env = run([{"id": "demo_b", "op": "remove"},
                   {"id": "demo_a", "op": "wrap", "with": {"id": "demo_wrap", "type": "section", "props": {"header": "H"}}},
                   {"id": "demo_c", "op": "replace", "with": {"id": "demo_new", "type": "row", "props": {}}}])
        grid = find(env, "demo_grid")
        self.assertEqual([c["id"] for c in grid["children"]], ["demo_wrap", "demo_hub"])
        self.assertEqual([c["id"] for c in find(env, "demo_wrap")["children"]], ["demo_a"])
        self.assertEqual(env["document"]["pages"][1]["components"][0]["id"], "demo_new")

    def test_each_sets_every_element_of_a_list_and_dash_appends(self) -> None:
        env = run([{"id": "demo_hub", "op": "each", "path": "/props/hub/modes", "set": {"/icon": "y"}}])
        self.assertEqual([m["icon"] for m in find(env, "demo_hub")["props"]["hub"]["modes"]], ["y", "y"])
        env = run([{"id": "demo_hub", "op": "set", "path": "/props/hub/modes/-", "value": {"value": "cool", "icon": "z"}}])
        self.assertEqual(len(find(env, "demo_hub")["props"]["hub"]["modes"]), 3)

    def test_json_patch_on_the_envelope(self) -> None:
        env = run([{"patch": [{"op": "add", "path": "/capabilities/-", "value": "demo-cap"},
                              {"op": "test", "path": "/revision", "value": 3},
                              {"op": "replace", "path": "/document/navigation/tabs/0/label", "value": "U"},
                              {"op": "add", "path": "/document/navigation/tabs/0/badge", "value": {"type": "none"}}]}])
        self.assertEqual(env["capabilities"], ["demo-cap"])
        self.assertEqual(env["document"]["navigation"]["tabs"][0]["label"], "U")
        self.assertEqual(env["document"]["navigation"]["tabs"][0]["badge"], {"type": "none"})
        with self.assertRaises(draft.DraftError):
            run([{"patch": [{"op": "test", "path": "/revision", "value": 4}]}])
        with self.assertRaises(draft.DraftError):
            run([{"patch": [{"op": "replace", "path": "/nope", "value": 1}]}])

    def test_an_edit_that_matches_nothing_or_misuses_a_page_fails_with_its_number(self) -> None:
        with self.assertRaisesRegex(draft.DraftError, "edit 1: an edit matched no target"):
            run([{"id": "demo_a", "op": "remove"}, {"id": "demo_missing", "op": "remove"}])
        with self.assertRaises(draft.DraftError):
            run([{"page": "demo_page", "op": "remove"}])
        with self.assertRaises(draft.DraftError):
            run([{"id": "demo_a", "op": "frobnicate"}])

    def test_an_edit_with_no_selector_is_refused(self) -> None:
        for edit in ({"Id": "demo_a", "op": "remove"}, {"op": "set", "path": "/x", "value": 1}, {"where": {"pageIds": ["demo_page"]}, "op": "remove"}):
            with self.assertRaisesRegex(draft.DraftError, "names no target"):
                run([edit])

    def test_errors_never_carry_authored_values(self) -> None:
        with self.assertRaises(draft.DraftError) as caught:
            run([{"id": "demo_a", "op": "set", "path": "/props/nope/deeper", "value": "SECRET-VALUE"}])
        self.assertNotIn("SECRET-VALUE", str(caught.exception))


class FileTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)

    def test_apply_files_writes_a_compact_draft_and_leaves_the_source(self) -> None:
        source, edits, out = self.dir / "s.json", self.dir / "e.json", self.dir / "o" / "d.json"
        source.write_text(json.dumps(envelope()))
        edits.write_text(json.dumps({"edits": [{"id": "demo_grid", "op": "set", "path": "/props/maxColumns", "value": 4}]}))
        rows = draft.apply_files(source, edits, out, check_ignore=False)
        self.assertEqual(rows, [{"targets": 1, "changed": 1}])
        self.assertEqual(json.loads(out.read_text())["revision"], envelope()["revision"])  # the draft keeps its source's revision
        self.assertEqual(json.loads(source.read_text()), envelope())
        self.assertEqual(find(json.loads(out.read_text()), "demo_grid")["props"]["maxColumns"], 4)
        self.assertNotIn(": ", out.read_text())

    def test_bad_inputs_are_refused(self) -> None:
        source, edits, out = self.dir / "s.json", self.dir / "e.json", self.dir / "d.json"
        source.write_text("not json")
        edits.write_text("{}")
        with self.assertRaises(draft.DraftError):
            draft.apply_files(source, edits, out, check_ignore=False)
        source.write_text(json.dumps({"revision": "1", "document": {"assets": []}}))
        edits.write_text(json.dumps({"edits": []}))
        with self.assertRaises(draft.DraftError):
            draft.apply_files(source, edits, out, check_ignore=False)
        self.assertFalse(out.exists())

    def test_files_outside_an_ignored_folder_are_refused(self) -> None:
        with self.assertRaises(draft.DraftError):
            draft.require_ignored(draft.REPO / "tools" / "parity_loop" / "draft.json")
        draft.require_ignored(draft.DRAFT_DIR / "publication.draft.json")

    def test_a_written_file_must_resolve_under_the_draft_folder(self) -> None:
        inside = draft.DRAFT_DIR / "publication.draft.json"
        self.assertEqual(draft.require_ignored(inside, write=True), inside.resolve())
        # ignored by git, but not the draft folder; and an absolute path outside the repo; and '..' out of the folder
        for path in (draft.REPO / "apple" / ".build" / "x.json", Path(self.dir) / "x.json", draft.DRAFT_DIR / ".." / "evidence" / "x.json"):
            with self.assertRaises(draft.DraftError, msg=str(path)):
                draft.require_ignored(path, write=True)

    def test_a_symlink_to_a_tracked_file_is_refused(self) -> None:
        draft.DRAFT_DIR.mkdir(parents=True, exist_ok=True)
        link = draft.DRAFT_DIR / "demo-link-test.json"
        link.unlink(missing_ok=True)
        link.symlink_to(draft.REPO / "tools" / "parity_loop" / "README.md")
        self.addCleanup(link.unlink, missing_ok=True)
        for write in (False, True):
            with self.assertRaisesRegex(draft.DraftError, "symlink"):
                draft.require_ignored(link, write=write)
        with self.assertRaises(draft.DraftError):
            draft.apply_files(link, link, draft.DRAFT_DIR / "demo-link-out.json")
        broken = draft.DRAFT_DIR / "demo-broken-link.json"
        broken.unlink(missing_ok=True)
        broken.symlink_to(draft.REPO / "tools" / "parity_loop" / "nothing-here.json")
        self.addCleanup(broken.unlink, missing_ok=True)
        with self.assertRaisesRegex(draft.DraftError, "symlink"):
            draft.require_ignored(broken, write=True)

    def test_compile_runs_the_swift_test_and_reads_its_report(self) -> None:
        target, result = self.dir / "d.json", self.dir / "r.json"
        target.write_text("{}")
        seen = {}

        def fake(argv, cwd=None, env=None, capture_output=None, timeout=None):
            seen["argv"], seen["env"] = argv, env
            Path(env["PARITY_DRAFT_RESULT"]).write_text(json.dumps({"ok": False, "code": "invalid_value", "pointer": "/x"}))
            return mock.Mock(returncode=1)
        with mock.patch.object(draft.subprocess, "run", fake):
            report = draft.compile_publication(target, result, check_ignore=False)
        self.assertEqual(seen["argv"][:3], ["swift", "test", "--filter"])
        self.assertEqual(seen["env"]["PARITY_DRAFT_PUBLICATION"], str(target.resolve()))
        self.assertNotIn("FENTON_HASS_TOKEN", seen["env"])
        self.assertEqual(draft.describe(report), "rejected: invalid_value at /x")
        self.assertEqual(draft.describe({"ok": True}), "compiles: no rejection")
        self.assertEqual(draft.describe({"ok": False, "stage": "preflight", "code": "unsupported_capability", "pointer": "/p"}),
                         "rejected [preflight]: unsupported_capability at /p")
        self.assertEqual(draft.describe({"ok": True, "unchecked": ["providers", "assets"]}),
                         "compiles: no rejection (unchecked, device only: providers, assets)")

    def test_compile_without_a_result_is_an_error(self) -> None:
        target = self.dir / "d.json"
        target.write_text("{}")
        with mock.patch.object(draft.subprocess, "run", lambda *a, **k: mock.Mock(returncode=1)):
            with self.assertRaises(draft.DraftError):
                draft.compile_publication(target, self.dir / "r.json", check_ignore=False)


if __name__ == "__main__":
    unittest.main()
