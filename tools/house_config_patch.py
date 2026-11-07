#!/usr/bin/env python3
"""house_config_patch: add the optional derived-id fields to the server's house document, for upload.

The app no longer derives ids from names. Two optional schema-2 fields carry them instead; a document without a field leaves that
control "not configured" in the app (``ClimateConfig.Room`` and ``AirPurifierConfig``):

- ``climate.rooms[].occupiedOnlyEntityId``: the room's "track only when occupied" switch;
- ``roomDevices.airPurifiers[].aqiEntityId``, ``autoModeEntityId``, ``fanEntityId``, ``modeEntityId``: the entities of a purifier.

This tool fills each missing field from Home Assistant's own registries (read over the SSH add-on's websocket, as
``tools/ha_change.py`` does), so the answer is whatever exists on the server:

- a purifier's fan is the ``fan.*`` entity on the same registry ``device_id`` as its PM2.5 sensor; its AQI, auto-mode and fan-mode
  entities are the generic ``<base>_air_quality_index``, ``<base>_auto_mode`` and ``<base>_fan_mode`` names, kept only when the
  registry has them (``<base>`` is the sensor's id without ``sensor.`` and ``_pm2_5``);
- a room's occupied-only switch is the one ``switch.*`` entity with ``occupied`` in its id whose registry name starts with the
  room's title, else the one in an area named like the room, else the only candidate whose id contains the room's key.

What the registry cannot answer comes from the git-ignored local file ``build/ha/patch-rules.local.json`` (never committed, never
printed): an object of ``{"occupiedOnlyEntityId": "<template with {key}>", "fanEntityId": "<template with {base}>"}``. A field with
no answer at all stays missing and is counted.

    tools/house_config_patch.py                         # read the live document, write build/ha/house.json
    tools/house_config_patch.py --check                 # live document: exit 0 only when every field is there and exists
    tools/house_config_patch.py --check --input FILE    # the same for a local document (the file written above)

Output is counts only: no id, name or value is ever printed. The output stays inside ``build/ha/`` (git-ignored), compact and
key-sorted, and is refused above the integration's 256 KiB limit. A field already present is never changed. Stdlib only.
Documentation: .agents/platforms/apple/ha-operations.md.
"""
from __future__ import annotations

import argparse
import json
import re
import shlex
import subprocess
import sys
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Sequence, Set

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ha_change import WS_CLIENT  # noqa: E402  (the stdlib websocket client that runs on the HA host)

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_HOST = "hass"
REMOTE_DOCUMENT = "/config/fenton_home/house.json"
DEFAULT_OUT = ROOT / "build" / "ha" / "house.json"
LOCAL_RULES = ROOT / "build" / "ha" / "patch-rules.local.json"
#: ``fenton_home`` refuses a larger house file.
BYTE_LIMIT = 256 * 1024
WS_TIMEOUT = 120
HOST_PATTERN = re.compile(r"^[A-Za-z0-9._][A-Za-z0-9._-]*$")

#: Generic Home Assistant integration suffixes for a purifier's other entities (not house names); kept only when the registry has them.
GENERIC_SUFFIXES = {
    "aqiEntityId": "sensor.{base}_air_quality_index",
    "autoModeEntityId": "select.{base}_auto_mode",
    "modeEntityId": "select.{base}_fan_mode",
}
PURIFIER_FIELDS = ("aqiEntityId", "autoModeEntityId", "fanEntityId", "modeEntityId")
OCCUPIED_WORD = "occupied"

Runner = Callable[..., "subprocess.CompletedProcess[str]"]


class PatchError(Exception):
    """A refusal or failure; the message never contains a document or registry value."""


# MARK: - Registry

class Registry:
    """The entity, device and area registries, indexed for the lookups the rules need."""

    def __init__(self, entities: Sequence[dict], devices: Sequence[dict] = (), areas: Sequence[dict] = ()):
        self.entities = [e for e in entities if isinstance(e, dict) and isinstance(e.get("entity_id"), str)
                         and not e.get("disabled_by")]
        self.ids: Set[str] = {e["entity_id"] for e in self.entities}
        self.device_area = {d.get("id"): d.get("area_id") for d in devices if isinstance(d, dict)}
        self.area_name = {a.get("area_id"): a.get("name") for a in areas if isinstance(a, dict)}

    def entity(self, entity_id: str) -> Optional[dict]:
        return next((e for e in self.entities if e["entity_id"] == entity_id), None)

    def area_of(self, entity: dict) -> str:
        """The entity's area name (its own area, else its device's), casefolded, or ""."""
        area_id = entity.get("area_id") or self.device_area.get(entity.get("device_id"))
        return str(self.area_name.get(area_id) or "").casefold()

    def fan_on_device_of(self, sensor_id: str) -> Optional[str]:
        """The single ``fan.*`` entity sharing the sensor's registry device, or None."""
        sensor = self.entity(sensor_id)
        device = sensor.get("device_id") if sensor else None
        if not device:
            return None
        fans = [e["entity_id"] for e in self.entities if e.get("device_id") == device and e["entity_id"].startswith("fan.")]
        return fans[0] if len(fans) == 1 else None

    def occupied_switch(self, title: str, key: str) -> Optional[str]:
        """The one occupied-only switch for a room: its registry name starts with the room's title, else it sits in an area named
        like the room, else it is the only candidate with the room's key in its id."""
        candidates = [e for e in self.entities if e["entity_id"].startswith("switch.") and OCCUPIED_WORD in e["entity_id"]]
        wanted = title.casefold()
        for match in (
            lambda e: any(str(e.get(k) or "").casefold().startswith(wanted) for k in ("name", "original_name")),
            lambda e: self.area_of(e) == wanted,
            lambda e: key in e["entity_id"],
        ):
            found = [e["entity_id"] for e in candidates if match(e)]
            if len(found) == 1:
                return found[0]
        return None


