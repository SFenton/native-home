"""Demo remotes: on or off, commands are accepted and ignored, entity id ``remote.<object_id>``."""
from __future__ import annotations

from collections.abc import Iterable
from typing import Any

from homeassistant.components.remote import RemoteEntity
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntitiesCallback
from homeassistant.helpers.typing import ConfigType, DiscoveryInfoType


async def async_setup_platform(hass: HomeAssistant, config: ConfigType, async_add_entities: AddEntitiesCallback,
                               discovery_info: DiscoveryInfoType | None = None) -> None:
    """Add the demo remotes."""
    async_add_entities(DemoRemote(entry) for entry in (discovery_info or {}).get("entries", []))


class DemoRemote(RemoteEntity):
    """A remote that only remembers whether it is on."""

    _attr_should_poll = False

    def __init__(self, entry: dict[str, Any]) -> None:
        self.entity_id = f"remote.{entry['object_id']}"
        self._attr_unique_id = f"remote_{entry['object_id']}"
        self._attr_name = entry["name"]
        self._attr_is_on = entry.get("state") == "on"

    async def async_turn_on(self, **kwargs: Any) -> None:
        self._attr_is_on = True
        self.async_write_ha_state()

    async def async_turn_off(self, **kwargs: Any) -> None:
        self._attr_is_on = False
        self.async_write_ha_state()

    async def async_send_command(self, command: Iterable[str], **kwargs: Any) -> None:
        """Accept a command and do nothing (the test instance controls no device)."""
