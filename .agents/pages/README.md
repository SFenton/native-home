# Pages

> **What:** one folder per web route with a platform-neutral spec and per-platform notes. **Read when:** porting or changing a page.

Full screen map: the coordinator's private dashboard inventory (link kept outside the repo).

| Page | Web route | Spec | Native status |
|---|---|---|---|
| Home | `/at-a-glance/overview` | [home/spec.md](home/spec.md) | Scaffolded ([ios.md](home/ios.md)) |
| Security | `/at-a-glance/security` | [security/spec.md](security/spec.md) | Ported ([ios.md](security/ios.md)) |
| Climate | `/at-a-glance/thermostat` | [climate/spec.md](climate/spec.md) | Ported ([ios.md](climate/ios.md)) |
| Chores (+ Groceries, residents' chores, To-Do) | `/at-a-glance/chores` | [chores/spec.md](chores/spec.md) | Ported ([ios.md](chores/ios.md)) |
| Media | `/at-a-glance/media` | [media/spec.md](media/spec.md) | Ported ([ios.md](media/ios.md)) |
| Custom Lights | `/at-a-glance/custom-lights` | [custom-lights/spec.md](custom-lights/spec.md) | Ported ([ios.md](custom-lights/ios.md)) |
| Sprinklers | `/at-a-glance/sprinklers` | [sprinklers/spec.md](sprinklers/spec.md) | Ported ([ios.md](sprinklers/ios.md)) |
| Settings | `/at-a-glance/settings` | `plans/settings-household-spec.md` | Home Assistant settings modal ([ios.md](settings/ios.md)); Vacation; Admin, Special Device Modes, Guest Controls, car ([household.md](settings/household.md)) |
| Inventory (All Food, Pantry, Fridge, Freezer, Spice Rack, Cabinet) | `/food-and-recipes/<space>` | [inventory/spec.md](inventory/spec.md) | Pages, item editor and Add Item ([ios.md](inventory/ios.md)); reached from the Food & Recipes hub once it lands |
| Vacuums | `/vacuums` | [vacuums/spec.md](vacuums/spec.md) | Page, sheet and map ([ios.md](vacuums/ios.md)) |
| Food & Recipes | `/food`, `/food/recipes` | [food/spec.md](food/spec.md) | Hub, Recipes grid, recipe detail ([ios.md](food/ios.md)) |
| Rooms (16) | `/<room>` | [rooms/spec.md](rooms/spec.md) | Config-driven pages, Quick Links, room grid ([ios.md](rooms/ios.md)); room device sheets and the vacuum sheet wired in |
| Your Summary (the header Profile button) | `#daily-report` | [settings/profile.md](settings/profile.md) | Four tabs: Profile, Overdue Chores, Upcoming Chores, Expired Food |
| Vacation, Vacation Mode, Solo Trip | `vacation`, `vacation-mode`, `solo-trip` | [vacation/spec.md](vacation/spec.md) | Ported ([ios.md](vacation/ios.md)) |