# MARK: - Patching

def room_key(title: str) -> str:
    """The web's ``thermostatRoomKey``: lower-case with spaces as underscores."""
    return title.lower().replace(" ", "_")


def purifier_base(pm25: str) -> str:
    """A purifier's shared prefix: its PM2.5 sensor id without the ``sensor.`` prefix and the ``_pm2_5`` suffix."""
    base = pm25[len("sensor."):] if pm25.startswith("sensor.") else pm25
    return base[: -len("_pm2_5")] if base.endswith("_pm2_5") else base


def load_local_rules(path: Path = LOCAL_RULES) -> Dict[str, str]:
    """The git-ignored fallback templates, or {} when the file is absent or unreadable."""
    try:
        rules = json.loads(path.read_text())
    except (OSError, ValueError):
        return {}
    return {k: v for k, v in rules.items() if isinstance(v, str)} if isinstance(rules, dict) else {}


def patch(document: Dict[str, Any], registry: Registry, local_rules: Optional[Dict[str, str]] = None) -> Dict[str, int]:
    """Fill the missing fields of ``document`` in place from the registry (then the local rules). Returns counts.

    Counts: ``rooms``, ``rooms_filled``, ``purifiers``, ``purifier_fields_filled``, ``unresolved`` (fields still missing).
    """
    rules = local_rules or {}
    counts = {"rooms": 0, "rooms_filled": 0, "purifiers": 0, "purifier_fields_filled": 0, "unresolved": 0}

    def fill(holder: dict, field: str, found: Optional[str], template: Optional[str], **names: str) -> None:
        if field in holder:
            return
        value = found or (template.format(**names) if template else None)
        if value:
            holder[field] = value
            counts["rooms_filled" if field == "occupiedOnlyEntityId" else "purifier_fields_filled"] += 1
        else:
            counts["unresolved"] += 1

    climate = document.get("climate")
    for room in (climate.get("rooms", []) if isinstance(climate, dict) else []):
        if not isinstance(room, dict) or not isinstance(room.get("title"), str):
            continue
        counts["rooms"] += 1
        key = room_key(room["title"])
        fill(room, "occupiedOnlyEntityId", registry.occupied_switch(room["title"], key), rules.get("occupiedOnlyEntityId"), key=key)
    devices = document.get("roomDevices")
    for purifier in (devices.get("airPurifiers", []) if isinstance(devices, dict) else []):
        if not isinstance(purifier, dict) or not isinstance(purifier.get("pm25EntityId"), str):
            continue
        counts["purifiers"] += 1
        base = purifier_base(purifier["pm25EntityId"])
        for field, template in GENERIC_SUFFIXES.items():
            guess = template.format(base=base)
            fill(purifier, field, guess if guess in registry.ids else None, None)
        fill(purifier, "fanEntityId", registry.fan_on_device_of(purifier["pm25EntityId"]), rules.get("fanEntityId"), base=base)
    return counts


def check(document: Dict[str, Any], registry: Registry) -> Dict[str, int]:
    """Counts for ``--check``: rooms and purifiers with every field, and the ids of those fields that exist in the registry."""
    out = {"rooms": 0, "rooms_with_field": 0, "purifiers": 0, "purifiers_complete": 0, "ids": 0, "ids_found": 0}
    climate = document.get("climate")
    for room in (climate.get("rooms", []) if isinstance(climate, dict) else []):
        if isinstance(room, dict) and isinstance(room.get("title"), str):
            out["rooms"] += 1
            value = room.get("occupiedOnlyEntityId")
            if isinstance(value, str) and value:
                out["rooms_with_field"] += 1
                out["ids"] += 1
                out["ids_found"] += value in registry.ids
    devices = document.get("roomDevices")
    for purifier in (devices.get("airPurifiers", []) if isinstance(devices, dict) else []):
        if isinstance(purifier, dict) and isinstance(purifier.get("pm25EntityId"), str):
            out["purifiers"] += 1
            values = [purifier.get(f) for f in PURIFIER_FIELDS]
            if all(isinstance(v, str) and v for v in values):
                out["purifiers_complete"] += 1
            for value in values:
                if isinstance(value, str) and value:
                    out["ids"] += 1
                    out["ids_found"] += value in registry.ids
    return out


