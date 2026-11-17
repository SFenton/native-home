# Modals

> **What:** every modal mockup, by area, generated from [catalog.json](../catalog.json). **Read when:** you need to see how a modal looks today, or to find the mockup to update. Sheets, pushes inside sheets, covers and alerts. Sheets follow the system appearance unless always-dark.

## bedroom (8)

| Mockup | Id | Status | Surfaces | Relations |
|---|---|---|---|---|
| [Bed alarm day page (pushed)](bedroom/bed-alarm-day-page/bed-alarm-day-page.html) | `bed-alarm-day-page` | shipped | iphone, duo, ipad | from `bed-side-sheet` |
| [Bed alarm editor (pushed)](bedroom/bed-alarm-editor/bed-alarm-editor.html) | `bed-alarm-editor` | shipped | iphone, duo, ipad | from `bed-side-sheet`; opens `schedule-delete-dialog` |
| [Bed side sheet (Temperature, Special Modes, Alarms, Status)](bedroom/bed-side-sheet/bed-side-sheet.html) | `bed-side-sheet` | shipped | iphone, duo, ipad | from `room-master-bedroom`, `wake-light-sheet`; opens `bed-alarm-day-page`, `bed-alarm-editor`, `bed-temperature-scope-sheet`, `bed-power-off-dialog` |
| [Delete alarm or activity? (confirmation dialogs)](bedroom/schedule-delete-dialog/schedule-delete-dialog.html) | `schedule-delete-dialog` | shipped | iphone, duo, ipad | from `wake-light-editor`, `bed-alarm-editor`, `humidifier-activity-editor` |
| [Tonight or All Nights? (scope sheet)](bedroom/bed-temperature-scope-sheet/bed-temperature-scope-sheet.html) | `bed-temperature-scope-sheet` | shipped | iphone, duo, ipad | from `bed-side-sheet` |
| [Turn off bed side? (confirmation dialog)](bedroom/bed-power-off-dialog/bed-power-off-dialog.html) | `bed-power-off-dialog` | shipped | iphone, duo, ipad | from `bed-side-sheet` |
| [Wake alarm editor (pushed)](bedroom/wake-light-editor/wake-light-editor.html) | `wake-light-editor` | shipped | iphone, duo, ipad | from `wake-light-sheet`; opens `schedule-delete-dialog` |
| [Wake light sheet (Wake Alarms, Defaults)](bedroom/wake-light-sheet/wake-light-sheet.html) | `wake-light-sheet` | shipped | iphone, duo, ipad | from `room-master-bedroom`; opens `wake-light-editor`, `bed-side-sheet` |

## cameras (2)

| Mockup | Id | Status | Surfaces | Relations |
|---|---|---|---|---|
| [Allow Photos Access (alert)](cameras/camera-photos-denied-alert/camera-photos-denied-alert.html) | `camera-photos-denied-alert` | shipped | iphone, duo, ipad | from `camera-viewer` |
| [Camera viewer (live video, always dark)](cameras/camera-viewer/camera-viewer.html) | `camera-viewer` | shipped | iphone, duo, ipad | from `home`, `security`; opens `camera-photos-denied-alert` |

## chores (5)

| Mockup | Id | Status | Surfaces | Relations |
|---|---|---|---|---|
| [Add admin to-do sheet (with images)](chores/add-admin-todo-sheet/add-admin-todo-sheet.html) | `add-admin-todo-sheet` | shipped | iphone, duo, ipad | from `admin-todo` |
| [Add grocery item sheet](chores/add-grocery-item-sheet/add-grocery-item-sheet.html) | `add-grocery-item-sheet` | shipped | iphone, duo, ipad | from `groceries` |
| [Delete task? (confirmation dialog)](chores/todo-delete-dialog/todo-delete-dialog.html) | `todo-delete-dialog` | shipped | iphone, duo, ipad | from `chores`, `groceries`, `resident-chores`, `admin-todo`, `your-summary` |
| [Rename to-do item sheet](chores/rename-todo-item-sheet/rename-todo-item-sheet.html) | `rename-todo-item-sheet` | shipped | iphone, duo, ipad | from `admin-todo` |
| [Task sheet (create and edit)](chores/donetick-task-sheet/donetick-task-sheet.html) | `donetick-task-sheet` | shipped | iphone, duo, ipad | from `chores`, `resident-chores`, `unassigned-chores`, `home-improvement-chores`, `your-summary`; opens `todo-delete-dialog` |

## climate (3)

