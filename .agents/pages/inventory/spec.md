# Food inventory pages spec (port of React `EverShelfInventoryPanel` x6 + `ScanItemCameraSheet`)

> **What:** platform-neutral spec for the six inventory pages, item editor and Add Item scan sheet. **Read when:** porting or changing them. iOS notes: [ios.md](ios.md).

Source: SFenton/ha-sfenton-react-dash @9ac2a46. `src/pages/DashboardViewPage.tsx` (EVERSHELF_INVENTORY_PAGES :1814-1821, EverShelfInventoryPage :7451-7455, route switch :7481, controls :7501), `src/components/hass/EverShelfInventoryPanel.tsx` (2054 lines), `src/components/hass/EverShelfInventoryControls.ts`, `src/components/hass/expiryDate.ts`, `src/components/hass/ScanItemCameraSheet.tsx` (1635 lines), `src/components/shell/DashboardFloatingAction.tsx` (:55-100), `src/constants/everShelfFood.ts`, `src/constants/routes.ts` (:17-22, :47-52, :167). Copy: `src/i18n/locales/en/pages/food.json` (delete.*, inventory.*).

## Pages
| Route | Title | Pantryhub location | Delete label | Scan default |
|---|---|---|---|---|
| `all-food` | All Food (mdi:food-variant) | `all` (no filter) | library | none (app default `dispensa`) |
| `pantry` | Pantry (mdi:food-fork-drink) | `dispensa` | pantry | `dispensa` |
| `fridge` | Fridge (mdi:fridge) | `frigo` | fridge | `frigo` |
| `freezer` | Freezer (mdi:snowflake) | `freezer` | freezer | `freezer` |
| `spice-rack` | Spice Rack (mdi:shaker-outline) | `spice_rack` | spice rack | `spice_rack` |
| `cabinet` | Cabinet (mdi:cupboard) | `cabinet` | cabinet | `cabinet` |
All six back-navigate to `food`. Reached from the Food & Recipes hub tiles (see recipes-spec). Hub tile subtitles use `sensor.demo_sensor_12|fridge|freezer`, `sensor.demo_kitchen_1|cabinet`, `sensor.demo_sensor_15`, `sensor.demo_sensor_11` (attr `expiring_list`).

## Inventory list (EverShelfInventoryPanel)
- Load: `evershelf.list_inventory` `{location?, q?}` with `return_response` (omit location for all). Search uses `q`; result trusted only if `source == "ha_sensor_product_search"` and `search == q`, else local token filter. Aggregated search rows (no `inventory_id`, has ids list) are expanded by a second unfiltered `list_inventory` call.
- Phases: "Loading {Title}" page loader, then content; search spinner overlay "Searching inventory" while debounce (250 ms) or request pending.
- Grouping: rows merged by lower-cased name; display quantity = sum; display expiry = soonest; batches split by (location, expiry date, prepared_food).
- Row: title, subtitle "Quantity {n}" (only when >1) · "Expires on MM/DD/YYYY" | "Expired on MM/DD/YYYY" | "No expiration date" | "Multiple Expiration Dates". Tone: expired (past), soon (<7 days), else normal. Expiry is computed on the **local** calendar (expiryDate.ts: Pantryhub UTC `days_remaining` rolls over early, so never trust it).
- Row actions: cart (mdi:cart-plus -> spinner -> check for 3 s): prompt "Quantity of {title} to add to the grocery cart." (default 1), then both `evershelf.add_to_shopping` `{name, quantity}` and `todo.add_item` on `todo.demo_todo_2` `{item: title}`. Single batch: pencil (Edit) + delete (mdi:delete). Multiple batches: whole row taps and a disclosure button opens the editor.
- Delete: qty 1 -> confirm "Delete {title} from the {location}?"; qty >1 -> prompt "Choose how many {title} to delete from the {location}." (error "Enter a number from 1 to {quantity}."); sequential `evershelf.delete_inventory` `{inventory_id, quantity?}` (smallest rows first); removed locally on success.
- Empty/error: "Unable to Load {Title}" ("Try again in a moment, or scan an item while {title} is unavailable."); "No Items Found" ("Scan an item to add it to your {title}."); "No Matching Items" (search: "Try a different search or clear the search to show all items." / with filter: "Try a different search, clear the selected filter, or clear the search to show all items."; filter only: "Try a different filter, or clear it to show all items.").

## Item editor (InventoryItemDetailsModal, form size, title = item name)
One card per batch: header "{title}" (or batch expiry label when several) + "In the {location}[ · Prepared]", delete button; Quantity stepper (min 1, max 999); Expiration Date picker (empty "No expiration date", must be YYYY-MM-DD or empty: "Use YYYY-MM-DD or clear the date."); checkbox "Prepared Food Item" ("Indicates this is a prepared food item and does not need classification."). When drafts differ: hint "Saving adds|removes {n} item(s) to/from the {location}." and Reset / Save.
- Save: decrease via `delete_inventory` steps; expiry change via `evershelf.update_inventory_item` `{inventory_id, expiry_date}` once per unit; increase via `evershelf.add_scanned_item` `{name, quantity: delta, inventory_prepared_food, vacuum_sealed, product_id?, location?, expiry_date?, unit?}`; then refresh `list_inventory`.
- Prepared toggle: prompt "How many of {title} to mark as prepared? (available: n)" when qty >1; `evershelf.set_inventory_prepared_food` `{inventory_id, prepared_food, quantity}` per row; optimistic projection reverted after 10 s, re-read retry 1 s; error "Unable to update prepared food". Sheet blocks dismissal while busy.

