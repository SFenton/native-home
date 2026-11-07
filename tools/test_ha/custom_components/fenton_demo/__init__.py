"""Test-only demo entities for the S+H test Home Assistant instance (todo, valve, camera, remote, media_player, sun).

Stock Home Assistant has no YAML source for these domains, so this component creates them from
``demo_data.json`` (written by ``tools/test_ha/gen_demo_package.py`` from the DemoHouse export). It holds no credentials and
talks to nothing. Enable it with a bare ``fenton_demo:`` line in ``configuration.yaml``.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import homeassistant.helpers.config_validation as cv
from homeassistant.core import HomeAssistant
from homeassistant.helpers.discovery import async_load_platform
from homeassistant.helpers.typing import ConfigType

DOMAIN = "fenton_demo"
PLATFORMS = ("todo", "valve", "camera", "remote", "media_player")
# ``sun`` has no entity platform: the built-in ``sun.sun`` keeps its own id, so the demo id is a plain state (below).
STATE_DOMAINS = ("sun",)
CONFIG_SCHEMA = cv.empty_config_schema(DOMAIN)


def load_data(path: Path) -> dict[str, list[dict[str, Any]]]:
    """The generated ``{platform: [{object_id, name, state}]}`` file (an empty set when it is missing)."""
    try:
        data = json.loads(path.read_text())
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


async def async_setup(hass: HomeAssistant, config: ConfigType) -> bool:
    """Load one platform per domain that has entries, and write the state-only domains (``sun``) directly."""
    path = Path(__file__).parent / "demo_data.json"
    data = await hass.async_add_executor_job(load_data, path)
    for platform in PLATFORMS:
        entries = data.get(platform) or []
        if entries:
            hass.async_create_task(async_load_platform(hass, platform, DOMAIN, {"entries": entries}, config))
    for domain in STATE_DOMAINS:
        for entry in data.get(domain) or []:
            hass.states.async_set(f"{domain}.{entry['object_id']}", entry.get("state") or "above_horizon",
                                  {"friendly_name": entry["name"]})
    return True
