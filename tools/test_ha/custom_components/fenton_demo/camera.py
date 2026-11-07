"""Demo cameras: a fixed one-pixel image, entity id ``camera.<object_id>``."""
from __future__ import annotations

import base64
from typing import Any

from homeassistant.components.camera import Camera
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntitiesCallback
from homeassistant.helpers.typing import ConfigType, DiscoveryInfoType

#: A 1x1 grey PNG.
PIXEL = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGD4DwABBAEAHwCXMQAAAABJRU5ErkJggg==")


async def async_setup_platform(hass: HomeAssistant, config: ConfigType, async_add_entities: AddEntitiesCallback,
                               discovery_info: DiscoveryInfoType | None = None) -> None:
    """Add the demo cameras."""
    async_add_entities(DemoCamera(entry) for entry in (discovery_info or {}).get("entries", []))


class DemoCamera(Camera):
    """A camera that always returns the same still."""

    _attr_should_poll = False

    def __init__(self, entry: dict[str, Any]) -> None:
        super().__init__()
        self.entity_id = f"camera.{entry['object_id']}"
        self._attr_unique_id = f"camera_{entry['object_id']}"
        self._attr_name = entry["name"]
        self.content_type = "image/png"

    async def async_camera_image(self, width: int | None = None, height: int | None = None) -> bytes | None:
        return PIXEL
