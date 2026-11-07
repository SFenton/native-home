"""Demo todo lists: in-memory, one per generated entry, entity id ``todo.<object_id>``."""
from __future__ import annotations

from typing import Any

from homeassistant.components.todo import TodoItem, TodoItemStatus, TodoListEntity, TodoListEntityFeature
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntitiesCallback
from homeassistant.helpers.typing import ConfigType, DiscoveryInfoType


async def async_setup_platform(hass: HomeAssistant, config: ConfigType, async_add_entities: AddEntitiesCallback,
                               discovery_info: DiscoveryInfoType | None = None) -> None:
    """Add the demo lists."""
    async_add_entities(DemoTodo(entry) for entry in (discovery_info or {}).get("entries", []))


class DemoTodo(TodoListEntity):
    """A todo list that keeps its items in memory."""

    _attr_should_poll = False
    _attr_supported_features = (TodoListEntityFeature.CREATE_TODO_ITEM | TodoListEntityFeature.UPDATE_TODO_ITEM
                                | TodoListEntityFeature.DELETE_TODO_ITEM)

    def __init__(self, entry: dict[str, Any]) -> None:
        self.entity_id = f"todo.{entry['object_id']}"
        self._attr_unique_id = f"todo_{entry['object_id']}"
        self._attr_name = entry["name"]
        self._items: list[TodoItem] = []

    @property
    def todo_items(self) -> list[TodoItem]:
        return self._items

    async def async_create_todo_item(self, item: TodoItem) -> None:
        self._items.append(TodoItem(summary=item.summary, uid=str(len(self._items) + 1), status=TodoItemStatus.NEEDS_ACTION))
        self.async_write_ha_state()

    async def async_update_todo_item(self, item: TodoItem) -> None:
        self._items = [item if existing.uid == item.uid else existing for existing in self._items]
        self.async_write_ha_state()

    async def async_delete_todo_items(self, uids: list[str]) -> None:
        self._items = [existing for existing in self._items if existing.uid not in uids]
        self.async_write_ha_state()
