"""Demo valves: open or closed, no position, entity id ``valve.<object_id>``."""
from __future__ import annotations

from typing import Any

from homeassistant.components.valve import ValveEntity, ValveEntityFeature
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntitiesCallback
from homeassistant.helpers.typing import ConfigType, DiscoveryInfoType


async def async_setup_platform(hass: HomeAssistant, config: ConfigType, async_add_entities: AddEntitiesCallback,
                               discovery_info: DiscoveryInfoType | None = None) -> None:
    """Add the demo valves."""
    async_add_entities(DemoValve(entry) for entry in (discovery_info or {}).get("entries", []))


class DemoValve(ValveEntity):
    """A valve that only remembers whether it is open."""

    _attr_should_poll = False
    _attr_reports_position = False
    _attr_supported_features = ValveEntityFeature.OPEN | ValveEntityFeature.CLOSE

    def __init__(self, entry: dict[str, Any]) -> None:
        self.entity_id = f"valve.{entry['object_id']}"
        self._attr_unique_id = f"valve_{entry['object_id']}"
        self._attr_name = entry["name"]
        self._attr_is_closed = entry.get("state") != "open"

    async def async_open_valve(self) -> None:
        self._attr_is_closed = False
        self.async_write_ha_state()

    async def async_close_valve(self) -> None:
        self._attr_is_closed = True
        self.async_write_ha_state()