| Mockup | Id | Status | Surfaces | Relations |
|---|---|---|---|---|
| [Automation and Tracking detail pages (pushed)](climate/climate-automation-details/climate-automation-details.html) | `climate-automation-details` | shipped | iphone, duo, ipad | from `climate-sheet` |
| [Climate room detail (target dial, vents)](climate/climate-room-detail/climate-room-detail.html) | `climate-room-detail` | shipped | iphone, duo, ipad | from `climate-sheet` |
| [Thermostat advanced controls (Rooms, Automation, Tracking)](climate/climate-sheet/climate-sheet.html) | `climate-sheet` | shipped | iphone, duo, ipad | from `climate`; opens `climate-room-detail`, `climate-automation-details` |

## custom-lights (2)

| Mockup | Id | Status | Surfaces | Relations |
|---|---|---|---|---|
| [Custom light sheet (brightness, colour)](custom-lights/custom-light-sheet/custom-light-sheet.html) | `custom-light-sheet` | shipped | iphone, duo, ipad | from `custom-lights` |
| [Lighting Mode picker (option sheet)](custom-lights/lighting-mode-picker/lighting-mode-picker.html) | `lighting-mode-picker` | shipped | iphone, duo, ipad | from `custom-lights` |

## food (3)

| Mockup | Id | Status | Surfaces | Relations |
|---|---|---|---|---|
| [Filter Recipes (filter sheet)](food/recipe-filter-sheet/recipe-filter-sheet.html) | `recipe-filter-sheet` | shipped | iphone, duo, ipad | from `recipes` |
| [Recipe detail (General, Ingredients, Instructions)](food/recipe-detail-sheet/recipe-detail-sheet.html) | `recipe-detail-sheet` | shipped | iphone, duo, ipad | from `food-hub`, `recipes` |
| [Sort Recipes (filter sheet)](food/recipe-sort-sheet/recipe-sort-sheet.html) | `recipe-sort-sheet` | shipped | iphone, duo, ipad | from `recipes` |

## home (7)

| Mockup | Id | Status | Surfaces | Relations |
|---|---|---|---|---|
| [Air Quality overview](home/room-overview-air-quality/room-overview-air-quality.html) | `room-overview-air-quality` | shipped | iphone, duo, ipad | from `home` |
| [Climate overview](home/room-overview-climate/room-overview-climate.html) | `room-overview-climate` | shipped | iphone, duo, ipad | from `home`; opens `room-group-detail` |
| [Contact Sensors overview](home/room-overview-contacts/room-overview-contacts.html) | `room-overview-contacts` | shipped | iphone, duo, ipad | from `home`, `security`; opens `room-group-detail` |
| [Lights overview](home/room-overview-lights/room-overview-lights.html) | `room-overview-lights` | shipped | iphone, duo, ipad | from `home`; opens `room-group-detail` |
| [Occupancy overview](home/room-overview-occupancy/room-overview-occupancy.html) | `room-overview-occupancy` | shipped | iphone, duo, ipad | from `home`; opens `room-group-detail` |
| [Room group detail (pushed in an overview sheet)](home/room-group-detail/room-group-detail.html) | `room-group-detail` | shipped | iphone, duo, ipad | from `room-overview-lights`, `room-overview-climate`, `room-overview-occupancy`, `room-overview-contacts` |
| [Weather sheet (forecast, always dark)](home/weather-sheet/weather-sheet.html) | `weather-sheet` | shipped | iphone, duo, ipad | from `home`, `weather-summary-card` |

## inventory (6)

| Mockup | Id | Status | Surfaces | Relations |
|---|---|---|---|---|
| [Add Item scanner (barcode, expiry, review)](inventory/scan-item-sheet/scan-item-sheet.html) | `scan-item-sheet` | shipped | iphone, duo, ipad | from `inventory-space` |
| [Delete item from the space? (confirmation dialog)](inventory/inventory-delete-dialog/inventory-delete-dialog.html) | `inventory-delete-dialog` | shipped | iphone, duo, ipad | from `inventory-space` |
| [Filter Inventory (filter sheet)](inventory/inventory-filter-sheet/inventory-filter-sheet.html) | `inventory-filter-sheet` | shipped | iphone, duo, ipad | from `inventory-space` |
| [Item editor (batches, expiry, quantity)](inventory/inventory-item-editor/inventory-item-editor.html) | `inventory-item-editor` | shipped | iphone, duo, ipad | from `inventory-space`; opens `inventory-quantity-prompt` |
| [Quantity prompt (alert with text field)](inventory/inventory-quantity-prompt/inventory-quantity-prompt.html) | `inventory-quantity-prompt` | shipped | iphone, duo, ipad | from `inventory-space`, `inventory-item-editor` |
| [Sort Inventory (filter sheet)](inventory/inventory-sort-sheet/inventory-sort-sheet.html) | `inventory-sort-sheet` | shipped | iphone, duo, ipad | from `inventory-space` |