## FABs (inventory routes, after content loads)
Search pill ("Search items...", a11y "Search inventory"), Sort (mdi:swap-vertical), Filter (mdi:tune-vertical); blue (42,126,180), brown (155,110,64) when active; plus Scan Item (icon-only once items exist or search is active, else labeled "Scan Item"). Controls are kept per route.
- **Sort Inventory**: radio Title ("Sort alphabetically by item name.") / Expiration Date ("Sort by the item expiration date."); direction segmented Ascending (mdi:arrow-up, "Ascending (A-Z, soonest first)") / Descending. No-date items sort last. Apply / Reset.
- **Filter Inventory**: All Items, Expired, Expiring Within a Week (<=7), a Month (<=30), 6 Months (<=183), a Year (<=365), No Expiration Date; subtitles per FILTER_OPTIONS (:134-142).

## Scan Item sheet (ScanItemCameraSheet, title "Add Item", form size)
Also launched from Kitchen and Food hub FABs. Three steps with back buttons ("Back to barcode scan", "Back to expiration date"); subtitle "{Scan Barcode|Enter Product Name} · Step 1 of 3", "Expiration Date · Step 2 of 3", "Review Item · Step 3 of 3", then "Adding Item"/"Item Added".
1. **Barcode**: rear camera, continuous decode EAN-13, EAN-8, UPC-A, UPC-E, Code 128, Code 39, ITF. On hit -> `evershelf.resolve_barcode` `{barcode}` (return_response); found fills name/brand/prepared flag. Not found or skipped -> "What item are you adding?" text field. Buttons "Scan Barcode Again", "Skip Barcode"/"Next". Location suggestion runs in background: `evershelf.suggest_location` `{mode, name, product_fingerprint, product_id, barcode?, category?}`; product committed via `evershelf.prepare_scanned_product` (name, barcode, brand, category, image_url, unit, default_quantity, notes, package_unit, nutriments, prepared_food?, product_id?).
2. **Expiration**: camera crop of the visible frame as JPEG data URL -> `evershelf.read_expiry_image` `{image}`; found fills date (rate-limit error copy for AI 429). "Read Expiration Date (Again)", "Skip Expiration"/"Next". Manual "When does it expire?" date + Quick Expiration Dates radio: In 3 Days, In 1 Week, In 1 Month, In 6 Months, In 1 Year.
3. **Review**: name, "How many are you adding?" (>=1, "Quantity must be at least 1."), "Where should it be stored?" Pantry/Fridge/Freezer/Spice Rack/Cabinet/Library (`altro`) with hint (history / suggested / manual / fallback copy), date, Prepared Food checkbox. "Add" -> `evershelf.add_scanned_item` `{location, name, quantity, barcode?, brand?, category?, image_url?, default_quantity?, unit?, notes?, package_unit?, nutriments?, expiry_date + expiry_user_set: true?, prepared_food?, product_id?, idempotency_key}`. Progress "Adding to {Location}..." -> check "Added to {Location}" + "Done". Errors return to review.

## Native notes
- Reuse: modal-sheet pattern (`.large`; scan sheet uses its own NavigationStack for steps), ComponentGallery. Floating actions + FilterSheet + EverShelfService from recipes-spec (build once; whichever thread lands first owns them).
- New: `InventoryRow` (title, subtitle, tone, cart/edit/delete with spinner-check) and `QuantityStepper` -> HassDesign, pattern doc `inventory-row.md`. `ExpiryDate` helpers (HassCore, local-calendar, port tests). `InventoryListModel` (load/search/group/sort/filter), `InventoryItemEditor`, `InventoryScreen(location:)` (Features/Food). `ScanItemSheet` with VisionKit `DataScannerViewController` (barcodes, symbologies above) and a still capture for `read_expiry_image` (keep server OCR; optionally pre-fill with Vision text recognition) (Features/Food; camera permission string in Info.plist). Gallery pages: InventoryRow states, QuantityStepper, FilterSheet.
- Split view: single page on phones, Duo folded/unfolded portrait, iPad portrait. Unfolded landscape and iPad landscape: list primary, item editor in the secondary column (instead of a sheet); scan stays a sheet.
- Open questions: replace `window.prompt` quantity prompts with native alerts with text fields (assumed yes)? Should the list live-refresh on `sensor.demo_sensor_15` changes (web only reloads on actions/search)? Is "Library" (`altro`) still a valid scan destination with no page of its own?
