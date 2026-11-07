#!/usr/bin/env python3
"""gen_demo_package: DemoHouse export -> the files the test Home Assistant instance serves.

    python3 tools/test_ha/gen_demo_package.py [--export build/ha/demo-house.json] [--out build/ha/test-instance]

``--export`` is the file the DEBUG-only ``DemoHouseExportTests`` writes (``tools/test_ha/export_demo_house.sh``): the house-config
document plus one resting state per entity id it names. Output (under ``--out``, inside the git-ignored ``build/ha/`` scratch
place so ``tools/ha_change.py apply`` may upload it):

    config/packages/demo_house.yaml        helpers, scripts, automations, persons and the template entities
    config/packages/demo_house_extra.yaml  template climate, vacuum, alarm_control_panel, weather (keys to confirm
                                            in the step-6 spike; push it separately)
    config/fenton_home/house.json          the document the ``fenton_home`` integration serves (at most 256 KiB)
    config/custom_components/fenton_demo/demo_data.json   todo, valve, camera, remote, media_player and sun ids for the test-only component

Every id in the export comes from exactly one source (native helper, script, automation, person, template, or the
``fenton_demo`` component: todo, valve, camera, remote, media_player, sun, as the template integration has no media_player); an id no source can make stops the run, so the coverage never silently shrinks. Template
switch, light, fan, lock, cover, number and select entities read a backing ``input_*`` helper (``demo_state_<domain>_<object>``)
so a service call from a journey changes state truthfully. Resting values come from the export (``DemoHouse.states``), the one
source the app tests also read. Stdlib only; the YAML is emitted as block mappings with JSON scalars (valid YAML).
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

ROOT = Path(__file__).resolve().parents[2]
EXPORT_VERSION = 1
HOUSE_BYTE_LIMIT = 256 * 1024  # fenton_home const.py: the integration refuses a larger house file

ENTITY_ID = re.compile(r"^[a-z_]+\.demo_[a-z0-9_]+$")
BARE_ID = re.compile(r"^demo_[a-z0-9_]+$")
#: A document key whose bare ``demo_*`` value is not a script service name.
NOT_A_SCRIPT_KEYS = {"scheduleId"}

#: Domains made by Home Assistant's own helper integrations (the YAML key is the domain).
HELPER_DOMAINS = ("input_boolean", "input_text", "input_number", "input_datetime", "input_select", "input_button", "counter",
                  "timer", "schedule")
#: Domains the generated template package makes (the stock-documented ones).
TEMPLATE_DOMAINS = ("sensor", "binary_sensor", "switch", "light", "fan", "lock", "cover", "button", "number", "select")
#: Template domains whose keys need the spike to confirm (kept in their own file).
EXTRA_TEMPLATE_DOMAINS = ("climate", "vacuum", "alarm_control_panel", "weather")
#: Domains the test-only component makes (no stock YAML source).
COMPONENT_DOMAINS = ("todo", "valve", "camera", "remote", "media_player", "sun")
OTHER_DOMAINS = ("script", "automation", "person")
#: Template domains with a backing input_* helper.
BACKED = {"switch": "input_boolean", "light": "input_boolean", "fan": "input_boolean", "lock": "input_boolean",
          "cover": "input_boolean", "number": "input_number", "select": "input_select"}

#: Template keys whose schema is ``cv.template`` in Core 2026.10.4 (components/template/*.py, read in the live container). A
#: list or dict there is rejected; the template integration then logs and SKIPS the block, so ``ha core check`` passes and the
#: entities silently vanish. Every such key must therefore be a string (a number or bool is turned into one by Core).
TEMPLATE_STRING_KEYS = frozenset({
    "state", "options", "hvac_modes", "hvac_mode", "current_temperature", "target_temperature", "condition", "humidity",
    "temperature", "min", "max", "step", "name", "availability", "icon", "picture",
})
SELECT_OPTIONS_TEMPLATE = "{{ " + repr(["Option 1", "Option 2"]) + " }}"
HVAC_MODES_TEMPLATE = "{{ " + repr(["off", "heat", "cool"]) + " }}"

FIXED_DATETIME = "2024-01-01 00:00:00"
SELECT_OPTIONS = ["Option 1", "Option 2"]


class GenError(Exception):
    """The export cannot be turned into a package."""


# MARK: - Reading the export

def load_export(path: Path) -> Dict[str, Any]:
    """The decoded export, checked for version and shape."""
    try:
        data = json.loads(path.read_text())
    except (OSError, ValueError) as exc:
        raise GenError(f"{path}: cannot read the export ({exc}); run tools/test_ha/export_demo_house.sh") from exc
    if not isinstance(data, dict) or data.get("version") != EXPORT_VERSION:
        raise GenError(f"{path}: expected export version {EXPORT_VERSION}")
    if not isinstance(data.get("document"), dict) or not isinstance(data.get("entities"), list):
        raise GenError(f"{path}: missing document or entities")
    for entity in data["entities"]:
        if not isinstance(entity, dict) or not ENTITY_ID.match(str(entity.get("entity_id", ""))):
            raise GenError(f"{path}: entity id is not a demo id: {entity!r}"[:160])
    return data


def split_id(entity_id: str) -> Tuple[str, str]:
    """``light.demo_kitchen`` -> ``("light", "demo_kitchen")``."""
    domain, _, obj = entity_id.partition(".")
    return domain, obj


def title(obj: str) -> str:
    """``demo_bedroom_1_alarm_1`` -> ``Demo Bedroom 1 Alarm 1`` (its slug is the object id again)."""
    return " ".join(w[:1].upper() + w[1:] for w in obj.split("_"))


def slug(text: str) -> str:
    """Home Assistant's slugify for the ASCII names used here."""
    return re.sub(r"[^a-z0-9]+", "_", text.lower()).strip("_")