## location (1)

| Mockup | Id | Status | Surfaces | Relations |
|---|---|---|---|---|
| [Location permission (stages)](location/location-permission-sheet/location-permission-sheet.html) | `location-permission-sheet` | shipped | iphone, duo | from `your-summary`, `launch-cold-signed-in` |

## media (1)

| Mockup | Id | Status | Surfaces | Relations |
|---|---|---|---|---|
| [Media remote sheet (Controls, Apps, Devices, Hue Sync)](media/media-remote-sheet/media-remote-sheet.html) | `media-remote-sheet` | shipped | iphone, duo, ipad | from `media`, `room-page`, `room-master-bedroom` |

## room-devices (5)

| Mockup | Id | Status | Surfaces | Relations |
|---|---|---|---|---|
| [Air purifier sheet](room-devices/air-purifier-sheet/air-purifier-sheet.html) | `air-purifier-sheet` | shipped | iphone, duo, ipad | from `room-page`, `room-overview-air-quality` |
| [Bathroom fan sheet](room-devices/bathroom-fan-sheet/bathroom-fan-sheet.html) | `bathroom-fan-sheet` | shipped | iphone, duo, ipad | from `room-page` |
| [Grill (Grill Probe) sheet](room-devices/grill-sheet/grill-sheet.html) | `grill-sheet` | shipped | iphone, duo, ipad | from `room-page` |
| [Humidifier activity editor (pushed)](room-devices/humidifier-activity-editor/humidifier-activity-editor.html) | `humidifier-activity-editor` | shipped | iphone, duo, ipad | from `humidifier-sheet` |
| [Humidifier sheet (Controls, Schedules, Info)](room-devices/humidifier-sheet/humidifier-sheet.html) | `humidifier-sheet` | shipped | iphone, duo, ipad | from `room-page`, `room-master-bedroom`; opens `humidifier-activity-editor`, `schedule-delete-dialog` |

## rooms (1)

| Mockup | Id | Status | Surfaces | Relations |
|---|---|---|---|---|
| [Room card sheet (groups, items, fallbacks)](rooms/room-card-sheet/room-card-sheet.html) | `room-card-sheet` | shipped | iphone, duo, ipad | from `room-page`, `room-kitchen` |

## security (2)

| Mockup | Id | Status | Surfaces | Relations |
|---|---|---|---|---|
| [Disarm the Security System? (alert)](security/disarm-confirm-alert/disarm-confirm-alert.html) | `disarm-confirm-alert` | shipped | iphone, duo, ipad | from `security`, `security-system-sheet` |
| [Security System sheet (alarm card)](security/security-system-sheet/security-system-sheet.html) | `security-system-sheet` | shipped | iphone, duo, ipad | from `security`, `home`, `quick-links-security-system`; opens `disarm-confirm-alert` |

## settings (9)

