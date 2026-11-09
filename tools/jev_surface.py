#!/usr/bin/env python3
"""jev_surface: the surface list `research.release_impact` is asked about (stdlib only).

The list is generated from the Swift sources so it follows the code: the Home Assistant domains and services the
app calls, the HAKit types it uses, and the system frameworks it imports. A release note, changelog entry or
upgrade guide is then checked against it with one noul per entry ("does this change affect `light.turn_on`?").

    python3 tools/jev_surface.py                 # JSON: {"domains": [...], "services": [...], "hakit": [...], "frameworks": [...]}
    python3 tools/jev_surface.py --criteria      # the `research.release_impact` criteria (name -> description)
    python3 tools/jev_surface.py --text          # one entry per line

Services are found by literal call sites (`callService("light", "turn_on"`, `domain: "light", service: "turn_on"`)
and by `"domain", "verb"` string pairs (a common Home Assistant verb) whose domain is one the app calls: services built from variables are not
listed. This is a best effort starting list for a hint, never a complete inventory.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ("apple/Sources", "apple/Apps")
#: Modules that are this project or noise; everything else imported is a framework worth checking release notes for.
LOCAL_MODULES = frozenset({"HassCore", "HassDesign", "HassUI", "HassTelemetry", "FentonActivityModel",
                           "FentonActivityViews", "Foundation", "Darwin", "ObjectiveC", "XCTest", "Testing",
                           "os", "Observation", "CoreGraphics", "QuartzCore", "AppKit"})
#: HAKit symbols that look like `HA...` but are not (hashes, project types).
NOT_HAKIT = frozenset({"HASS", "HASH", "HASE", "HAKit"})
IMPORT = re.compile(r"^\s*(?:@testable\s+)?import\s+([A-Za-z0-9_]+)", re.MULTILINE)
CALL = re.compile(r"call[A-Za-z]*Service[A-Za-z]*\(\s*\"([a-z_0-9]+)\"\s*,\s*\"([a-z_0-9]+)\"|"
                  r"domain:\s*\"([a-z_0-9]+)\"\s*,\s*service:\s*\"([a-z_0-9]+)\"")
VERB = (r"turn_on|turn_off|toggle|press|reload|start|stop|pause|locate|return_to_base|open_cover|close_cover|stop_cover|"
        r"set_[a-z_0-9]+|select_[a-z_0-9]+|increment|decrement|trigger|add_item|update_item|remove_item")
PAIR = re.compile(r"\"([a-z_0-9]+)\"\s*,\s*\"(" + VERB + r")\"")
HAKIT = re.compile(r"\bHA[A-Z][A-Za-z]+\b")
CALLED = re.compile(r"\bHAKit\.[a-z][A-Za-z]*")


#: Core Home Assistant domains: a `"domain", "verb"` pair with one of these counts even when no literal call site names it.
CORE_DOMAINS = frozenset({"light", "switch", "fan", "cover", "climate", "vacuum", "script", "automation", "button",
                          "number", "select", "media_player", "lock", "scene", "homeassistant", "todo", "weather",
                          "input_boolean", "input_button", "input_datetime", "input_number", "input_select",
                          "input_text", "valve", "water_heater", "humidifier", "remote", "siren", "camera"})


def swift_files(root: Path = ROOT) -> list[Path]:
    """Every `.swift` file under the app's source folders, sorted."""
    out: list[Path] = []
    for folder in SOURCES:
        out += sorted((root / folder).rglob("*.swift")) if (root / folder).is_dir() else []
    return out


def surface(root: Path = ROOT) -> dict[str, list[str]]:
    """The generated surface: `domains`, `services` (`domain.service`), `hakit` and `frameworks`, each sorted."""
    texts = [p.read_text(encoding="utf-8", errors="replace") for p in swift_files(root)]
    services: set[str] = set()
    for text in texts:
        for match in CALL.finditer(text):
            domain, service = (match.group(1), match.group(2)) if match.group(1) else (match.group(3), match.group(4))
            services.add(f"{domain}.{service}")
    domains = {s.split(".", 1)[0] for s in services}
    for text in texts:
        for match in PAIR.finditer(text):
            if match.group(1) in domains or match.group(1) in CORE_DOMAINS:
                services.add(f"{match.group(1)}.{match.group(2)}")
    domains = {s.split(".", 1)[0] for s in services}
    hakit: set[str] = set()
    frameworks: set[str] = set()
    for text in texts:
        hakit |= {name for name in HAKIT.findall(text) if name not in NOT_HAKIT}
        hakit |= set(CALLED.findall(text))
        frameworks |= {m for m in IMPORT.findall(text) if m not in LOCAL_MODULES}
    return {"domains": sorted(domains), "services": sorted(services), "hakit": sorted(hakit),
            "frameworks": sorted(frameworks)}


def criteria(root: Path = ROOT) -> dict[str, str]:
    """The `research.release_impact` criteria: one described surface entry per key, in a stable order."""
    data = surface(root)
    out: dict[str, str] = {}
    for domain in data["domains"]:
        out[f"domain:{domain}"] = f"the Home Assistant `{domain}` integration or entity domain (its entities, state attributes or features)"
    for service in data["services"]:
        out[f"service:{service}"] = f"the Home Assistant service `{service}` (its fields, behavior, name or availability)"
    for name in data["hakit"]:
        out[f"hakit:{name}"] = f"the HAKit API `{name}` (the Swift client library for the Home Assistant websocket)"
    for name in data["frameworks"]:
        out[f"framework:{name}"] = f"Apple's `{name}` framework (its API, behavior or availability on iOS)"
    return out


def main(argv: list[str] | None = None) -> int:
    """Command-line entry point."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--criteria", action="store_true", help="print the release_impact criteria")
    parser.add_argument("--text", action="store_true", help="one entry per line")
    args = parser.parse_args(argv)
    result: Any = criteria() if args.criteria else surface()
    if args.text:
        names = list(result) if args.criteria else [f"{k}:{v}" for k, vs in result.items() for v in vs]
        print("\n".join(names))
    else:
        print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