def bare_script_ids(document: Any) -> List[str]:
    """Every bare ``demo_*`` string in the document that names a script service (a ``call.service`` value or a script key)."""
    found: set = set()

    def walk(node: Any, key: str = "") -> None:
        if isinstance(node, str):
            if BARE_ID.match(node) and key not in NOT_A_SCRIPT_KEYS:
                found.add(node)
        elif isinstance(node, list):
            for item in node:
                walk(item, key)
        elif isinstance(node, dict):
            for k, v in node.items():
                walk(v, k)

    walk(document)
    return sorted(found)


# MARK: - YAML emission

def scalar(value: Any) -> str:
    """A YAML flow scalar (JSON is valid YAML, quotes included)."""
    return json.dumps(value, ensure_ascii=False)


def dump(node: Any, indent: int = 0) -> List[str]:
    """Block-style YAML lines for dicts, lists and scalars (an empty container stays inline)."""
    pad = "  " * indent
    lines: List[str] = []
    if isinstance(node, dict):
        if not node:
            return [pad + "{}"]
        for key, value in node.items():
            if isinstance(value, (dict, list)) and value:
                lines.append(f"{pad}{key}:")
                lines.extend(dump(value, indent + 1))
            else:
                lines.append(f"{pad}{key}: {scalar(value)}")
    elif isinstance(node, list):
        if not node:
            return [pad + "[]"]
        for item in node:
            if isinstance(item, (dict, list)) and item:
                sub = dump(item, indent + 1)
                lines.append(f"{pad}- {sub[0].lstrip()}")
                lines.extend(sub[1:])
            else:
                lines.append(f"{pad}- {scalar(item)}")
    else:
        lines.append(pad + scalar(node))
    return lines


# MARK: - Building the package

def resting(entity: Dict[str, Any]) -> Tuple[str, Dict[str, Any]]:
    """The resting state and the attributes worth keeping (``friendly_name`` is set from the id)."""
    attrs = {k: v for k, v in (entity.get("attributes") or {}).items() if k != "friendly_name"}
    return str(entity.get("state", "unknown")), attrs


def backing_id(domain: str, obj: str) -> str:
    """The helper entity id that stores a template entity's state (a name no document id can collide with)."""
    return f"{BACKED[domain]}.demo_state_{domain}_{obj[len('demo_'):]}"


def number_of(state: str, default: float = 0.0) -> float:
    try:
        return float(state)
    except ValueError:
        return default


#: The unit systems a package can be emitted in. The export's temperatures are Celsius (21 is a room at 21 degrees); the instance
#: follows the real house, so the default is imperial and they are written in degrees Fahrenheit (70).
UNIT_SYSTEMS = ("imperial", "metric")