| Mockup | Id | Status | Surfaces | Relations |
|---|---|---|---|---|
| [App Icon picker](settings/app-icon-picker-sheet/app-icon-picker-sheet.html) | `app-icon-picker-sheet` | shipped | iphone, duo, ipad | from `settings` |
| [Auto-Reset sheet (morning re-enable per room)](settings/auto-reset-sheet/auto-reset-sheet.html) | `auto-reset-sheet` | shipped | iphone, duo, ipad | from `household-admin` |
| [Discard feedback? (confirmation dialog)](settings/feedback-discard-dialog/feedback-discard-dialog.html) | `feedback-discard-dialog` | shipped | iphone, duo, ipad | from `feedback-form-sheet` |
| [Feedback form (Report an Issue, Request a Feature)](settings/feedback-form-sheet/feedback-form-sheet.html) | `feedback-form-sheet` | shipped | iphone, duo, ipad | from `settings`; opens `feedback-discard-dialog`, `feedback-result-alerts` |
| [Feedback result alerts (filed, couldn't send)](settings/feedback-result-alerts/feedback-result-alerts.html) | `feedback-result-alerts` | shipped | iphone, duo, ipad | from `feedback-form-sheet` |
| [Home Assistant settings (full-screen cover)](settings/ha-settings/ha-settings.html) | `ha-settings` | shipped | iphone, duo, ipad | from `settings`; opens `ha-sign-out-dialog`, `ha-web-page` |
| [Presence-Based Overrides sheet (room grid)](settings/presence-overrides-sheet/presence-overrides-sheet.html) | `presence-overrides-sheet` | shipped | iphone, duo, ipad | from `household-admin`; opens `presence-override-detail` |
| [Room presence override detail (four modes)](settings/presence-override-detail/presence-override-detail.html) | `presence-override-detail` | shipped | iphone, duo, ipad | from `presence-overrides-sheet` |
| [Sign out of Home Assistant? (confirmation dialog)](settings/ha-sign-out-dialog/ha-sign-out-dialog.html) | `ha-sign-out-dialog` | shipped | iphone, duo, ipad | from `ha-settings` |

## shell (6)

| Mockup | Id | Status | Surfaces | Relations |
|---|---|---|---|---|
| [Quick Links sheet](shell/quick-links/quick-links.html) | `quick-links` | shipped | iphone, duo, ipad | from `shell-header-items`; opens `quick-links-rooms`, `quick-links-security-system` |
| [Quick Links: Rooms grid](shell/quick-links-rooms/quick-links-rooms.html) | `quick-links-rooms` | shipped | iphone, duo, ipad | from `quick-links` |
| [Quick Links: Security System detail](shell/quick-links-security-system/quick-links-security-system.html) | `quick-links-security-system` | shipped | iphone, duo, ipad | from `quick-links` |
| [Sign Out couldn't complete (alert)](shell/sign-out-failed-alert/sign-out-failed-alert.html) | `sign-out-failed-alert` | shipped | iphone, duo, ipad | from `your-summary`, `ha-settings` |
| [Sign Out of Home Assistant? (alert)](shell/sign-out-alert/sign-out-alert.html) | `sign-out-alert` | shipped | iphone, duo, ipad | from `your-summary` |
| [Your Summary (Account sheet, four tabs)](shell/your-summary/your-summary.html) | `your-summary` | shipped | iphone, duo, ipad | from `shell-header-items`; opens `sign-out-alert`, `sign-out-failed-alert`, `location-permission-sheet`, `donetick-task-sheet`, `todo-delete-dialog` |

## sprinklers (3)

| Mockup | Id | Status | Surfaces | Relations |
|---|---|---|---|---|
| [Sprinkler controller sheet](sprinklers/sprinkler-controller-sheet/sprinkler-controller-sheet.html) | `sprinkler-controller-sheet` | shipped | iphone, duo, ipad | from `sprinklers`; opens `sprinkler-water-page`, `sprinkler-schedule-page` |
| [Water a zone now (pushed)](sprinklers/sprinkler-water-page/sprinkler-water-page.html) | `sprinkler-water-page` | shipped | iphone, duo, ipad | from `sprinkler-controller-sheet` |
| [Zone program schedule editor (pushed)](sprinklers/sprinkler-schedule-page/sprinkler-schedule-page.html) | `sprinkler-schedule-page` | shipped | iphone, duo, ipad | from `sprinkler-controller-sheet` |

## vacation (3)

| Mockup | Id | Status | Surfaces | Relations |
|---|---|---|---|---|
| [Solo Trip schedule editor sheet](vacation/solo-trip-editor-sheet/solo-trip-editor-sheet.html) | `solo-trip-editor-sheet` | shipped | iphone, duo, ipad | from `solo-trip` |
| [Turn Off Vacation Mode? (alert)](vacation/vacation-disable-alert/vacation-disable-alert.html) | `vacation-disable-alert` | shipped | iphone, duo, ipad | from `vacation-mode` |
| [Vacation dates (confirmation sheet)](vacation/vacation-confirmation-sheet/vacation-confirmation-sheet.html) | `vacation-confirmation-sheet` | shipped | iphone, duo, ipad | from `vacation-mode` |

## vacuums (4)

| Mockup | Id | Status | Surfaces | Relations |
|---|---|---|---|---|
| [Cleaning outcome report (pushed)](vacuums/vacuum-outcome-report/vacuum-outcome-report.html) | `vacuum-outcome-report` | shipped | iphone, duo, ipad | from `vacuum-sheet` |
| [Use Area / Use Rooms (confirmation)](vacuums/vacuum-switch-dialog/vacuum-switch-dialog.html) | `vacuum-switch-dialog` | shipped | iphone, duo, ipad | from `vacuum-sheet` |
| [Vacuum area editor (pushed)](vacuums/vacuum-area-editor/vacuum-area-editor.html) | `vacuum-area-editor` | shipped | iphone, duo, ipad | from `vacuum-sheet` |
| [Vacuum sheet (Controls, Rooms, Auto-Clean, Dock, Info)](vacuums/vacuum-sheet/vacuum-sheet.html) | `vacuum-sheet` | shipped | iphone, duo, ipad | from `vacuums`, `room-page`; opens `vacuum-area-editor`, `vacuum-outcome-report`, `vacuum-switch-dialog` |

Open any file in a browser (`python3 -m http.server --directory .agents/design/mockups`). How to author or update one: [_kit/AUTHORING.md](../_kit/AUTHORING.md).
