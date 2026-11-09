#!/usr/bin/env python3
"""Checks every case in cases/ against schema.json, the atlas catalog and git.

Usage: python3 evals/agents/design-defects/validate.py   (exit 1 on any problem)
Uses only the standard library: a small structural check stands in for a JSON Schema validator.
"""
import json, subprocess, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
schema = json.loads((HERE / "schema.json").read_text())
catalog = {i["id"] for i in json.loads((ROOT / ".agents/design/mockups/catalog.json").read_text())["items"]}
props = schema["properties"]
problems = []
ids = set()
for path in sorted((HERE / "cases").glob("*.json")):
    case = json.loads(path.read_text())
    where = path.name
    extra = set(case) - set(props)
    missing = set(schema["required"]) - set(case)
    if extra or missing:
        problems.append(f"{where}: extra {sorted(extra)} missing {sorted(missing)}")
        continue
    if case["id"] + ".json" != path.name or case["id"] in ids:
        problems.append(f"{where}: id must match the file name and be unique")
    ids.add(case["id"])
    if len(case["owner_report"].split()) > 26:
        problems.append(f"{where}: owner_report over 25 words")
    if case["surface"] is not None and case["surface"] not in catalog:
        problems.append(f"{where}: surface {case['surface']!r} is not in catalog.json")
    for key, allowed in (("poses", props["poses"]["items"]["enum"]),):
        bad = [p for p in case[key] if p not in allowed]
        if bad:
            problems.append(f"{where}: unknown pose {bad}")
    if case["app"] not in props["app"]["enum"] or case["category"] not in props["category"]["enum"]:
        problems.append(f"{where}: bad app or category")
    for ref in ("pre_fix_ref", "fix_ref"):
        if case[ref] and subprocess.run(["git", "-C", str(ROOT), "cat-file", "-e", case[ref] + "^{commit}"], capture_output=True).returncode:
            problems.append(f"{where}: {ref} {case[ref]} is not a commit in this clone")
    if (case["pre_fix_ref"] is None) != (case["fix_ref"] is None):
        problems.append(f"{where}: pre_fix_ref and fix_ref are both set or both null")
print(f"{len(ids)} cases, {len(problems)} problems")
for p in problems:
    print(" ", p)
sys.exit(1 if problems else 0)