def temperature(celsius: float, units: str = "imperial") -> int:
    """A demo temperature in the instance's unit system, as a whole number (21 C is 70 F)."""
    if units not in UNIT_SYSTEMS:
        raise GenError(f"units {units!r}: expected one of {', '.join(UNIT_SYSTEMS)}")
    return round(celsius * 9 / 5 + 32) if units == "imperial" else round(celsius)


class Package:
    """The generated entities, by source."""

    def __init__(self, export: Dict[str, Any], units: str = "imperial"):
        self.export = export
        self.units = units
        temperature(0, units)  # rejects an unknown unit system early
        self.entities = {e["entity_id"]: e for e in export["entities"]}
        self.helpers: Dict[str, Dict[str, Any]] = {d: {} for d in HELPER_DOMAINS}
        self.scripts: Dict[str, Any] = {}
        self.automations: List[Dict[str, Any]] = []
        self.persons: List[Dict[str, Any]] = []
        self.templates: List[Dict[str, Any]] = []
        self.extra: List[Dict[str, Any]] = []
        self.component: Dict[str, List[Dict[str, Any]]] = {d: [] for d in COMPONENT_DOMAINS}
        self.sources: Dict[str, str] = {}  # entity id -> helper | script | automation | person | template | extra | component

    # -- helpers
    def add_helper(self, domain: str, obj: str, entity: Dict[str, Any]) -> None:
        state, _ = resting(entity)
        name = title(obj)
        if domain == "input_boolean":
            self.helpers[domain][obj] = {"name": name, "initial": state == "on"}
        elif domain == "input_text":
            self.helpers[domain][obj] = {"name": name, "initial": "" if state in ("unknown", "unavailable") else state, "max": 255}
        elif domain == "input_number":
            self.helpers[domain][obj] = {"name": name, "min": 0, "max": 100, "step": 1, "mode": "box", "initial": number_of(state)}
        elif domain == "input_datetime":
            self.helpers[domain][obj] = {"name": name, "has_date": True, "has_time": True, "initial": FIXED_DATETIME}
        elif domain == "input_select":
            self.helpers[domain][obj] = {"name": name, "options": SELECT_OPTIONS, "initial": SELECT_OPTIONS[0]}
        elif domain == "input_button":
            self.helpers[domain][obj] = {"name": name}
        elif domain == "counter":
            self.helpers[domain][obj] = {"name": name, "initial": 0, "step": 1}
        elif domain == "timer":
            self.helpers[domain][obj] = {"name": name, "duration": "0:05:00"}
        elif domain == "schedule":
            self.helpers[domain][obj] = {"name": name}

    def add_backing(self, domain: str, obj: str, entity: Dict[str, Any]) -> str:
        """Create the backing helper of a template entity and return its entity id."""
        helper_id = backing_id(domain, obj)
        helper_domain, helper_obj = split_id(helper_id)
        state, _ = resting(entity)
        if helper_domain == "input_boolean":
            on = state in ("on", "open", "unlocked")
            self.helpers[helper_domain][helper_obj] = {"name": title(helper_obj), "initial": on}
        elif helper_domain == "input_number":
            self.helpers[helper_domain][helper_obj] = {"name": title(helper_obj), "min": 0, "max": 100, "step": 1,
                                                       "mode": "box", "initial": number_of(state)}
        else:
            self.helpers[helper_domain][helper_obj] = {"name": title(helper_obj), "options": SELECT_OPTIONS, "initial": SELECT_OPTIONS[0]}
        return helper_id

    # -- scripts, automations, persons
    def add_script(self, obj: str) -> None:
        self.scripts[obj] = {"alias": title(obj), "mode": "parallel",
                             "sequence": [{"event": "demo_script_called", "event_data": {"script": obj}}]}

    def add_automation(self, obj: str) -> None:
        alias = title(obj)
        if slug(alias) != obj:
            raise GenError(f"automation.{obj}: alias {alias!r} would not produce that entity id")
        self.automations.append({"id": obj, "alias": alias, "mode": "single",
                                 "triggers": [{"trigger": "event", "event_type": "demo_never_fires"}],
                                 "actions": [{"event": "demo_automation_ran", "event_data": {"automation": obj}}]})

    def add_person(self, obj: str) -> None:
        name = title(obj)
        if slug(name) != obj:
            raise GenError(f"person.{obj}: name {name!r} would not produce that entity id")
        self.persons.append({"name": name, "id": obj})

    # -- template entities
    def add_template(self, domain: str, obj: str, entity: Dict[str, Any], extra: bool = False) -> None:
        state, attrs = resting(entity)
        name = title(obj)
        if slug(name) != obj:
            raise GenError(f"{domain}.{obj}: name {name!r} would not produce that entity id")
        base: Dict[str, Any] = {"name": name, "unique_id": f"{domain}_{obj}", "default_entity_id": f"{domain}.{obj}"}
        noop = [{"event": f"demo_{domain}_action", "event_data": {"entity": f"{domain}.{obj}"}}]
        item: Dict[str, Any]
        if domain == "sensor":
            item = dict(base, state=state)
            if attrs:
                item["attributes"] = {k: v for k, v in attrs.items() if isinstance(v, (str, int, float, bool))}
        elif domain == "binary_sensor":
            item = dict(base, state="{{ true }}" if state == "on" else "{{ false }}")
        elif domain == "button":
            item = dict(base, press=noop)
        elif domain in BACKED:
            helper = self.add_backing(domain, obj, entity)
            item = self.backed_template(domain, base, helper)
        elif domain == "climate":
            item = dict(base, hvac_mode=state, current_temperature=str(temperature(number_of(str(attrs.get("current_temperature", 21)), 21), self.units)),
                        target_temperature=str(temperature(number_of(str(attrs.get("temperature", 21)), 21), self.units)),
                        hvac_modes=HVAC_MODES_TEMPLATE, set_hvac_mode=noop, set_temperature=noop)
        elif domain == "vacuum":
            item = dict(base, state=state, start=noop)
        elif domain == "alarm_control_panel":
            item = dict(base, state=state, arm_away=noop, arm_home=noop, disarm=noop)
        elif domain == "weather":
            item = dict(base, condition=state, temperature="{{ %d }}" % temperature(21, self.units), humidity="{{ 40 }}")
        else:
            raise GenError(f"no template for {domain}")
        (self.extra if extra else self.templates).append({domain: [item]})

    @staticmethod
    def backed_template(domain: str, base: Dict[str, Any], helper: str) -> Dict[str, Any]:
        on = f"is_state('{helper}', 'on')"
        turn_on = [{"action": "input_boolean.turn_on", "target": {"entity_id": helper}}]
        turn_off = [{"action": "input_boolean.turn_off", "target": {"entity_id": helper}}]
        if domain in ("switch", "light", "fan"):
            return dict(base, state="{{ " + on + " }}", turn_on=turn_on, turn_off=turn_off)
        if domain == "lock":
            return dict(base, state="{{ not " + on + " }}", lock=turn_off, unlock=turn_on)
        if domain == "cover":
            return dict(base, state="{{ 'open' if " + on + " else 'closed' }}", open_cover=turn_on, close_cover=turn_off)
        if domain == "number":
            return dict(base, state=f"{{{{ states('{helper}') | float(0) }}}}", min=0, max=100, step=1,
                        set_value=[{"action": "input_number" + ".set_value", "target": {"entity_id": helper},
                                    "data": {"value": "{{ value }}"}}])
        return dict(base, state=f"{{{{ states('{helper}') }}}}", options=SELECT_OPTIONS_TEMPLATE,
                    select_option=[{"action": "input_select" + ".select_option", "target": {"entity_id": helper},
                                    "data": {"option": "{{ option }}"}}])

    # -- component data
    def add_component(self, domain: str, obj: str, entity: Dict[str, Any]) -> None:
        state, attrs = resting(entity)
        self.component[domain].append({"object_id": obj, "name": title(obj), "state": state})


