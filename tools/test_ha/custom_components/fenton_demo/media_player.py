"""Demo media players: power, volume and mute kept in memory, entity id ``media_player.<object_id>``.

The template integration has no media_player platform, so these come from this component.
"""
from __future__ import annotations

from typing import Any

from homeassistant.components.media_player import MediaPlayerEntity, MediaPlayerEntityFeature, MediaPlayerState
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntitiesCallback
from homeassistant.helpers.typing import ConfigType, DiscoveryInfoType


async def async_setup_platform(hass: HomeAssistant, config: ConfigType, async_add_entities: AddEntitiesCallback,
                               discovery_info: DiscoveryInfoType | None = None) -> None:
    """Add the demo media players."""
    async_add_entities(DemoMediaPlayer(entry) for entry in (discovery_info or {}).get("entries", []))


class DemoMediaPlayer(MediaPlayerEntity):
    """A media player that only remembers its power state, volume and mute."""

    _attr_should_poll = False
    _attr_supported_features = (MediaPlayerEntityFeature.TURN_ON | MediaPlayerEntityFeature.TURN_OFF
                                | MediaPlayerEntityFeature.VOLUME_SET | MediaPlayerEntityFeature.VOLUME_MUTE
                                | MediaPlayerEntityFeature.VOLUME_STEP)

    def __init__(self, entry: dict[str, Any]) -> None:
        self.entity_id = f"media_player.{entry['object_id']}"
        self._attr_unique_id = f"media_player_{entry['object_id']}"
        self._attr_name = entry["name"]
        self._attr_state = MediaPlayerState.ON if entry.get("state") == "on" else MediaPlayerState.OFF
        self._attr_volume_level = 0.3
        self._attr_is_volume_muted = False

    async def async_turn_on(self) -> None:
        self._attr_state = MediaPlayerState.ON
        self.async_write_ha_state()

    async def async_turn_off(self) -> None:
        self._attr_state = MediaPlayerState.OFF
        self.async_write_ha_state()

    async def async_set_volume_level(self, volume: float) -> None:
        self._attr_volume_level = volume
        self.async_write_ha_state()

    async def async_mute_volume(self, mute: bool) -> None:
        self._attr_is_volume_muted = mute
        self.async_write_ha_state()

    async def async_volume_up(self) -> None:
        await self.async_set_volume_level(min(1.0, (self._attr_volume_level or 0) + 0.1))

    async def async_volume_down(self) -> None:
        await self.async_set_volume_level(max(0.0, (self._attr_volume_level or 0) - 0.1))
