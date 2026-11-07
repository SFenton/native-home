"""``tools/pr_visual.py``: tree diff, per-class selection, budgets, Jev shadow, comment bodies. Synthetic packs only."""

import importlib.util
import json
import sys
import tempfile
import unittest
from argparse import Namespace
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]
ROOT = TOOLS.parent


def load_tool(name):
    spec = importlib.util.spec_from_file_location(name, TOOLS / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


pv = load_tool("pr_visual")

ALL_POSES = list(pv.POSES)
HINGE_FILE = "apple/Sources/HassUI/UIKitPort/App/Layout/UKHingedPanes.swift"
SHEET_FILE = "apple/Sources/HassDesign/SheetFit.swift"


def tree(width=300.0, label="10:41", extra=0):
    """A tiny XCUITest-style dump: a window, a clock label and a button; `width` moves the button frame."""
    wide = 60.0 + (3 if label != "10:41" else 0)
    lines = ["Window, 0x1, {{0.0, 0.0}, {800.0, 600.0}}",
             f"  StaticText, 0x2, {{{{10.0, 10.0}}, {{{wide}, 20.0}}}}, label: '{label}'",
             f"  Button, 0x3, {{{{10.0, 40.0}}, {{{width}, 44.0}}}}, label: '{label}'"]
    for i in range(extra):
        lines.append(f"  Cell, 0x{i + 9}, {{{{0.0, {100 + 50 * i}.0}}, {{300.0, 44.0}}}}")
    return "\n".join(lines) + "\n"


def write_pack(root, trees, not_run=(), with_trees=True, shot_names=("Security",)):
    """`trees` maps pose id -> tree text; poses in `not_run` carry result not_run and no files."""
    root = Path(root)
    manifest = {"poses": {}}
    for pose in ALL_POSES:
        if pose in not_run:
            manifest["poses"][pose] = {"result": "not_run"}
            continue
        d = root / pose
        d.mkdir(parents=True, exist_ok=True)
        if with_trees:
            (d / "Security.ax.txt").write_text(trees.get(pose, tree()), encoding="utf-8")
        for name in shot_names:
            (d / f"{name}--uikit-inner.png").write_bytes(f"{pose}/{name}".encode())
        manifest["poses"][pose] = {"result": "pass"}
    (root / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    return root


class Packs(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)

    def select(self, after=None, before=None, files=(), request="", not_run=(), asker=None, round_=1,
               with_trees=True, previous=None, shot_names=("Security",), after_dir="after"):
        b = write_pack(self.base / "before", before or {}, not_run, with_trees, shot_names)
        a = write_pack(self.base / after_dir, after or {}, not_run, with_trees, shot_names)
        request_file = self.base / "request.txt"
        request_file.write_text(request, encoding="utf-8")
        args = Namespace(branch="agents/x", task="T-x", round=round_, base_pack=str(b), after_pack=str(a),
                         request_file=str(request_file), files=list(files), diff_base="none", previous=previous)
        return pv.build_selection(args, asker)


class TreeDiff(unittest.TestCase):
    def test_labels_and_values_are_ignored(self):
        self.assertEqual(pv.tree_diff(pv.parse_tree(tree(label="10:41")), pv.parse_tree(tree(label="10:42"))), 0)

    def test_static_text_width_is_not_a_layout_change(self):
        a, b = pv.parse_tree(tree(label="A")), pv.parse_tree(tree(label="B"))
        self.assertEqual(pv.tree_diff(a, b), 0)

    def test_frame_move_beyond_tolerance_counts_but_not_within(self):
        base = pv.parse_tree(tree(300.0))
        self.assertEqual(pv.tree_diff(base, pv.parse_tree(tree(301.5))), 0)
        self.assertEqual(pv.tree_diff(base, pv.parse_tree(tree(340.0))), 1)

    def test_element_list_difference_counts(self):
        self.assertEqual(pv.tree_diff(pv.parse_tree(tree()), pv.parse_tree(tree(extra=2))), 2)


class Selection(Packs):
    def test_candidates_touch_only_changed_poses(self):
        sel = self.select(after={"duo-unfolded-landscape": tree(340.0)})
        duo = sel["classes"]["duo"]
        self.assertTrue(duo["needs_evidence"])
        self.assertEqual(duo["poses"]["Lying flat"], "changed")
        # no transition code and no motion named: pair only, no clip
        self.assertEqual(duo["clips"], [])
        self.assertEqual(len(duo["pairs"]), 1)
        self.assertEqual(duo["pairs"][0]["pose"], "Lying flat")
        for other in ("iphone", "ipad"):
            self.assertFalse(sel["classes"][other]["needs_evidence"])
            self.assertTrue(sel["classes"][other]["reason"])

    def test_transition_code_widens_when_no_pose_changed(self):
        sel = self.select(files=[HINGE_FILE])
        duo = sel["classes"]["duo"]
        self.assertTrue(duo["needs_evidence"])
        self.assertEqual(len(duo["clips"]), pv.MAX_CLIPS)
        self.assertEqual(duo["pairs"], [])
        self.assertFalse(sel["classes"]["ipad"]["needs_evidence"])  # hinge code is Duo-only
        self.assertFalse(sel["classes"]["iphone"]["needs_evidence"])

    def test_round_trip_is_one_clip_per_edge(self):
        sel = self.select(files=[HINGE_FILE])
        for clip in sel["classes"]["duo"]["clips"]:
            self.assertEqual(clip["direction"], "round trip")
        edges = [c["edge"] for c in sel["classes"]["duo"]["clips"]]
        self.assertEqual(len(edges), len(set(edges)))

    def test_going_back_splits_the_directions(self):
        sel = self.select(after={"duo-partial-fold": tree(340.0)}, files=[HINGE_FILE],
                          request="It jumps when going back to flat")
        dirs = [c["direction"] for c in sel["classes"]["duo"]["clips"]]
        self.assertEqual(dirs, ["forward", "reverse"])

    def test_equivalent_edges_collapse(self):
        sel = self.select(after={"duo-partial-fold": tree(340.0)}, files=[HINGE_FILE])
        duo = sel["classes"]["duo"]
        self.assertEqual([c["edge"] for c in duo["clips"]], ["duo-unfolded-landscape<->duo-partial-fold"])
        collapsed = [c for c in duo["checked_not_shown"] if c["what"] == "folded to half open"]
        self.assertEqual(len(collapsed), 1)
        self.assertIn("same end layout", collapsed[0]["covered_by"])

    def test_budgets_pairs_and_clips(self):
        changed = {p: tree(340.0, extra=1) for p in ALL_POSES}
        sel = self.select(after=changed, files=[HINGE_FILE], request="rotate, fold and half-close all misbehave")
        duo = sel["classes"]["duo"]
        self.assertLessEqual(len(duo["clips"]), pv.MAX_CLIPS)
        self.assertLessEqual(len(duo["pairs"]), pv.MAX_PAIRS)
        self.assertEqual(len(duo["pairs"]), 4)
        self.assertEqual(len(duo["more_pairs"]), 0)
        # more surfaces than the budget go to more_pairs
        for pose in ("duo-folded", "duo-unfolded-portrait", "duo-unfolded-landscape", "duo-partial-fold"):
            (self.base / "after" / pose / "Home.ax.txt").write_text(tree(), encoding="utf-8")
            (self.base / "before" / pose / "Home.ax.txt").write_text(tree(500.0), encoding="utf-8")
        args = Namespace(branch="agents/x", task="T", round=1, base_pack=str(self.base / "before"),
                         after_pack=str(self.base / "after"), request_file=None, files=[], diff_base="none")
        sel = pv.build_selection(args, None)
        self.assertEqual(len(sel["classes"]["duo"]["pairs"]), 4)
        self.assertEqual(len(sel["classes"]["duo"]["more_pairs"]), 4)

    def test_priority_order_named_then_crossing_then_into_changed(self):
        sel = self.select(after={"duo-unfolded-portrait": tree(340.0)}, files=[HINGE_FILE],
                          request="Rotating the Duo is broken")
        first = sel["classes"]["duo"]["clips"][0]
        self.assertEqual(first["edge"], "duo-unfolded-portrait<->duo-unfolded-landscape")
        self.assertIn("describes", first["why"])
        # crossing one page / two outranks a plain move when nothing is named
        sel = self.select(files=[HINGE_FILE])
        why = [c["why"] for c in sel["classes"]["duo"]["clips"]]
        self.assertIn("one page and two", why[0])

    def test_iphone_gets_no_pose_transition_clips(self):
        sel = self.select(after={"iphone": tree(340.0)}, files=[HINGE_FILE, "apple/Sources/HassUI/SplitPolicy.swift"])
        phone = sel["classes"]["iphone"]
        self.assertTrue(phone["needs_evidence"])
        self.assertEqual(phone["clips"], [])
        self.assertEqual(len(phone["pairs"]), 1)

    def test_iphone_in_screen_clip_only_for_motion_code(self):
        sel = self.select(files=["apple/Sources/HassDesign/Motion/StateColorTransition.swift"])
        self.assertEqual([c["edge"] for c in sel["classes"]["iphone"]["clips"]], ["iphone-in-screen"])
        layout = self.select(files=[SHEET_FILE], request="Duo sections")  # sheet fit is layout, not motion
        self.assertFalse(layout["classes"]["iphone"]["needs_evidence"])

    def test_unchanged_class_gets_no_comment(self):
        sel = self.select()
        for cls in pv.CLASSES:
            self.assertFalse(sel["classes"][cls]["needs_evidence"])
            self.assertIsNone(pv.render_class(sel, cls, 1))

    def test_sheet_variants_only_when_sheet_code_changed(self):
        plain = self.select(after={"duo-partial-fold": tree(340.0)}, files=[HINGE_FILE])
        self.assertTrue(any(c["what"] == "sheets" for c in plain["classes"]["duo"]["checked_not_shown"]))
        self.assertFalse(any(c["sheet"] for c in plain["classes"]["duo"]["clips"]))
        sheeted = self.select(after={"duo-partial-fold": tree(340.0)}, files=[HINGE_FILE, SHEET_FILE])
        self.assertTrue(any(c["sheet"] for c in sheeted["classes"]["duo"]["clips"]))

    def test_request_naming_a_class_needs_evidence(self):
        sel = self.select(request="The iPad looks wrong")
        self.assertTrue(sel["classes"]["ipad"]["needs_evidence"])
        self.assertFalse(sel["classes"]["duo"]["needs_evidence"])
        self.assertFalse(sel["classes"]["iphone"]["needs_evidence"])

    def test_pose_not_run_is_not_called_changed(self):
        sel = self.select(after={"duo-folded": tree(340.0)}, not_run=("duo-folded",), files=["README.md"])
        self.assertEqual(sel["classes"]["duo"]["poses"]["Folded"], "not_run")
        self.assertFalse(sel["classes"]["duo"]["needs_evidence"])  # no app file changed: nothing to look at

    def test_pack_without_trees_is_unknown_never_unchanged(self):
        sel = self.select(with_trees=False, files=["apple/Sources/HassUI/Home.swift"])
        for cls in pv.CLASSES:
            info = sel["classes"][cls]
            self.assertEqual(info["needs_evidence"], "unknown")
            self.assertEqual(info["route"], "verifier")
            self.assertIn("Not compared", info["reason"])
        self.assertTrue(sel["classes"]["duo"]["pairs"])  # screenshots still offered
        self.assertIsNone(pv.render_class(sel, "duo", 1))
        rows = pv.device_rows(sel)
        self.assertTrue(all("Not compared" in r and "Unchanged" not in r for r in rows))

    def test_edges_say_not_compared_without_trees(self):
        sel = self.select(with_trees=False, files=[HINGE_FILE], request="Sections slide under the hinge on the Duo")
        duo = sel["classes"]["duo"]
        checked = " ".join(c["covered_by"] for c in duo["checked_not_shown"])
        self.assertIn("not compared", checked)
        self.assertNotIn("tree check, no change", checked)
        self.assertIs(duo["needs_evidence"], True)
        self.assertEqual([c["edge"] for c in duo["clips"]], ["duo-unfolded-landscape<->duo-partial-fold"])

    def test_real_section_sides_pack_duo_is_never_no_comment(self):
        import os
        if not os.environ.get("FENTON_REAL_PACK"):
            self.skipTest("set FENTON_REAL_PACK to a real evidence pack folder (with before/ and after/)")
        pack = Path(os.environ["FENTON_REAL_PACK"])
        args = Namespace(branch="claude/section-sides", task="T", round=1, base_pack=str(pack / "before"),
                         after_pack=str(pack / "after"), request_file=None,
                         files=["apple/Sources/HassUI/UIKitPort/App/Layout/UKHingedPanes.swift"], diff_base="none")
        self.assertIs(pv.build_selection(args, None)["classes"]["duo"]["needs_evidence"], True)  # hinge code changed
        args.files = ["apple/Sources/HassUI/Home.swift"]
        self.assertEqual(pv.build_selection(args, None)["classes"]["duo"]["needs_evidence"], "unknown")

    def test_spec_wording_gives_the_iphone_nothing(self):
        sel = self.select(after={"duo-partial-fold": tree(340.0)}, files=[HINGE_FILE],
                          request="Sections slide to their sides under the hinge on the Duo; scrolling the list is smooth")
        self.assertFalse(sel["classes"]["iphone"]["needs_evidence"])
        self.assertFalse(sel["classes"]["ipad"]["needs_evidence"])

    def test_duo_only_sheet_file_gives_duo_not_iphone(self):
        sel = self.select(files=["apple/Sources/HassDesign/DuoSheetPolicy.swift"])
        self.assertIs(sel["classes"]["duo"]["needs_evidence"], True)
        self.assertFalse(sel["classes"]["iphone"]["needs_evidence"])
        self.assertFalse(sel["classes"]["ipad"]["needs_evidence"])

    def test_everyday_home_words_name_no_motion(self):
        for text in ("Turn the light off", "Open the garage", "Closing the garage door is slow"):
            for kind in pv.KIND_WORDS:
                self.assertFalse(pv.request_names_kind(text, "duo", kind), (text, kind))
        self.assertTrue(pv.request_names_kind("Rotating the Duo is broken", "duo", "rotate"))
        self.assertTrue(pv.request_names_kind("turn the iPad", "ipad", "rotate"))
        self.assertFalse(pv.request_names_kind("turn the iPad", "duo", "rotate"))

    def test_test_files_do_not_count_as_transition_code(self):
        sel = self.select(files=["apple/Tests/HassDesignTests/HingeAvoidanceTests.swift"])
        self.assertFalse(sel["classes"]["duo"]["needs_evidence"])

    def test_folded_turn_never_merges_with_open_turn(self):
        sel = self.select(files=[HINGE_FILE], request="turning the Duo is odd",
                          after={"duo-folded": tree(340.0), "duo-unfolded-portrait": tree(340.0)})
        checked = " ".join(f"{c['what']} {c['covered_by']}" for c in sel["classes"]["duo"]["checked_not_shown"])
        self.assertNotIn("same end layout as open upright", checked)
        self.assertNotIn("same end layout as turning the folded", checked)

    def test_signature_keys(self):
        sig = pv.edge_signature
        self.assertEqual(sig("duo-unfolded-landscape", "duo-partial-fold", "half"),
                         sig("duo-folded", "duo-partial-fold", "half"))
        self.assertNotEqual(sig("duo-folded", "duo-folded", "rotate"),
                            sig("duo-unfolded-portrait", "duo-unfolded-landscape", "rotate"))

    def test_previous_round_marks_unchanged_class_repost_false(self):
        first = self.select(after={"duo-partial-fold": tree(340.0)}, files=[HINGE_FILE])
        prev = self.base / "prev.json"
        prev.write_text(json.dumps(first))
        second = self.select(after={"duo-partial-fold": tree(340.0)}, files=[HINGE_FILE], previous=str(prev), round_=2,
                             after_dir="after-r2")  # same pictures, new folder: no repost
        self.assertFalse(second["classes"]["duo"]["repost"])
        third = self.select(after={"duo-partial-fold": tree(340.0), "duo-folded": tree(340.0)}, files=[HINGE_FILE],
                            previous=str(prev), round_=2)
        self.assertTrue(third["classes"]["duo"]["repost"])
        self.assertTrue(first["classes"]["duo"]["repost"])

    def test_clip_length_when_known(self):
        sel = self.select(after={"duo-partial-fold": tree(340.0)}, files=[HINGE_FILE])
        self.assertIn("about 10 s", pv.render_class(sel, "duo", 1))
        sel["classes"]["duo"]["clips"][0]["seconds"] = 9.6
        self.assertIn(", 10 s.", pv.render_class(sel, "duo", 1))

    def test_untreed_pairs_put_the_named_pose_first_and_never_flat(self):
        names = ("admin-settings", "home", "security", "chores", "climate", "garage")
        sel = self.select(with_trees=False, shot_names=names, files=[HINGE_FILE],
                          request="Security and Home sections stay on one side of the hinge when the Duo is half open")
        pairs = sel["classes"]["duo"]["pairs"]
        self.assertEqual(len(pairs), 4)
        self.assertTrue(all(p["pose"] == "Half open" for p in pairs))
        self.assertEqual([p["surface"] for p in pairs][:2], ["home", "security"])
        self.assertFalse(any(p["compared"] for p in pairs))
        body = pv.render_class(sel, "duo", 1)
        self.assertIn("(not compared)", body)
        self.assertNotIn("| Lying flat", body)

    def test_manifest_unchanged_pose_is_never_picked(self):
        b = write_pack(self.base / "before", {}, with_trees=False)
        a = write_pack(self.base / "after", {}, with_trees=False)
        manifest = json.loads((a / "manifest.json").read_text())
        manifest["poses"]["duo-partial-fold"]["changed"] = False
        (a / "manifest.json").write_text(json.dumps(manifest))
        args = Namespace(branch="x", task="T", round=1, base_pack=str(b), after_pack=str(a), request_file=None,
                         files=[HINGE_FILE], diff_base="none")
        pairs = pv.build_selection(args, None)["classes"]["duo"]["pairs"]
        self.assertTrue(pairs)
        self.assertFalse(any(p["pose_id"] == "duo-partial-fold" for p in pairs))

    def test_shots_pair_on_the_full_stem(self):
        b = write_pack(self.base / "before", {}, with_trees=False, shot_names=("home",))
        a = write_pack(self.base / "after", {}, with_trees=False, shot_names=("home",))
        (b / "duo-partial-fold" / "home--scrolled--uikit-inner.png").write_bytes(b"x")  # no scrolled twin after
        args = Namespace(branch="x", task="T", round=1, base_pack=str(b), after_pack=str(a), request_file=None,
                         files=[HINGE_FILE], diff_base="none")
        for pair in pv.build_selection(args, None)["classes"]["duo"]["pairs"]:
            self.assertNotIn("scrolled", pair["stem"])
            self.assertEqual(Path(pair["before"]).name, Path(pair["after"]).name)

    def test_not_run_poses_are_listed_as_not_run(self):
        sel = self.select(with_trees=False, files=[HINGE_FILE], request="the hinge", not_run=("duo-folded",))
        checked = {c["what"]: c["covered_by"] for c in sel["classes"]["duo"]["checked_not_shown"]}
        self.assertEqual(checked["Folded"], "not run")

    def test_pr_275_example(self):
        sel = self.select(after={"duo-partial-fold": tree(340.0, extra=1)}, files=[HINGE_FILE, "apple/Sources/X.swift"],
                          request="Sections cross the hinge when the Duo is half open")
        duo = sel["classes"]["duo"]
        self.assertEqual(duo["poses"], {"Folded": "same", "Open upright": "same", "Lying flat": "same", "Half open": "changed"})
        self.assertEqual(len(duo["clips"]), 1)
        self.assertEqual(duo["clips"][0]["label"], "Lying flat → Half open → Lying flat")
        self.assertEqual(duo["clips"][0]["direction"], "round trip")
        self.assertTrue(all(p["pose"] == "Half open" for p in duo["pairs"]) and duo["pairs"])
        self.assertFalse(sel["classes"]["iphone"]["needs_evidence"])
        self.assertFalse(sel["classes"]["ipad"]["needs_evidence"])
        checked = " ".join(c["what"] for c in duo["checked_not_shown"])
        self.assertIn("folded to half open", checked)
        self.assertIn("sheets", checked)
        body = pv.render_class(sel, "duo", 2)
        self.assertTrue(body.rstrip().endswith("<!-- sh:evidence:T-x:duo:2 -->"))


class JevShadow(Packs):
    def asker(self, calls):
        class Decision:
            def __init__(self, value):
                self.value = value

            def as_dict(self):
                return {"value": self.value}

        def ask(qid, ctx):
            calls.append((qid, ctx.get("device_class")))
            return Decision(["iphone", "ipad"] if qid == "pr.class_needs_evidence" else True)
        return ask

    def test_shadow_never_changes_the_selection(self):
        kwargs = dict(after={"duo-partial-fold": tree(340.0)}, files=[HINGE_FILE])
        calls = []
        with_jev = self.select(asker=self.asker(calls), **kwargs)
        without = self.select(asker=None, **kwargs)
        self.assertEqual(with_jev["classes"], without["classes"])
        self.assertTrue(calls)
        self.assertIn("pr.class_needs_evidence", with_jev["jev_shadow"])
        self.assertEqual(with_jev["jev_shadow"]["jev_disagrees"], ["iphone", "ipad"])
        self.assertFalse(with_jev["classes"]["ipad"]["needs_evidence"])
        self.assertEqual(pv.device_rows(with_jev), pv.device_rows(without))  # shadow: never shown

    def test_unavailable_is_recorded_and_carried_past(self):
        sel = self.select(after={"duo-partial-fold": tree(340.0)}, asker=lambda q, c: None)
        self.assertEqual(sel["jev_shadow"]["status"], "unavailable")
        self.assertTrue(sel["classes"]["duo"]["needs_evidence"])

    def test_a_raising_client_is_unavailable(self):
        def boom(q, c):
            raise RuntimeError("down")
        sel = self.select(after={"duo-partial-fold": tree(340.0)}, asker=boom)
        self.assertEqual(sel["jev_shadow"]["status"], "unavailable")

    def test_questions_are_registered_shadow_and_valid(self):
        jev = load_tool("jev_ask")
        questions = jev.load_questions()
        for qid in ("pr.class_needs_evidence", "pr.motion_named", "pr.motion_is_point", "pr.motion_direction",
                    "pr.needs_stills", "pr.needs_motion", "pr.plain_language"):
            self.assertEqual(questions[qid].mode, "shadow")
            self.assertEqual(questions[qid].data["version"], 1)
            self.assertEqual(questions[qid].data["evidence"], "unmeasured")


class Render(Packs):
    def test_comment_layout_and_marker(self):
        sel = self.select(after={"duo-partial-fold": tree(340.0)}, files=[HINGE_FILE])
        body = pv.render_class(sel, "duo", 2, task="T-section-sides", summary="Sections stay on one side of the hinge.")
        self.assertTrue(body.startswith("**Verifier** (agent) · iPhone Duo · round 2\n"))
        self.assertIn("Sections stay on one side of the hinge.", body)
        self.assertIn("Poses: Half open — changed", body)
        self.assertIn("| | Before | After |", body)
        self.assertIn("**Clips**", body)
        self.assertIn("Why this one:", body)
        self.assertIn("**Checked, not shown:**", body)
        self.assertIn("<details><summary>Technical record</summary>", body)
        self.assertTrue(body.rstrip().endswith("<!-- sh:evidence:T-section-sides:duo:2 -->"))

    def test_marker_uses_class_key(self):
        sel = self.select(request="iPad rotates badly")
        body = pv.render_class(sel, "ipad", 1)
        self.assertIn("<!-- sh:evidence:T-x:ipad:1 -->", body)
        self.assertIn("· iPad · round 1", body)

    def test_devices_rows_group_by_class(self):
        sel = self.select(after={"duo-partial-fold": tree(340.0)})
        rows = pv.device_rows(sel, {"iphone": "61 iPhone tests"})
        self.assertEqual(len(rows), 3)
        self.assertIn("| iPhone | Unchanged, checked by 61 iPhone tests |", rows)
        self.assertTrue(rows[1].startswith("| iPhone Duo | See the Duo pictures below"))

    def test_cli_select_render_devices(self):
        import contextlib
        import io
        write_pack(self.base / "before", {})
        write_pack(self.base / "after", {"duo-partial-fold": tree(340.0)})
        out = self.base / "selection.json"
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(pv.main(["select", "--branch", "a/b", "--task", "T-9", "--base-pack", str(self.base / "before"),
                                      "--after-pack", str(self.base / "after"), "--files", "x.swift", "--no-jev",
                                      "--out", str(out)]), 0)
        self.assertEqual(json.loads(out.read_text())["jev_shadow"]["status"], "skipped")
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            self.assertEqual(pv.main(["render", "--class", "duo", "--round", "1", "--selection", str(out)]), 0)
            self.assertEqual(pv.main(["devices", "--selection", str(out)]), 0)
        self.assertIn("<!-- sh:evidence:T-9:duo:1 -->", buf.getvalue())
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(pv.main(["render", "--class", "ipad", "--round", "1", "--selection", str(out)]), 3)


if __name__ == "__main__":
    unittest.main()
