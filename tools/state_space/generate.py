#!/usr/bin/env python3
"""Generate the state space: one row per (tile kind, variant, entity state).

Inputs (all generic; see tools/state_space/README.md):

- ``kinds.json``: the hand-kept registry of tile kinds, their domain, state sets and variants.
- ``ha-states-<tag>.json``: the closed state sets read from the pinned Home Assistant core tag.
- ``observed-text.json``: the observed words of free-text helpers. The file in the repo is a generic schema with placeholder
  values; the real one is house data and lives under ``build/state-space/`` (git-ignored), passed with ``--observed``.

Output: ``apple/Tests/HassCoreTests/StateGolden/state-space.json`` (deterministic, checked in) with rows
``{id, kind, selector, entity_id, domain, state, attributes, class, source, reviewed}``. ``state`` null is a missing entity.

    generate.py                       write the checked-in file
    generate.py --check               exit 1 when the checked-in file is not what the inputs generate
    generate.py --observed PATH       use another observed-text file (write it elsewhere with --out; never over the checked-in one)
    generate.py ha-diff OLD NEW       list states a newer ha-states file adds, as unreviewed rows

Only the Python standard library.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
DEFAULT_OUT = ROOT / "apple/Tests/HassCoreTests/StateGolden/state-space.json"
DEFAULT_HA = HERE / "ha-states-2026.11.0.json"
DEFAULT_OBSERVED = HERE / "observed-text.json"
DEFAULT_KINDS = HERE / "kinds.json"


def slug(text: str) -> str:
    """A stable id fragment: lower case, runs of other characters become one hyphen; empty is ``empty``."""
    if text == "":
        return "empty"
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-") or "x"


def _load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def entity_id(domain: str, kind_id: str, suffix: str = "") -> str:
    """A generic ``demo_`` entity id for a kind; never a house id."""
    return f"{domain}.demo_{kind_id.replace('-', '_')}{suffix}"


def build_rows(kinds: dict, ha: dict, observed: dict) -> list[dict]:
    """Every row of the state space, in a stable order."""
    rows: list[dict] = []
    universal = ha["universal"]
    for kind in kinds["kinds"]:
        for variant in kind["variants"]:
            selector = variant["selector"]
            attrs = variant.get("attributes", {})
            extra = {"options": variant["options"]} if "options" in variant else {}

            def add(domain: str, eid: str, state: str | None, cls: str, source: str, selector: str = selector,
                    attributes: dict = attrs, reviewed: bool = True) -> None:
                token = "missing" if state is None else slug(state)
                row = {"id": f"{kind['id']}.{selector}.{token}", "kind": kind["id"], "selector": selector,
                       "entity_id": eid, "domain": domain, "state": state, "attributes": attributes,
                       "class": cls, "source": source, "reviewed": reviewed, **extra}
                rows.append(row)

            base_eid = entity_id(kind["domain"], kind["id"])
            seen: set[str] = set()
            for set_name in kind["state_sets"]:
                entry = ha["sets"][set_name]
                for state in entry["states"]:
                    if state in seen:
                        continue
                    seen.add(state)
                    cls = "transitional" if state in entry.get("transitional", []) else "content"
                    add(kind["domain"], base_eid, state, cls, f"ha:{set_name}@{ha['ha_tag']}")
            for state in universal:
                add(kind["domain"], base_eid, state, state, "universal")
            add(kind["domain"], base_eid, None, "missing", "universal")
            helper = kind.get("free_text")
            if helper:
                spec = observed["helpers"].get(helper, {"values": []})
                values = list(spec["values"]) + ([""] if spec.get("include_empty") else [])
                unreviewed = set(spec.get("unreviewed", []))
                helper_eid = entity_id("input_text", kind["id"], "_status")
                seen_text: set[str] = set()
                for value in values:
                    if value in seen_text:
                        continue
                    seen_text.add(value)
                    add("input_text", helper_eid, value, "free-text", f"observed:{helper}", selector="helper", attributes={},
                        reviewed=value not in unreviewed)
                for state in universal:
                    add("input_text", helper_eid, state, state, "universal", selector="helper", attributes={})
    ids = [row["id"] for row in rows]
    duplicates = sorted({i for i in ids if ids.count(i) > 1})
    if duplicates:
        raise SystemExit(f"generate: duplicate row ids (two observed values slug alike?): {duplicates[:5]}")
    return rows


def sizes(rows: list[dict]) -> dict[str, int]:
    """Row count per kind, in the registry's order."""
    out: dict[str, int] = {}
    for row in rows:
        out[row["kind"]] = out.get(row["kind"], 0) + 1
    return out


def document(kinds_path: Path, ha_path: Path, observed_path: Path) -> dict:
    kinds, ha, observed = _load(kinds_path), _load(ha_path), _load(observed_path)
    rows = build_rows(kinds, ha, observed)
    return {"schema": 1, "ha_tag": ha["ha_tag"], "row_count": len(rows), "per_kind": sizes(rows), "rows": rows}


def render(doc: dict) -> str:
    """Deterministic text: one row per line, so a diff reads."""
    head = {k: v for k, v in doc.items() if k != "rows"}
    lines = [json.dumps(r, ensure_ascii=False, sort_keys=True) for r in doc["rows"]]
    return json.dumps(head, ensure_ascii=False, sort_keys=True)[:-1] + ',"rows":[\n' + ",\n".join(lines) + "\n]}\n"


def ha_diff(old: dict, new: dict) -> list[dict]:
    """States ``new`` has that ``old`` lacks, per set, as unreviewed rows the lint treats as open."""
    out = []
    for name, entry in new["sets"].items():
        before = set(old["sets"].get(name, {}).get("states", []))
        for state in entry["states"]:
            if state not in before:
                out.append({"set": name, "state": state, "reviewed": False, "ha_tag": new["ha_tag"]})
    return out


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", nargs="?", choices=["generate", "ha-diff"], default="generate")
    parser.add_argument("paths", nargs="*")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--kinds", type=Path, default=DEFAULT_KINDS)
    parser.add_argument("--ha", type=Path, default=DEFAULT_HA)
    parser.add_argument("--observed", type=Path, default=DEFAULT_OBSERVED)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    args = parser.parse_args(argv)
    if args.command == "ha-diff":
        if len(args.paths) != 2:
            parser.error("ha-diff takes OLD and NEW ha-states files")
        added = ha_diff(_load(Path(args.paths[0])), _load(Path(args.paths[1])))
        print(json.dumps(added, indent=1))
        return 1 if added else 0
    text = render(document(args.kinds, args.ha, args.observed))
    if args.check:
        current = args.out.read_text(encoding="utf-8") if args.out.exists() else ""
        if current != text:
            print(f"generate: {args.out} is stale; run tools/state_space/generate.py", file=sys.stderr)
            return 1
        return 0
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(text, encoding="utf-8")
    print(f"wrote {args.out} ({text.count(chr(10)) - 2} rows)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
