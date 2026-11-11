# Patterns

> **What:** cross-screen behaviors with one canonical component each. **Read when:** touching any shared behavior.

**The registry is the index.** [`contracts/patterns.json`](../../contracts/patterns.json) holds one record per pattern (canonical components, owned files, keywords, related patterns, status, regex guards) and [`contracts/components.json`](../../contracts/components.json) maps every shared view and modifier to its pattern, tests and system-API note. Ask it, do not scan this table: `python3 tools/pattern_guard.py which <path>…` (who owns a file), `index` (the compact index), `changed --base origin/main` (patterns your diff touches, and whether their docs moved) and no argument (validate the registry and run the guards, which `pr-checks` runs, with `components_index.py --check` and `jev_ask.py sync --check`). A new pattern needs its doc here, a record in the registry and a row below.

| Pattern | Canonical component | Web source |
|---|---|---|
| [dynamic-grid.md](dynamic-grid.md) | `HassDesign/DynamicGridLayout.swift` | `src/components/core/DynamicGrid.tsx` |
| [hinge-avoidance.md](hinge-avoidance.md) | `HassDesign/HingeAvoidance.swift`, `HassUI/App/Layout/HingedPanes.swift` | none (iPhone Duo and iPad) |
| [action-tiles.md](action-tiles.md) | `HassDesign/TileActions/` | none (native convention, owner 2026-10-26) |
| [entity-tile.md](entity-tile.md) | `HassDesign/GlassTile.swift` | `src/components/core/GlassTile.tsx` |
| [list-row-removal.md](list-row-removal.md) | `UIKitPort/Design/UKListUpdater.swift`; rules in `HassDesign/Motion/ListUpdateTransition.swift` | none (native) |
| [module-list.md](module-list.md) | `HassDesign/ModuleList.swift` | none (direction G inset list) |
| [check-row.md](check-row.md) | `HassDesign/CheckRow.swift` (UIKit `UKCheckRow`) | `CheckboxRow` in `src/components/hass/` (chores, vacation) |
| [swipe-row.md](swipe-row.md) | `HassDesign/Swipe/SwipeActionRow.swift` | none (custom swipe row on a plain stack, iOS 18+; the List's swipe actions on iOS 17) |
| [scroll-frame-rate.md](scroll-frame-rate.md) | `HassDesign/ReportsScrollActivity.swift` | none (no app refresh-rate request while scrolling; scroll surfaces report to ScrollActivity) |
| [status-rail.md](status-rail.md) | `HassUI/Features/Home/StatusRail.swift` | `src/components/hass/StatusRail.tsx` |
| [room-overview-sheet.md](room-overview-sheet.md) | `HassUI/Common/RoomOverview/RoomOverviewSheet.swift` | `src/pages/AtAGlancePage.tsx` (`LightsSheet`, `OccupancySheet`, `ContactSheet`, …) |
| [modal-sheet.md](modal-sheet.md) | `HassDesign/HassModal.swift` (`HassModal`, `SheetCloseItem`, `hassSheet()`), `HassUI/Common/ModalTabBar.swift` | `src/components/core/ModalSheet.tsx`, `ModalTabNav.tsx` |
| [scroll-fit.md](scroll-fit.md) | `HassDesign/ScrollFit.swift` (`scrollsOnlyWhenNeeded()`, `pullToRefresh`) | none (native scroll behavior) |
| [modal-inventory.md](modal-inventory.md) | `UIKitPort/App/Page/UKShellSheet.swift` (UIKit port) | none |
| [rows.md](rows.md) | `UIKitPort/Design/UKRow.swift` (`UKRowView`, UIKit port) | none |
| [page-base.md](page-base.md) | `UIKitPort/App/Page/UKPageBody.swift`, `UKPageViewController` (UIKit port) | none yet |
| [header-edge-fade.md](header-edge-fade.md) (pages and modals use the system soft scroll-edge effect, `headerSoftEdge()`; mask fallback before iOS 26, R10) | `HassDesign/HeaderEdgeFade.swift` | `src/hooks/ui/useScrollMask.ts` (FestivalNativeApps `ModalTopEdgeFade`) |
| [page-backdrop.md](page-backdrop.md) | `HassUI/Common/HouseBackdrop.swift` | `src/components/shell/AppShell.module.css` `.backdrop` |
| [media-remote.md](media-remote.md) | `HassUI/Features/MediaRemote/MediaRemoteSheet.swift` | `src/components/hass/MediaRemoteModalContent.tsx` |
| [floating-actions.md](floating-actions.md) | `HassDesign/FloatingActionBar.swift`, `HassDesign/FilterSheet.swift` | `src/components/core/FloatingActionButton.tsx`, `src/components/shell/DashboardFloatingAction.tsx` |
| [image-card.md](image-card.md) | `HassDesign/ImageCard.swift` | `src/components/hass/recipes/RecipeCard.tsx` |
| [vacuum-sheet.md](vacuum-sheet.md) | `HassUI/Features/Vacuums/VacuumSheet.swift` | `src/components/hass/VacuumCard.tsx` |
| [valetudo-map.md](valetudo-map.md) | `HassUI/Features/Vacuums/ValetudoMapView.swift` | `src/components/hass/ValetudoMapCard.tsx` |
| [thermostat-dial.md](thermostat-dial.md) | `HassDesign/ThermostatDial/ThermostatDial.swift` | `src/components/hass/CircularControlDial.tsx` |
| [schedule-date-fields.md](schedule-date-fields.md) | `HassDesign/ScheduleDateFields.swift` | `NativePickerField` in `ScheduleConfirmationForm` |
| [alerts.md](alerts.md) | `HassUI/Common/AlertCopy.swift` | none (native only) |
| [state-message.md](state-message.md) | `HassDesign/StateMessage.swift` | `EmptyState` |
| [info-box.md](info-box.md) | `HassDesign/InfoBox.swift` | `src/components/core/InfoBox.tsx` |
| [page-indicator.md](page-indicator.md) | `HassDesign/PageIndicator.swift` | none (native only; web carousel dots) |
| [status-pill.md](status-pill.md) | `HassDesign/StatusPill.swift` | `src/components/core/StatusPill.tsx` |
| [option-picker.md](option-picker.md) | `HassDesign/OptionPickerSheet.swift` | `src/components/core/OptionPickerDialog.tsx` |
| [bedroom-devices.md](bedroom-devices.md) | `HassUI/Features/Bedroom/BedSideSheet.swift`, `WakeLightSheet.swift` and the tab, editor and tile files beside them | `src/components/hass/wakeLights/`, Bed in `DashboardViewPage.tsx` |
| [room-device-sheets.md](room-device-sheets.md) | `HassUI/Features/RoomDevices/` | `src/components/hass/*ModalContent.tsx` (fan, purifier, humidifier, grill) |
| [settings-section.md](settings-section.md) | `HassDesign/SettingsSection.swift` | `src/components/core/SettingsSection.tsx` |
| [optimistic-actions.md](optimistic-actions.md) | `HassCore/Optimism/OptimisticActions.swift` | `src/hooks/useOptimisticState.ts`, `src/components/hass/optimisticActionState.ts` |
| [tap-feedback.md](tap-feedback.md) | `HassDesign/TapFeedback.swift`, `HassDesign/TransientFailure.swift` | none (native only) |
| [content-gate.md](content-gate.md) | `HassDesign/Loading/ContentGate.swift` | `src/components/hass/recipes/useRecipeCollection.ts` (criteria phases) |
| [image-cache.md](image-cache.md) | `HassDesign/Images/ImagePipeline.swift`, `CachedImage.swift` | browser HTTP cache (`decoding="async"` images) |
| [avatar.md](avatar.md) | `HassDesign/Avatar/AvatarView.swift`; sync in `HassCore/Profile/PersonAvatars.swift` | none (native only; Home Assistant `person.*` `entity_picture`) |
| [telemetry.md](telemetry.md) | `HassTelemetry/`, `HassUI/Diagnostics/` | none (native only) |
| [weather.md](weather.md) | `HassUI/Features/Home/Weather/WeatherSummaryCard.swift`, `WeatherSheet.swift`, `WeatherPagedCarousel.swift`; logic in `HassCore/Weather` | `src/components/hass/WeatherSummary.tsx`, `useWeatherForecasts.ts`, `weatherPresentation.ts`, `weatherDayBriefing.ts` |
| [camera-streams.md](camera-streams.md) | `HassUI/Features/Cameras/CameraStreamPool.swift`, `CameraLiveModel.swift`; logic in `HassCore/Cameras/CameraStream.swift` | `SFenton/WebRTC` `www/stream-manager.js`, `rtcStreamRetention.ts` |
| [resume-lifecycle.md](resume-lifecycle.md) | `HassTelemetry/ResourceCensus.swift`, `HassUI/Diagnostics/ResourceCensusProbe.swift`, `HassDesign/NativePaging.swift` | none (native only) |
| [motion.md](motion.md) | `HassDesign/Motion/MotionTokens.swift` | none (native; rules in `design/motion.md`) |
| [ticker.md](ticker.md) | `HassDesign/TickerLabel.swift` | none (native only) |
| [design-tokens.md](design-tokens.md) | `HassDesign/HassTokens.swift` | `src/styles/tokens.css` |

## Reuse rules

Standing rules from the 2026-10-13 duplication audit (evidence: [archive/audit](../archive/audit/README.md)).

- Before writing a helper, grep `HassCore/Entities`, `HassCore/Connection` and `HassDesign` for it. Feature folders hold feature logic only; infrastructure types live in those three places.
- A second copy of anything a pattern record already covers is a major review finding. Extend the shared one instead.
- Every file in `HassUI/Features/Gallery` is wrapped in `#if DEBUG`. Production code reaches the galleries only through `ComponentGallery.requested` and `galleryLastCallBanner()`, which is a no-op in Release.
- Journeys subclass `JourneyTestCase` ([devices](../testing/apple/devices.md)).
- Warnings and errors use `InlineAlert`; Form section headers and footers use `FormHeader`/`FormFooter` (the system secondary label is about 3.3:1 on the sheet background).
