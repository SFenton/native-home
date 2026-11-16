# Patterns

> **What:** cross-screen behaviors with one canonical component each. **Read when:** touching any shared behavior.

**The registry is the index.** [`contracts/patterns.json`](../../contracts/patterns.json) holds one record per pattern (canonical components, owned files, keywords, related patterns, status, regex guards) and [`contracts/components.json`](../../contracts/components.json) maps every shared view and modifier to its pattern, tests and system-API note. Ask it, do not scan this table: `python3 tools/pattern_guard.py which <path>…` (who owns a file), `index` (the compact index), `changed --base origin/main` (patterns your diff touches, and whether their docs moved) and no argument (validate the registry and run the guards, which `pr-checks` runs, with `components_index.py --check` and `jev_ask.py sync --check`). A new pattern needs its doc here, a record in the registry and a row below.

| Pattern | Canonical component | Web source |
|---|---|---|
| [dynamic-grid.md](dynamic-grid.md) | `HassDesign/DynamicGridLayout.swift` | `src/components/core/DynamicGrid.tsx` |
| [hinge-avoidance.md](hinge-avoidance.md) | `HassDesign/HingeAvoidance.swift`, `HassUI/UIKitPort/Design/UKFoldColumns.swift`, `HassUI/App/Layout/FoldColumns.swift` | none (iPhone Duo and iPad) |
| [action-tiles.md](action-tiles.md) | `HassDesign/TileActions/TileActionStrip.swift`, `HassDesign/TileActions/TileActionButtonStyle.swift`, `HassCore/TileActions/TileActionSpec.swift` | none (native convention) |
| [entity-tile.md](entity-tile.md) | `HassUI/UIKitPort/Design/UKGlassTileView.swift` | `src/components/core/GlassTile.tsx` |
| [module-list.md](module-list.md) | `HassUI/UIKitPort/Design/UKModule.swift` | none (direction G inset list) |
| [check-row.md](check-row.md) | `HassDesign/CheckRow.swift` | `CheckboxRow` in `src/components/hass/` (chores, vacation) |
| [swipe-row.md](swipe-row.md) | `HassUI/UIKitPort/Design/UKSwipeActions.swift` | none (custom swipe row on a plain stack, iOS 18+; the List's swipe actions on iOS 17) |
| [scroll-frame-rate.md](scroll-frame-rate.md) | `HassUI/UIKitPort/Foundation/UKScrollRate.swift` | none (no app refresh-rate request while scrolling; scroll surfaces report to ScrollActivity) |
| [status-rail.md](status-rail.md) | `HassUI/UIKitPort/Design/UKLayoutViews.swift` | `src/components/hass/StatusRail.tsx` |
| [room-overview-sheet.md](room-overview-sheet.md) | `HassUI/Common/RoomOverview/RoomOverviewStyle.swift` | `src/pages/AtAGlancePage.tsx` (`LightsSheet`, `OccupancySheet`, `ContactSheet`, …) |
| [modal-sheet.md](modal-sheet.md) | `HassUI/UIKitPort/Design/UKHassModal.swift`, `HassUI/Common/ModalTabBar.swift` | `src/components/core/ModalSheet.tsx`, `ModalTabNav.tsx` |
| [scroll-fit.md](scroll-fit.md) | `HassUI/UIKitPort/App/Page/UKScrollFit.swift` | none (native scroll behavior) |
| [modal-inventory.md](modal-inventory.md) | `HassUI/UIKitPort/App/Page/UKShellSheet.swift` | none |
| [rows.md](rows.md) | `HassUI/UIKitPort/Design/UKRow.swift` | none |
| [page-base.md](page-base.md) | `HassUI/UIKitPort/App/Page/UKPageBody.swift`, `HassUI/UIKitPort/App/Page/UKPageViewController.swift` | none yet |
| [header-edge-fade.md](header-edge-fade.md) (pages and modals use the system soft scroll-edge effect, `headerSoftEdge()`; mask fallback before iOS 26, R10) | `HassDesign/HeaderEdgeFade.swift` | `src/hooks/ui/useScrollMask.ts` (FestivalNativeApps `ModalTopEdgeFade`) |
| [page-backdrop.md](page-backdrop.md) | `HassUI/Common/HouseBackdrop.swift` | `src/components/shell/AppShell.module.css` `.backdrop` |
| [media-remote.md](media-remote.md) | `HassUI/Features/MediaRemote/MediaRemoteControls.swift` | `src/components/hass/MediaRemoteModalContent.tsx` |
| [floating-actions.md](floating-actions.md) | `HassDesign/FloatingActionBar.swift`, `HassUI/UIKitPort/Design/UKForm.swift` | `src/components/core/FloatingActionButton.tsx`, `src/components/shell/DashboardFloatingAction.tsx` |
| [image-card.md](image-card.md) | `HassDesign/ImageCard.swift` | `src/components/hass/recipes/RecipeCard.tsx` |
| [vacuum-sheet.md](vacuum-sheet.md) | `HassUI/UIKitPort/ServerUI/UKServerUIVacuumView.swift` | `src/components/hass/VacuumCard.tsx` |
| [valetudo-map.md](valetudo-map.md) | `HassUI/UIKitPort/Features/Vacuums/UKValetudoMapView.swift`, `HassCore/Vacuums/ValetudoMap.swift` | `src/components/hass/ValetudoMapCard.tsx` |
| [thermostat-dial.md](thermostat-dial.md) | `HassDesign/ThermostatDial/ThermostatDial.swift` | `src/components/hass/CircularControlDial.tsx` |
| [schedule-date-fields.md](schedule-date-fields.md) | `HassUI/UIKitPort/Design/UKScheduleDateFields.swift` | `NativePickerField` in `ScheduleConfirmationForm` |
| [alerts.md](alerts.md) | `HassUI/Common/AlertCopy.swift` | none (native only) |
| [state-message.md](state-message.md) | `HassUI/UIKitPort/Design/UKStateMessage.swift` | `EmptyState` |
| [info-box.md](info-box.md) | `HassDesign/InfoBox.swift` | `src/components/core/InfoBox.tsx` |
| [page-indicator.md](page-indicator.md) | `HassDesign/PageIndicator.swift` | none (native only; web carousel dots) |
| [status-pill.md](status-pill.md) | `HassDesign/StatusPill.swift` | `src/components/core/StatusPill.tsx` |
| [option-picker.md](option-picker.md) | `HassDesign/OptionPickerSheet.swift` | `src/components/core/OptionPickerDialog.tsx` |
| [bedroom-devices.md](bedroom-devices.md) | `HassUI/Features/Bedroom/BedSideSheet.swift`, `HassUI/Features/Bedroom/WakeLightSheet.swift` | `src/components/hass/wakeLights/`, Bed in `DashboardViewPage.tsx` |
| [room-device-sheets.md](room-device-sheets.md) | `HassUI/UIKitPort/Features/RoomDevices/UKRoomDeviceSheets.swift`, `HassUI/UIKitPort/Features/RoomDevices/UKRoomDeviceSheets.swift` | `src/components/hass/*ModalContent.tsx` (fan, purifier, humidifier, grill) |
| [settings-section.md](settings-section.md) | `HassUI/UIKitPort/Design/UKSettingsSection.swift` | `src/components/core/SettingsSection.tsx` |
| [optimistic-actions.md](optimistic-actions.md) | `HassCore/Optimism/OptimisticActions.swift` | `src/hooks/useOptimisticState.ts`, `src/components/hass/optimisticActionState.ts` |
| [tap-feedback.md](tap-feedback.md) | `HassDesign/TapFeedback.swift`, `HassDesign/TransientFailure.swift` | none (native only) |
| [content-gate.md](content-gate.md) | `HassUI/UIKitPort/Design/UKContentGate.swift` | `src/components/hass/recipes/useRecipeCollection.ts` (criteria phases) |
| [image-cache.md](image-cache.md) | `HassDesign/Images/ImagePipeline.swift`, `HassUI/UIKitPort/Design/UKImageViews.swift` | browser HTTP cache (`decoding="async"` images) |
| [avatar.md](avatar.md) | `HassCore/Profile/PersonAvatars.swift` | none (native only; Home Assistant `person.*` `entity_picture`) |
| [telemetry.md](telemetry.md) | `HassTelemetry/Telemetry.swift` | none (native only) |
| [weather.md](weather.md) | `HassUI/UIKitPort/Features/Home/UKWeatherCarousel.swift` | `src/components/hass/WeatherSummary.tsx`, `useWeatherForecasts.ts`, `weatherPresentation.ts`, `weatherDayBriefing.ts` |
| [camera-streams.md](camera-streams.md) | `HassUI/Features/Cameras/CameraStreamPool.swift`, `HassUI/Features/Cameras/CameraLiveModel.swift`, `HassCore/Cameras/CameraStream.swift`, `HassUI/UIKitPort/Design/UKCameraControlStrip.swift`, `HassUI/UIKitPort/Design/UKCameraViewerGeometry.swift` | `SFenton/WebRTC` `www/stream-manager.js`, `rtcStreamRetention.ts` |
| [routes.md](routes.md) | `HassCore/Routes/RouteRequest.swift`, `HassCore/Push/PushLink.swift`, `FentonActivityModel/RouteCatalog.swift`, `Apps/iOS/RouteEntity.swift` | none (native; authored by the Studio) |
| [resume-lifecycle.md](resume-lifecycle.md) | `HassTelemetry/ResourceCensus.swift`, `HassUI/Diagnostics/ResourceCensusProbe.swift`, `HassUI/UIKitPort/Design/UKPaging.swift` | none (native only) |
| [motion.md](motion.md) | `HassDesign/Motion/MotionTokens.swift` | none (native; rules in `design/motion.md`) |
| [ticker.md](ticker.md) | `HassDesign/TickerLabel.swift` | none (native only) |
| [design-tokens.md](design-tokens.md) | `HassDesign/HassTokens.swift` | `src/styles/tokens.css` |
| [copy.md](copy.md) | `HassCore/Weather/WeatherCopy.swift`, `HassCore/Text/PluralCopy.swift` | `src/i18n/copy.ts` |

## Reuse rules

Standing rules from the duplication audit (evidence: [archive/audit](../archive/audit/README.md)).

- Before writing a helper, grep `HassCore/Entities`, `HassCore/Connection` and `HassDesign` for it. Feature folders hold feature logic only; infrastructure types live in those three places.
- A second copy of anything a pattern record already covers is a major review finding. Extend the shared one instead.
- Every file in `HassUI/Features/Gallery` is wrapped in `#if DEBUG`. Production code reaches the galleries only through `ComponentGallery.requested` and `galleryLastCallBanner()`, which is a no-op in Release.
- Journeys subclass `JourneyTestCase` ([devices](../testing/apple/devices.md)).
- Warnings and errors use `InlineAlert`; Form section headers and footers use `FormHeader`/`FormFooter` (the system secondary label is about 3.3:1 on the sheet background).
