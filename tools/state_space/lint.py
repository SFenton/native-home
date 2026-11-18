#!/usr/bin/env python3
"""Mapping-completeness lint for a publication.

Finds the authoring gaps that make a tile say a constant word for an ordinary state (the "Unknown" on a PC tile).
Input is a publication envelope or a bare composition document, passed as a path; the layout of a house is house data, so the
tool prints nothing that names a node, a page or an entity unless ``--details`` is given, and its report is counts plus a
table by rule, node type and kind. Run it over the git-ignored draft; never commit its input or the detailed output.

Rules:

- ``empty-map``: a text slot (an object with ``states`` and ``fallbackText``) whose ``states`` is empty and whose fallback is a
  constant. Every state the entity can have reads the constant. A slot with a ``projection`` takes its text from a native
  projection and is skipped.
- ``partial-map``: ``states`` lists some values but not every ordinary state of the closed set the node's kind implies (a
  remote ``device`` or ``card`` reads a boolean: ``on`` and ``off``). The missing states read the constant fallback.
- ``reachable-fallback``: a constant that reads as a failure ("Unknown", "Unavailable", "Error", "N/A") sits in a slot the two
  rules above did not flag, so it is still reachable by a state the lint cannot rule out. Low severity: review.
- ``unread-helper``: a data source nothing reads, or an entity id named in ``--helpers`` (a JSON list of ids the old layout read,
  for example a status text helper) that the publication never mentions.

Usage::

    lint.py PUBLICATION.json [--helpers FILE] [--details] [--report PATH] [--json]

Exit status 1 when any finding has severity ``high``; 0 otherwise. Standard library only.
"""
from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path
from typing import Any, Iterator

ERROR_WORDS = {"unknown", "unavailable", "error", "n/a", "--", "-", "?"}
BINARY = ("on", "off")
DEVICE_KINDS = {"device", "card"}
SEVERITY = {"empty-map": "high", "partial-map": "medium", "reachable-fallback": "low", "unread-helper": "medium"}


def document_of(data: dict) -> dict:
    """The composition document of an envelope, or the data itself when it already is one."""
    return data.get("document", data) if isinstance(data, dict) else {}


def walk(value: Any, path: str = "", node: dict | None = None) -> Iterator[tuple[str, dict, dict | None]]:
    """Yield ``(path, dict, nearest enclosing node)`` for every object; a node has ``type`` and ``props``."""
    if isinstance(value, dict):
        owner = value if isinstance(value.get("props"), dict) and "type" in value else node
        yield path, value, owner
        for key, child in value.items():
            yield from walk(child, f"{path}/{key}", owner)
    elif isinstance(value, list):
        for index, child in enumerate(value):
            yield from walk(child, f"{path}/{index}", node)


def is_slot(obj: dict) -> bool:
    return isinstance(obj.get("states"), list) and isinstance(obj.get("fallbackText"), str)


def covered_values(states: list) -> set[str]:
    return {s.get("value") for s in states if isinstance(s, dict) and isinstance(s.get("value"), str)}


def strings(value: Any) -> Iterator[str]:
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for child in value.values():
            yield from strings(child)
    elif isinstance(value, list):
        for child in value:
            yield from strings(child)


def lint(data: dict, helpers: list[str] | None = None) -> list[dict]:
    """Every finding of the publication, in document order. ``helpers`` are entity ids the old layout read."""
    document = document_of(data)
    findings: list[dict] = []

    def add(rule: str, path: str, node: dict | None, detail: str) -> None:
        props = (node or {}).get("props", {})
        findings.append({"rule": rule, "severity": SEVERITY[rule], "path": path, "node_id": (node or {}).get("id"),
                         "node_type": (node or {}).get("type", "-"), "kind": props.get("kind", "-"), "detail": detail})

    for path, obj, node in walk(document):
        if not is_slot(obj):
            continue
        if "projection" in obj:
            continue
        fallback = obj["fallbackText"]
        values = covered_values(obj["states"])
        kind = (node or {}).get("props", {}).get("kind")
        closed = set(BINARY) if kind in DEVICE_KINDS and (node or {}).get("type") == "remote-control" else None
        if not obj["states"] and fallback:
            add("empty-map", path, node, "no state maps to a word; every state reads the constant fallback")
        elif closed and closed - values:
            add("partial-map", path, node, f"{len(closed - values)} of {len(closed)} ordinary states unmapped: {sorted(closed - values)}")
        elif fallback.strip().lower() in ERROR_WORDS:
            add("reachable-fallback", path, node, "failure word as a constant fallback; the ordinary states it can see are not provable")

    sources = [s for s in document.get("dataSources", []) if isinstance(s, dict) and isinstance(s.get("id"), str)]
    outside = {k: v for k, v in document.items() if k != "dataSources"}
    referenced = set(strings(outside))
    referenced.update(s for src in sources for key, v in src.items() if key != "id" for s in strings(v))
    for index, source in enumerate(sources):
        if source["id"] not in referenced:
            add("unread-helper", f"/dataSources/{index}", None, "a data source nothing reads")
    if helpers:
        text = "\n".join(strings(document))
        for entity_id in helpers:
            if entity_id not in text:
                add("unread-helper", "/", None, f"a helper the old layout read is never mentioned: {entity_id}")
    return findings


def counts(findings: list[dict]) -> dict[str, int]:
    return dict(sorted(Counter(f["rule"] for f in findings).items()))


def table(findings: list[dict]) -> list[tuple[str, str, str, int]]:
    """Generic rows: rule, node type, kind, count. No ids, titles or paths."""
    tally = Counter((f["rule"], f["node_type"], f["kind"]) for f in findings)
    return [(*key, n) for key, n in sorted(tally.items())]


def report(findings: list[dict], nodes: int) -> str:
    lines = ["# State lint", "", f"Counts only; no layout detail. Nodes scanned: {nodes}.", "", "| Rule | Severity | Findings |", "|---|---|---|"]
    for rule, n in counts(findings).items():
        lines.append(f"| {rule} | {SEVERITY[rule]} | {n} |")
    if not findings:
        lines.append("| (none) | - | 0 |")
    lines += ["", "| Rule | Node type | Kind | Findings |", "|---|---|---|---|"]
    lines += [f"| {r} | {t} | {k} | {n} |" for r, t, k, n in table(findings)]
    return "\n".join(lines) + "\n"


def count_nodes(data: dict) -> int:
    return sum(1 for _, obj, node in walk(document_of(data)) if node is obj)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("publication", type=Path)
    parser.add_argument("--helpers", type=Path, help="JSON list of entity ids the old layout read")
    parser.add_argument("--details", action="store_true", help="print node ids and paths (house data: do not commit)")
    parser.add_argument("--report", type=Path, help="write the counts-only markdown report here")
    parser.add_argument("--json", action="store_true", help="print the counts as JSON")
    args = parser.parse_args(argv)
    data = json.loads(args.publication.read_text(encoding="utf-8"))
    helpers = json.loads(args.helpers.read_text(encoding="utf-8")) if args.helpers else None
    findings = lint(data, helpers)
    text = report(findings, count_nodes(data))
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(text, encoding="utf-8")
    if args.json:
        print(json.dumps(counts(findings)))
    else:
        print(text, end="")
    if args.details:
        for f in findings:
            print(f"{f['rule']}\t{f['severity']}\t{f['node_id']}\t{f['path']}\t{f['detail']}")
    return 1 if any(f["severity"] == "high" for f in findings) else 0


if __name__ == "__main__":
    sys.exit(main())