def build(export: Dict[str, Any], units: str = "imperial") -> Package:
    """Assign every id in the export to a source; raise for an id nothing can make. ``units`` is the instance's unit system."""
    pkg = Package(export, units)
    for entity_id in sorted(pkg.entities):
        domain, obj = split_id(entity_id)
        entity = pkg.entities[entity_id]
        if domain in HELPER_DOMAINS:
            pkg.add_helper(domain, obj, entity); source = "helper"
        elif domain == "script":
            pkg.add_script(obj); source = "script"
        elif domain == "automation":
            pkg.add_automation(obj); source = "automation"
        elif domain == "person":
            pkg.add_person(obj); source = "person"
        elif domain in TEMPLATE_DOMAINS:
            pkg.add_template(domain, obj, entity); source = "template"
        elif domain in EXTRA_TEMPLATE_DOMAINS:
            pkg.add_template(domain, obj, entity, extra=True); source = "extra"
        elif domain in COMPONENT_DOMAINS:
            pkg.add_component(domain, obj, entity); source = "component"
        else:
            raise GenError(f"{entity_id}: no source can make a {domain} entity; extend gen_demo_package.py")
        pkg.sources[entity_id] = source
    for obj in bare_script_ids(export["document"]):
        if obj not in pkg.scripts:
            pkg.add_script(obj)
    return pkg


