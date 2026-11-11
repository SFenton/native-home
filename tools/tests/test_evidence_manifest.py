"""``tools/evidence_manifest.py``: one reader for the three shapes of an evidence manifest, used by ``pr_note`` and ``pr_visual``."""

import json
import re
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import evidence_manifest  # noqa: E402
import pr_visual  # noqa: E402

SKILL = TOOLS.parent / ".agents" / "skills" / "pose-matrix" / "SKILL.md"


#: The manifest the pose-matrix skill describes, in the shape its example had: path strings and no ``source``.
SKILL_EXAMPLE = {
    "branch": "claude/x", "sha": "<head>", "task": "T-0142", "ran_at": "2026-11-01T18:00:00Z",
    "poses": {
        "duo-partial-fold": {
            "device": "iPhone Duo (HASS)", "udid": "<UDID>", "pose_confirmed": True,
            "screenshots": ["build/evidence/x/duo-partial-fold/home.png"],
            "ax_tree": "build/evidence/x/duo-partial-fold/home.ax.txt",
            "measurements": {"sheet_frame": [0, 0, 455, 874], "min_target_pt": 44},
            "tests": {"FentonHomeUITests/HomeJourneyTests/testX": "pass"},
            "result": "pass|fail|not_run", "failure_class": None, "notes": "",
        }
    },
    "summary": {"pass": 6, "fail": 1, "not_run": 2},
}


def skill_example():
    """The skill's manifest: its ``json`` example when the skill file has one (read only), else ``SKILL_EXAMPLE``. The skill
    names the pose keys in prose; the picture key it names must be one the reader reads."""
    text = SKILL.read_text(encoding="utf-8")
    assert any(f"`{key}`" in text for key in evidence_manifest.MEDIA_KEYS), "the skill names no picture key the reader reads"
    block = re.search(r"```json\n(.*?)\n```", text, re.S)
    return json.loads(block.group(1)) if block else SKILL_EXAMPLE


def as_strings(entries, source):
    """Shape b: path strings under each pose, the pose carries ``source``."""
    poses = {}
    for e in entries:
        poses.setdefault(e["pose"], {"result": "pass", "source": source, "screenshots": []})["screenshots"].append(e["path"])
    return {"poses": poses}


def as_objects(entries, source):
    """Shape c: ``{path, source}`` objects under each pose."""
    poses = {}
    for e in entries:
        poses.setdefault(e["pose"], {"result": "pass", "screenshots": []})["screenshots"].append(
            {"path": e["path"], "source": source})
    return {"poses": poses}


def as_media(entries, source):
    """Shape a: a top-level ``media`` list."""
    return {"media": [{"path": e["path"], "source": source, "pose": e["pose"]} for e in entries]}