def check_passes(counts: Dict[str, int]) -> bool:
    """Every room and purifier has its fields and every named id exists."""
    return (counts["rooms"] == counts["rooms_with_field"] and counts["purifiers"] == counts["purifiers_complete"]
            and counts["ids"] == counts["ids_found"])


def encode(document: Dict[str, Any]) -> str:
    """The document as the integration stores it: compact, key-sorted, within its size limit."""
    text = json.dumps(document, separators=(",", ":"), sort_keys=True, ensure_ascii=False)
    if len(text.encode()) > BYTE_LIMIT:
        raise PatchError(f"the patched document is {len(text.encode())} bytes, over the {BYTE_LIMIT} limit")
    return text


# MARK: - The server

def default_run(args: List[str], input: Optional[str] = None) -> "subprocess.CompletedProcess[str]":
    return subprocess.run(args, capture_output=True, text=True, input=input, timeout=180, check=False)


def ssh(host: str, remote: str, run: Runner, input: Optional[str] = None) -> str:
    if not HOST_PATTERN.match(host):
        raise PatchError("--host: expected an ssh alias (letters, digits, . _ -)")
    proc = run(["ssh", "-o", "BatchMode=yes", host, remote], input=input) if input is not None else run(["ssh", "-o", "BatchMode=yes", host, remote])
    if proc.returncode != 0:
        raise PatchError(f"ssh {host}: the command failed (exit {proc.returncode})")
    return proc.stdout


def fetch_document(host: str, run: Runner = default_run) -> Dict[str, Any]:
    """Read the live document over ssh. Errors name the step, never the content."""
    try:
        document = json.loads(ssh(host, f"cat {REMOTE_DOCUMENT}", run))
    except ValueError:
        raise PatchError("the house document on the server is not valid JSON") from None
    if not isinstance(document, dict):
        raise PatchError("the house document on the server is not an object")
    return document


def ws_list(host: str, command: str, run: Runner = default_run) -> List[dict]:
    """One registry list through the add-on's websocket client (the add-on's own token, never printed)."""
    message = json.dumps({"type": command})
    out = ssh(host, f"python3 - {shlex.quote(message)} {WS_TIMEOUT}", run, input=WS_CLIENT)
    try:
        reply = json.loads(out.strip().splitlines()[-1])
    except (ValueError, IndexError):
        raise PatchError("no usable reply from the websocket client") from None
    if not reply.get("success") or not isinstance(reply.get("result"), list):
        raise PatchError(f"{command} failed")
    return reply["result"]


def fetch_registry(host: str, run: Runner = default_run) -> Registry:
    """The live entity, device and area registries."""
    return Registry(ws_list(host, "config/entity_registry/list", run), ws_list(host, "config/device_registry/list", run),
                    ws_list(host, "config/area_registry/list", run))


def inside_scratch(path: Path) -> bool:
    """Whether ``path`` resolves inside ``build/ha/`` (the git-ignored scratch place the apply tool accepts)."""
    try:
        path.resolve().relative_to((ROOT / "build" / "ha").resolve())
    except ValueError:
        return False
    return True


def main(argv: Optional[Sequence[str]] = None, run: Runner = default_run, rules_path: Path = LOCAL_RULES) -> int:
    """Run the tool; returns 0 done (or, with --check, complete), 1 refused, failed or incomplete."""
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--host", default=DEFAULT_HOST, help="ssh alias of the Home Assistant to read (default hass)")
    ap.add_argument("--input", type=Path, help="use this local document instead of reading the server's")
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT, help="where to write (must be inside build/ha/)")
    ap.add_argument("--check", action="store_true", help="exit 0 only when every field is present and exists; write nothing")
    args = ap.parse_args(argv)
    try:
        if args.input:
            try:
                document = json.loads(args.input.read_text())
            except (OSError, ValueError):
                raise PatchError("--input: not a readable JSON file") from None
            if not isinstance(document, dict):
                raise PatchError("--input: the document is not an object")
        else:
            document = fetch_document(args.host, run)
        registry = fetch_registry(args.host, run)
        if args.check:
            counts = check(document, registry)
            ok = check_passes(counts)
            print(f"house_config_patch: rooms {counts['rooms_with_field']}/{counts['rooms']}, purifiers "
                  f"{counts['purifiers_complete']}/{counts['purifiers']}, ids found {counts['ids_found']}/{counts['ids']}; "
                  f"{'complete' if ok else 'INCOMPLETE'}")
            return 0 if ok else 1
        counts = patch(document, registry, load_local_rules(rules_path))
        text = encode(document)
        if not inside_scratch(args.out):
            raise PatchError("--out must be inside build/ha/")
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text)
        print(f"house_config_patch: rooms {counts['rooms']} (filled {counts['rooms_filled']}), purifiers {counts['purifiers']} "
              f"(fields filled {counts['purifier_fields_filled']}), unresolved {counts['unresolved']}; wrote "
              f"{len(text.encode())} bytes to {args.out.resolve().relative_to(ROOT.resolve())}")
        return 1 if counts["unresolved"] else 0
    except PatchError as error:
        print(f"house_config_patch: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