def package_yaml(pkg: Package) -> str:
    """``packages/demo_house.yaml``."""
    root: Dict[str, Any] = {}
    for domain in HELPER_DOMAINS:
        if pkg.helpers[domain]:
            root[domain] = pkg.helpers[domain]
    root["script"] = pkg.scripts
    root["automation"] = pkg.automations
    root["person"] = pkg.persons
    root["template"] = pkg.templates
    return "# Generated by tools/test_ha/gen_demo_package.py from the DemoHouse export. Do not edit.\n" + "\n".join(dump(root)) + "\n"


def extra_yaml(pkg: Package) -> str:
    """``packages/demo_house_extra.yaml``."""
    return ("# Generated by tools/test_ha/gen_demo_package.py. Template keys here are confirmed by the step-6 spike.\n"
            + "\n".join(dump({"template": pkg.extra})) + "\n")


def house_json(export: Dict[str, Any]) -> str:
    """``fenton_home/house.json``: the document, compact, within the integration's size limit."""
    text = json.dumps(export["document"], separators=(",", ":"), sort_keys=True, ensure_ascii=False)
    if len(text.encode()) > HOUSE_BYTE_LIMIT:
        raise GenError(f"house.json is {len(text.encode())} bytes, over the {HOUSE_BYTE_LIMIT} limit")
    return text


def summary(pkg: Package) -> Dict[str, Any]:
    """Counts by source and domain, for the run output and the tests."""
    by_source: Dict[str, int] = {}
    for source in pkg.sources.values():
        by_source[source] = by_source.get(source, 0) + 1
    served: Dict[str, Dict[str, int]] = {}
    for entity_id, source in pkg.sources.items():
        domain = entity_id.split(".")[0]
        served.setdefault(source, {})[domain] = served.get(source, {}).get(domain, 0) + 1
    return {"total": len(pkg.sources), "by_source": by_source, "served_by": served,
            "backing_helpers": sum(1 for d in HELPER_DOMAINS for o in pkg.helpers[d] if o.startswith("demo_state_")),
            "scripts": len(pkg.scripts)}


def write_all(export: Dict[str, Any], out: Path, units: str = "imperial") -> Package:
    """Write every output file under ``out`` and return the package."""
    pkg = build(export, units)
    files = {
        "config/packages/demo_house.yaml": package_yaml(pkg),
        "config/packages/demo_house_extra.yaml": extra_yaml(pkg),
        "config/fenton_home/house.json": house_json(export),
        "config/custom_components/fenton_demo/demo_data.json": json.dumps(pkg.component, indent=1, sort_keys=True) + "\n",
    }
    for rel, text in files.items():
        target = out / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)
    return pkg


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--export", default=str(ROOT / "build/ha/demo-house.json"))
    ap.add_argument("--out", default=str(ROOT / "build/ha/test-instance"))
    ap.add_argument("--units", choices=UNIT_SYSTEMS, default="imperial",
                    help="the instance's unit system; temperatures are written in it (default imperial, like the real house)")
    args = ap.parse_args(argv)
    try:
        pkg = write_all(load_export(Path(args.export)), Path(args.out), args.units)
    except GenError as exc:
        print(f"gen_demo_package: {exc}", file=sys.stderr)
        return 1
    info = summary(pkg)
    print(json.dumps(info, sort_keys=True))
    for source, domains in sorted(info["served_by"].items()):
        print(f"served by {source}: " + ", ".join(f"{d} {n}" for d, n in sorted(domains.items())), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