class MediaEntryTests(unittest.TestCase):
    def test_manifest_three_shapes(self):
        """Fails if: the skill's own example yields no entry, or the same pictures written as path strings with a pose-level
        source, as ``{path, source}`` objects and as a top-level ``media`` list do not give identical ``media_entries`` (any
        shape yields fewer entries, or loses ``source``, ``class`` or ``pose``)."""
        example = evidence_manifest.media_entries(skill_example())
        self.assertGreaterEqual(len(example), 1)
        for entry in example:
            self.assertEqual(sorted(entry), ["class", "path", "pose", "source"])
            self.assertIn(entry["source"], (None, "demo", "mockup"))
        self.assertEqual({e["class"] for e in example}, {"duo"})
        for source in ("demo", "mockup", "live"):
            want = [dict(e, source=source) for e in example]
            for shape in (as_strings, as_objects, as_media):
                self.assertEqual(evidence_manifest.media_entries(shape(example, source)), want, shape.__name__)

    def test_classes_sources_and_mixed_shapes(self):
        """Fails if: a pose does not map to its evidence class (``iphone``, ``duo`` for iPhone Duo, ``ipad``; anything else
        ``all``), an object's own source does not win over the pose's, ``recordings`` or ``videos`` are skipped, or a mixed
        manifest loses an entry."""
        manifest = {
            "media": [{"path": "m.png", "source": "mockup"}, {"path": "c.png", "source": "demo", "class": "ipad"}],
            "poses": {
                "iphone": {"source": "demo", "screenshots": ["a.png", {"path": "b.png", "source": "live"}, {"path": "n.png"}]},
                "duo-partial-fold": {"recordings": [{"path": "r.mp4", "source": "demo"}], "videos": ["v.mp4"]},
                "ipad-landscape-rotated": {"source": "mockup", "screenshots": ["i.png"]},
                "watch": {"source": "demo", "screenshots": ["w.png"]},
            },
        }
        got = [(e["path"], e["source"], e["class"], e["pose"]) for e in evidence_manifest.media_entries(manifest)]
        self.assertEqual(got, [
            ("m.png", "mockup", "all", None), ("c.png", "demo", "ipad", None),
            ("a.png", "demo", "iphone", "iphone"), ("b.png", "live", "iphone", "iphone"), ("n.png", "demo", "iphone", "iphone"),
            ("r.mp4", "demo", "duo", "duo-partial-fold"), ("v.mp4", None, "duo", "duo-partial-fold"),
            ("i.png", "mockup", "ipad", "ipad-landscape-rotated"), ("w.png", "demo", "all", "watch")])
        self.assertEqual([evidence_manifest.pose_class(p) for p in ("iphone", "duo-folded", "ipad-portrait", "duolingo", None)],
                         ["iphone", "duo", "ipad", "all", "all"])

    def test_a_pose_that_did_not_run_yields_no_entry(self):
        """Fails if: a ``not_run`` pose yields an entry (so a picture), from its own lists or from a ``media`` entry that names
        it, or a pose that ran loses one."""
        manifest = {"media": [{"path": "x.png", "source": "demo", "pose": "ipad-portrait"},
                              {"path": "y.png", "source": "demo", "pose": "iphone"}],
                    "poses": {"ipad-portrait": {"result": "not_run", "source": "demo", "screenshots": ["x.png"]},
                              "iphone": {"result": "pass", "source": "demo", "screenshots": ["y.png"]}}}
        self.assertEqual([e["path"] for e in evidence_manifest.media_entries(manifest)], ["y.png", "y.png"])

    def test_junk_never_raises(self):
        """Fails if: a missing, broken or oddly typed manifest raises instead of reading as empty."""
        with tempfile.TemporaryDirectory() as tmp:
            bad = Path(tmp) / "manifest.json"
            self.assertEqual(evidence_manifest.read(bad), {})
            bad.write_text("not json")
            self.assertEqual(evidence_manifest.read(bad), {})
            bad.write_text("[1, 2]")
            self.assertEqual(evidence_manifest.read(bad), {})
        for junk in ({}, {"poses": [], "media": {}}, {"poses": {"iphone": None, "duo-folded": {"screenshots": "x.png"}},
                                                      "media": [None, 3, {"source": "demo"}, {"path": 7}]}):
            self.assertEqual(evidence_manifest.media_entries(junk), [])
        self.assertEqual(evidence_manifest.poses({"poses": {"iphone": None}}), {"iphone": {}})


class PrVisualReaderTests(unittest.TestCase):
    """``pr_visual.read_pack`` reads the manifest through the same reader."""

    def test_read_pack_takes_results_and_named_screenshots_from_every_shape(self):
        """Fails if: ``pr_visual`` reads a pose's result or its named screenshots differently for the three manifest shapes,
        lists a picture of a pose that did not run, or lets a named file replace the one in the pose folder."""
        with tempfile.TemporaryDirectory() as tmp:
            pack = Path(tmp)
            (pack / "iphone").mkdir()
            (pack / "iphone" / "Home.png").write_bytes(b"in the pose folder")
            (pack / "shots").mkdir()
            for name in ("Home.png", "Sheet.png", "Gone.png"):
                (pack / "shots" / name).write_bytes(name.encode())
            entries = [{"path": "shots/Home.png", "pose": "iphone"}, {"path": "shots/Sheet.png", "pose": "iphone"}]
            seen = []
            for shape in (as_strings, as_objects, as_media):
                manifest = shape(entries, "demo")
                manifest.setdefault("poses", {}).setdefault("iphone", {})["result"] = "fail"
                manifest["poses"]["ipad-portrait"] = {"result": "not_run", "screenshots": ["shots/Gone.png"]}
                (pack / "manifest.json").write_text(json.dumps(manifest))
                seen.append(pr_visual.read_pack(pack))
            self.assertEqual(seen[0], seen[1])
            self.assertEqual(seen[0], seen[2])
            self.assertEqual(seen[0]["iphone"]["result"], "fail")
            self.assertEqual(seen[0]["iphone"]["shots"], {"Home": str(pack / "iphone" / "Home.png"),
                                                          "Sheet": str(pack / "shots" / "Sheet.png")})
            self.assertEqual(seen[0]["ipad-portrait"], {"result": "not_run", "trees": {}, "shots": {}, "unchanged": False})


if __name__ == "__main__":
    unittest.main()
