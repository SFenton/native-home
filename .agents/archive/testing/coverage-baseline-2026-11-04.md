> **History, not current (2026-11-10):** UX line coverage is no longer measured (owner, 2026-11-10); this baseline is the last UX and logic measurement, kept for reference. See [coverage](../../testing/apple/coverage.md).

# Coverage baseline (combined run 2026-11-04, a6a9b30e: UX 95.61%, logic 96.09%)

> **What:** measured UX and logic line coverage and the per-file gap to 95%, from `tools/coverage_ios.py baseline`. **Read when:** you pick files to write tests for. Regenerate after a full run (`.agents/testing/apple/coverage.md`).

## UX: 95.61% (61854/64692), 0 more lines to reach 95%

Gallery-only code (fixture pages that only tests reach): 6091 lines, 295 uncovered = 10.4% of the uncovered lines.

| Area | Files | Covered / lines | % | Uncovered | of which Gallery |
|---|---:|---:|---:|---:|---:|
| HassUI/Features | 158 | 6408/7004 | 91.5 | 596 | 96 |
| UIKitPort/Design | 49 | 9053/9358 | 96.7 | 305 | 0 |
| UIKitPort/Gallery | 25 | 3588/3787 | 94.7 | 199 | 199 |
| UIKitPort/Features/Household | 10 | 2490/2666 | 93.4 | 176 | 0 |
| UIKitPort/Features/Home | 11 | 2909/3051 | 95.3 | 142 | 0 |
| UIKitPort/Features/Chores | 7 | 1974/2112 | 93.5 | 138 | 0 |
| UIKitPort/Features/Rooms | 22 | 5449/5586 | 97.5 | 137 | 0 |
| UIKitPort/Features/Inventory | 7 | 2492/2607 | 95.6 | 115 | 0 |
| UIKitPort/Features/Settings | 10 | 2711/2825 | 96.0 | 114 | 0 |
| UIKitPort/Features/Food | 4 | 1921/2032 | 94.5 | 111 | 0 |
| UIKitPort/Features/Vacuums | 8 | 2659/2758 | 96.4 | 99 | 0 |
| HassDesign | 78 | 2044/2141 | 95.5 | 97 | 0 |
| HassUI/App | 42 | 1475/1567 | 94.1 | 92 | 0 |
| UIKitPort/App/Shell | 10 | 2080/2144 | 97.0 | 64 | 0 |
| UIKitPort/Features/Cameras | 3 | 1023/1083 | 94.5 | 60 | 0 |
| HassUI/Diagnostics | 12 | 844/901 | 93.7 | 57 | 0 |
| UIKitPort/Features/Bedroom | 3 | 1610/1659 | 97.0 | 49 | 0 |
| UIKitPort/Features/Security | 7 | 941/975 | 96.5 | 34 | 0 |
| UIKitPort/App/Layout | 5 | 870/903 | 96.3 | 33 | 0 |
| UIKitPort/Features/RoomDevices | 4 | 1698/1731 | 98.1 | 33 | 0 |
| UIKitPort/Features/Climate | 5 | 1449/1478 | 98.0 | 29 | 0 |
| UIKitPort/App/Page | 10 | 972/999 | 97.3 | 27 | 0 |
| FentonActivityViews | 21 | 1114/1140 | 97.7 | 26 | 0 |
| HassDesign/Images | 1 | 255/278 | 91.7 | 23 | 0 |
| HassUI/Common | 10 | 361/382 | 94.5 | 21 | 0 |
| UIKitPort/App | 3 | 563/577 | 97.6 | 14 | 0 |
| UIKitPort/App/Login | 2 | 927/937 | 98.9 | 10 | 0 |
| UIKitPort/Diagnostics | 1 | 147/155 | 94.8 | 8 | 0 |
| UIKitPort/Features/Setup | 2 | 324/331 | 97.9 | 7 | 0 |
| HassDesign/Loading | 2 | 125/131 | 95.4 | 6 | 0 |
| HassDesign/TileActions | 15 | 233/239 | 97.5 | 6 | 0 |
| UIKitPort/Common | 5 | 343/349 | 98.3 | 6 | 0 |
| HassDesign/Avatar | 2 | 61/62 | 98.4 | 1 | 0 |
| HassDesign/Motion | 4 | 55/56 | 98.2 | 1 | 0 |
| HassDesign/ThermostatDial | 4 | 309/310 | 99.7 | 1 | 0 |
| UIKitPort/Foundation | 5 | 138/139 | 99.3 | 1 | 0 |

### UX HassUI/Features (596 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassUI/Features/Inventory/ScanCamera.swift | 56/224 | 25.0 | 168 |
| HassUI/Features/Cameras/CameraLiveModel.swift | 338/374 | 90.4 | 36 |
| HassUI/Features/Gallery/MediaRemoteGallery.swift (gallery) | 157/180 | 87.2 | 23 |
| HassUI/Features/Rooms/RoomSupport.swift | 62/80 | 77.5 | 18 |
| HassUI/Features/Gallery/VacationGallery.swift (gallery) | 107/124 | 86.3 | 17 |
| HassUI/Features/Cameras/CameraStreamPool.swift | 196/212 | 92.5 | 16 |
| HassUI/Features/Food/RecipeCollectionModel.swift | 213/227 | 93.8 | 14 |
| HassUI/Features/Gallery/SetupGallery.swift (gallery) | 81/94 | 86.2 | 13 |
| HassUI/Features/Food/RecipeDetailModel.swift | 114/125 | 91.2 | 11 |
| HassUI/Features/Bedroom/BedroomComponents.swift | 16/26 | 61.5 | 10 |
| HassUI/Features/Cameras/CameraAudio.swift | 199/209 | 95.2 | 10 |
| HassUI/Features/Inventory/InventoryItemEditor.swift | 66/76 | 86.8 | 10 |
| HassUI/Features/MediaRemote/MediaRemoteControls.swift | 30/40 | 75.0 | 10 |
| HassUI/Features/Chores/TodoListSection+Swipe.swift | 7/15 | 46.7 | 8 |
| HassUI/Features/Gallery/BedroomGallery.swift (gallery) | 320/328 | 97.6 | 8 |
| HassUI/Features/Home/Weather/WeatherHourlyMode.swift | 7/15 | 46.7 | 8 |
| HassUI/Features/Inventory/InventoryPresentation.swift | 45/53 | 84.9 | 8 |
| HassUI/Features/Settings/Feedback/FeedbackFormModel.swift | 187/195 | 95.9 | 8 |
| HassUI/Features/Cameras/WebRTCCameraPeer.swift | 265/272 | 97.4 | 7 |
| HassUI/Features/Climate/ClimateComponents.swift | 1/8 | 12.5 | 7 |
| HassUI/Features/Climate/ClimateScreen.swift | 0/7 | 0.0 | 7 |
| HassUI/Features/Gallery/RoomDevicesGallery.swift (gallery) | 167/174 | 96.0 | 7 |
| HassUI/Features/Chores/ChoresModel.swift | 33/39 | 84.6 | 6 |
| HassUI/Features/Gallery/ChoresGallery.swift (gallery) | 148/154 | 96.1 | 6 |
| HassUI/Features/Inventory/InventoryPrompt.swift | 18/24 | 75.0 | 6 |
| HassUI/Features/Settings/HomeAssistantSettingsView.swift | 45/51 | 88.2 | 6 |
| HassUI/Features/Chores/TodoPageLayout.swift | 36/41 | 87.8 | 5 |
| HassUI/Features/Home/HomeColumns.swift | 9/14 | 64.3 | 5 |
| HassUI/Features/RoomDevices/HumidifierSchedulesTab.swift | 10/15 | 66.7 | 5 |
| HassUI/Features/Rooms/QuickLinksSheet.swift | 8/13 | 61.5 | 5 |
| HassUI/Features/Settings/Profile/PersonRow.swift | 7/12 | 58.3 | 5 |
| HassUI/Features/Cameras/CameraLiveView.swift | 17/21 | 81.0 | 4 |
| HassUI/Features/Gallery/SecurityGallery.swift (gallery) | 78/82 | 95.1 | 4 |
| HassUI/Features/Home/Weather/WeatherCardContent.swift | 5/9 | 55.6 | 4 |
| HassUI/Features/Login/LoginModel.swift | 120/124 | 96.8 | 4 |
| HassUI/Features/Rooms/RoomSheets.swift | 3/7 | 42.9 | 4 |
| HassUI/Features/Settings/Feedback/FeedbackPickedMedia.swift | 39/43 | 90.7 | 4 |
| HassUI/Features/Settings/Household/HouseholdSettingsPage.swift | 36/40 | 90.0 | 4 |
| HassUI/Features/Sprinklers/SprinklerControllerSheet.swift | 16/20 | 80.0 | 4 |
| HassUI/Features/Cameras/CameraViewer.swift | 41/44 | 93.2 | 3 |
| HassUI/Features/Cameras/SignallingSocket.swift | 26/29 | 89.7 | 3 |
| HassUI/Features/Chores/DonetickTaskSheet.swift | 0/3 | 0.0 | 3 |
| HassUI/Features/Login/DebugSignInStub.swift | 50/53 | 94.3 | 3 |
| HassUI/Features/Rooms/RoomDeviceRouting.swift | 37/40 | 92.5 | 3 |
| HassUI/Features/Vacuums/VacuumComponents.swift | 20/23 | 87.0 | 3 |
| HassUI/Features/Vacuums/ValetudoMapView.swift | 99/102 | 97.1 | 3 |
| HassUI/Features/Cameras/LiveVideoSurface.swift | 54/56 | 96.4 | 2 |
| HassUI/Features/Chores/DonetickTaskFields.swift | 38/40 | 95.0 | 2 |
| HassUI/Features/Chores/TodoDraftStore.swift | 23/25 | 92.0 | 2 |
| HassUI/Features/Chores/TodoListSection.swift | 10/12 | 83.3 | 2 |
| HassUI/Features/Food/SuggestedRecipesCarousel.swift | 7/9 | 77.8 | 2 |
| HassUI/Features/Gallery/FoodGallery.swift (gallery) | 158/160 | 98.8 | 2 |
| HassUI/Features/Gallery/GalleryReset.swift (gallery) | 95/97 | 97.9 | 2 |
| HassUI/Features/Gallery/HomePagesGallery.swift (gallery) | 195/197 | 99.0 | 2 |
| HassUI/Features/Gallery/ProfileGallery.swift (gallery) | 88/90 | 97.8 | 2 |
| HassUI/Features/Gallery/RoomsGallery.swift (gallery) | 129/131 | 98.5 | 2 |
| HassUI/Features/Gallery/VacuumGallery.swift (gallery) | 120/122 | 98.4 | 2 |
| HassUI/Features/Gallery/WeatherFixtureCaller.swift (gallery) | 15/17 | 88.2 | 2 |
| HassUI/Features/Inventory/InventorySheetContent.swift | 8/10 | 80.0 | 2 |
| HassUI/Features/Media/MediaScreen.swift | 19/21 | 90.5 | 2 |
| HassUI/Features/MediaRemote/MediaRemoteSheet.swift | 76/78 | 97.4 | 2 |
| HassUI/Features/RoomDevices/HumidifierDials.swift | 66/68 | 97.1 | 2 |
| HassUI/Features/RoomDevices/HumidifierSheet.swift | 10/12 | 83.3 | 2 |
| HassUI/Features/Rooms/RoomScreen.swift | 22/24 | 91.7 | 2 |
| HassUI/Features/Settings/Feedback/FeedbackDiagnosticsCollector.swift | 60/62 | 96.8 | 2 |
| HassUI/Features/TileActions/RemoteTileSupport.swift | 16/18 | 88.9 | 2 |
| HassUI/Features/Vacuums/VacuumAreaEditor.swift | 48/50 | 96.0 | 2 |
| HassUI/Features/Bedroom/BedAlarmsTab.swift | 4/5 | 80.0 | 1 |
| HassUI/Features/Bedroom/BedSideSheet.swift | 8/9 | 88.9 | 1 |
| HassUI/Features/Bedroom/WakeLightSheet.swift | 1/2 | 50.0 | 1 |
| HassUI/Features/Chores/TodoItemRow.swift | 31/32 | 96.9 | 1 |
| HassUI/Features/Chores/TodoItemSheets.swift | 6/7 | 85.7 | 1 |
| HassUI/Features/Chores/TodoPageSheets.swift | 16/17 | 94.1 | 1 |
| HassUI/Features/Climate/ClimateSheet.swift | 30/31 | 96.8 | 1 |
| HassUI/Features/Food/SuggestedRecipesModel.swift | 37/38 | 97.4 | 1 |
| HassUI/Features/Gallery/ClimateGallery.swift (gallery) | 90/91 | 98.9 | 1 |
| HassUI/Features/Gallery/ComponentGallery.swift (gallery) | 4/5 | 80.0 | 1 |
| HassUI/Features/Gallery/HouseholdSettingsGallery.swift (gallery) | 75/76 | 98.7 | 1 |
| HassUI/Features/Gallery/WeatherFixtures.swift (gallery) | 99/100 | 99.0 | 1 |
| HassUI/Features/Home/CameraGrid.swift | 10/11 | 90.9 | 1 |
| HassUI/Features/Home/HomeRoute.swift | 60/61 | 98.4 | 1 |
| HassUI/Features/Home/Weather/WeatherCarouselPaging.swift | 36/37 | 97.3 | 1 |
| HassUI/Features/Home/Weather/WeatherChartText.swift | 20/21 | 95.2 | 1 |
| HassUI/Features/Inventory/InventoryScreen.swift | 3/4 | 75.0 | 1 |
| HassUI/Features/Login/SignInStyle.swift | 3/4 | 75.0 | 1 |
| HassUI/Features/MediaRemote/MediaRemoteTabs.swift | 0/1 | 0.0 | 1 |
| HassUI/Features/Security/SecurityScreen.swift | 7/8 | 87.5 | 1 |
| HassUI/Features/Security/SecuritySystemSheet.swift | 9/10 | 90.0 | 1 |
| HassUI/Features/Settings/AppIcon/AppIconPlatform.swift | 9/10 | 90.0 | 1 |
| HassUI/Features/Setup/SetupPoint.swift | 0/1 | 0.0 | 1 |
| HassUI/Features/Setup/SystemSettingsLink.swift | 6/7 | 85.7 | 1 |
| HassUI/Features/TileActions/TileActionItem+Spec.swift | 56/57 | 98.2 | 1 |
| HassUI/Features/Vacuums/VacuumCleanTarget.swift | 9/10 | 90.0 | 1 |
| HassUI/Features/Vacuums/VacuumControlsTab.swift | 1/2 | 50.0 | 1 |
| HassUI/Features/Vacuums/VacuumMapPanel.swift | 19/20 | 95.0 | 1 |

### UX UIKitPort/Design (305 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassUI/UIKitPort/Design/UKGlassTileView.swift | 668/720 | 92.8 | 52 |
| HassUI/UIKitPort/Design/UKHassModal.swift | 450/498 | 90.4 | 48 |
| HassUI/UIKitPort/Design/UKArcSpinnerView.swift | 133/152 | 87.5 | 19 |
| HassUI/UIKitPort/Design/UKThermostatDial.swift | 499/518 | 96.3 | 19 |
| HassUI/UIKitPort/Design/UKGlass.swift | 69/87 | 79.3 | 18 |
| HassUI/UIKitPort/Design/UKSheetItems.swift | 107/124 | 86.3 | 17 |
| HassUI/UIKitPort/Design/UKSegmentedControls.swift | 336/352 | 95.5 | 16 |
| HassUI/UIKitPort/Design/UKFloatingActionBar.swift | 432/441 | 98.0 | 9 |
| HassUI/UIKitPort/Design/UKPinnedBar.swift | 54/63 | 85.7 | 9 |
| HassUI/UIKitPort/Design/UKImageViews.swift | 333/341 | 97.7 | 8 |
| HassUI/UIKitPort/Design/UKTileActions.swift | 452/459 | 98.5 | 7 |
| HassUI/UIKitPort/Design/UKTickerLabel.swift | 298/304 | 98.0 | 6 |
| HassUI/UIKitPort/Design/UKGlassTileFaceView.swift | 475/480 | 99.0 | 5 |
| HassUI/UIKitPort/Design/UKHingeAvoidance.swift | 70/75 | 93.3 | 5 |
| HassUI/UIKitPort/Design/UKModule.swift | 102/107 | 95.3 | 5 |
| HassUI/UIKitPort/Design/UKPaging.swift | 237/242 | 97.9 | 5 |
| HassUI/UIKitPort/Design/UKStatusPillView.swift | 114/119 | 95.8 | 5 |
| HassUI/UIKitPort/Design/UKClimateThermostatDial.swift | 85/89 | 95.5 | 4 |
| HassUI/UIKitPort/Design/UKDiscardGuard.swift | 74/78 | 94.9 | 4 |
| HassUI/UIKitPort/Design/UKDynamicGrid.swift | 273/277 | 98.6 | 4 |
| HassUI/UIKitPort/Design/UKForm.swift | 427/431 | 99.1 | 4 |
| HassUI/UIKitPort/Design/UKModuleToggleRow.swift | 18/22 | 81.8 | 4 |
| HassUI/UIKitPort/Design/UKMotion.swift | 84/88 | 95.5 | 4 |
| HassUI/UIKitPort/Design/UKContentGate.swift | 134/137 | 97.8 | 3 |
| HassUI/UIKitPort/Design/UKControllerControls.swift | 101/104 | 97.1 | 3 |
| HassUI/UIKitPort/Design/UKPagePinnedBar.swift | 90/93 | 96.8 | 3 |
| HassUI/UIKitPort/Design/UKPrimaryButton.swift | 121/124 | 97.6 | 3 |
| HassUI/UIKitPort/Design/UKTilePaint.swift | 260/263 | 98.9 | 3 |
| HassUI/UIKitPort/Design/UKAvatarView.swift | 175/177 | 98.9 | 2 |
| HassUI/UIKitPort/Design/UKLayoutViews.swift | 293/295 | 99.3 | 2 |
| HassUI/UIKitPort/Design/UKStatusChipView.swift | 149/151 | 98.7 | 2 |
| HassUI/UIKitPort/Design/UKBrightnessTileView.swift | 202/203 | 99.5 | 1 |
| HassUI/UIKitPort/Design/UKCheckRow.swift | 25/26 | 96.2 | 1 |
| HassUI/UIKitPort/Design/UKPercentSliderRow.swift | 56/57 | 98.2 | 1 |
| HassUI/UIKitPort/Design/UKScheduleDateFields.swift | 163/164 | 99.4 | 1 |
| HassUI/UIKitPort/Design/UKSelfSizing.swift | 34/35 | 97.1 | 1 |
| HassUI/UIKitPort/Design/UKStateMessage.swift | 149/150 | 99.3 | 1 |
| HassUI/UIKitPort/Design/UKValueLabel.swift | 35/36 | 97.2 | 1 |

### UX UIKitPort/Gallery (199 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassUI/UIKitPort/Gallery/UKDesignControlsGallery.swift (gallery) | 403/524 | 76.9 | 121 |
| HassUI/UIKitPort/Gallery/UKDesignListsGallery.swift (gallery) | 322/354 | 91.0 | 32 |
| HassUI/UIKitPort/Gallery/UKDirectionGGallery.swift (gallery) | 729/747 | 97.6 | 18 |
| HassUI/UIKitPort/Gallery/UKPerformanceGallery.swift (gallery) | 206/214 | 96.3 | 8 |
| HassUI/UIKitPort/Gallery/UKShellGallery.swift (gallery) | 135/140 | 96.4 | 5 |
| HassUI/UIKitPort/Gallery/UKRoomDevicesGallery.swift (gallery) | 65/69 | 94.2 | 4 |
| HassUI/UIKitPort/Gallery/UKRoomsGallery.swift (gallery) | 151/155 | 97.4 | 4 |
| HassUI/UIKitPort/Gallery/UKFoodGallery.swift (gallery) | 166/169 | 98.2 | 3 |
| HassUI/UIKitPort/Gallery/UKHouseholdGallery.swift (gallery) | 189/191 | 99.0 | 2 |
| HassUI/UIKitPort/Gallery/UKGalleryRouter.swift (gallery) | 25/26 | 96.2 | 1 |
| HassUI/UIKitPort/Gallery/UKMediaRemoteGalleryPage.swift (gallery) | 114/115 | 99.1 | 1 |

### UX UIKitPort/Features/Household (176 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassUI/UIKitPort/Features/Household/UKVacation.swift | 652/709 | 92.0 | 57 |
| HassUI/UIKitPort/Features/Household/UKSummaryTabs.swift | 396/451 | 87.8 | 55 |
| HassUI/UIKitPort/Features/Household/UKYourSummary.swift | 238/262 | 90.8 | 24 |
| HassUI/UIKitPort/Features/Household/UKHouseholdSettings.swift | 389/401 | 97.0 | 12 |
| HassUI/UIKitPort/Features/Household/UKHouseholdParts.swift | 208/219 | 95.0 | 11 |
| HassUI/UIKitPort/Features/Household/UKSummaryProfile.swift | 210/218 | 96.3 | 8 |
| HassUI/UIKitPort/Features/Household/UKVacationParts.swift | 124/129 | 96.1 | 5 |
| HassUI/UIKitPort/Features/Household/UKGrouped.swift | 71/73 | 97.3 | 2 |
| HassUI/UIKitPort/Features/Household/UKLocation.swift | 188/190 | 98.9 | 2 |

### UX UIKitPort/Features/Home (142 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassUI/UIKitPort/Features/Home/UKRoomOverview.swift | 439/481 | 91.3 | 42 |
| HassUI/UIKitPort/Features/Home/UKHomeSupport.swift | 65/89 | 73.0 | 24 |
| HassUI/UIKitPort/Features/Home/UKWeatherSheet.swift | 778/802 | 97.0 | 24 |
| HassUI/UIKitPort/Features/Home/UKWeatherCarousel.swift | 319/338 | 94.4 | 19 |
| HassUI/UIKitPort/Features/Home/UKWeatherCard.swift | 390/402 | 97.0 | 12 |
| HassUI/UIKitPort/Features/Home/UKWeatherViews.swift | 488/498 | 98.0 | 10 |
| HassUI/UIKitPort/Features/Home/UKHomeViewController.swift | 198/206 | 96.1 | 8 |
| HassUI/UIKitPort/Features/Home/UKWeatherBackdrop.swift | 189/191 | 99.0 | 2 |
| HassUI/UIKitPort/Features/Home/UKStatusRail.swift | 42/43 | 97.7 | 1 |

### UX UIKitPort/Features/Chores (138 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassUI/UIKitPort/Features/Chores/UKTodoPageViewController.swift | 531/604 | 87.9 | 73 |
| HassUI/UIKitPort/Features/Chores/UKTodoForms.swift | 585/622 | 94.1 | 37 |
| HassUI/UIKitPort/Features/Chores/UKDonetickTaskViewController.swift | 418/433 | 96.5 | 15 |
| HassUI/UIKitPort/Features/Chores/UKChoresQuickLinks.swift | 70/77 | 90.9 | 7 |
| HassUI/UIKitPort/Features/Chores/UKTodoItemRow.swift | 190/196 | 96.9 | 6 |

### UX UIKitPort/Features/Rooms (137 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassUI/UIKitPort/Features/Rooms/UKRoomViewController.swift | 172/194 | 88.7 | 22 |
| HassUI/UIKitPort/Features/Rooms/MediaRemote/UKMediaRemoteControls.swift | 559/573 | 97.6 | 14 |
| HassUI/UIKitPort/Features/Rooms/MediaRemote/UKMediaRemoteTabs.swift | 637/650 | 98.0 | 13 |
| HassUI/UIKitPort/Features/Rooms/UKRoomsSheets.swift | 322/333 | 96.7 | 11 |
| HassUI/UIKitPort/Features/Rooms/UKRoomCards.swift | 378/388 | 97.4 | 10 |
| HassUI/UIKitPort/Features/Rooms/Sprinklers/UKSprinklersViewController.swift | 138/146 | 94.5 | 8 |
| HassUI/UIKitPort/Features/Rooms/Sprinklers/UKSprinklerSchedulePage.swift | 265/272 | 97.4 | 7 |
| HassUI/UIKitPort/Features/Rooms/UKRoomsBinding.swift | 121/128 | 94.5 | 7 |
| HassUI/UIKitPort/Features/Rooms/CustomLights/UKCustomLightSheetViewController.swift | 293/298 | 98.3 | 5 |
| HassUI/UIKitPort/Features/Rooms/MediaRemote/UKMediaRemoteSupport.swift | 64/69 | 92.8 | 5 |
| HassUI/UIKitPort/Features/Rooms/Sprinklers/UKSprinklerWaterPage.swift | 135/140 | 96.4 | 5 |
| HassUI/UIKitPort/Features/Rooms/UKMediaViewController.swift | 275/280 | 98.2 | 5 |
| HassUI/UIKitPort/Features/Rooms/CustomLights/UKCustomLightsViewController.swift | 267/271 | 98.5 | 4 |
| HassUI/UIKitPort/Features/Rooms/MediaRemote/UKMediaRemoteSheet.swift | 194/198 | 98.0 | 4 |
| HassUI/UIKitPort/Features/Rooms/UKQuickLinks.swift | 262/266 | 98.5 | 4 |
| HassUI/UIKitPort/Features/Rooms/Sprinklers/UKSprinklerList.swift | 285/288 | 99.0 | 3 |
| HassUI/UIKitPort/Features/Rooms/UKRoomSectionView.swift | 134/137 | 97.8 | 3 |
| HassUI/UIKitPort/Features/Rooms/UKRoomsSupport.swift | 213/216 | 98.6 | 3 |
| HassUI/UIKitPort/Features/Rooms/UKRoomsParts.swift | 155/157 | 98.7 | 2 |
| HassUI/UIKitPort/Features/Rooms/Sprinklers/UKSprinklerRows.swift | 358/359 | 99.7 | 1 |
| HassUI/UIKitPort/Features/Rooms/Sprinklers/UKSprinklerSheet.swift | 212/213 | 99.5 | 1 |

### UX UIKitPort/Features/Inventory (115 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassUI/UIKitPort/Features/Inventory/UKScanItemSheet.swift | 887/927 | 95.7 | 40 |
| HassUI/UIKitPort/Features/Inventory/UKInventoryViewController.swift | 588/620 | 94.8 | 32 |
| HassUI/UIKitPort/Features/Inventory/UKInventoryEditor.swift | 291/305 | 95.4 | 14 |
| HassUI/UIKitPort/Features/Inventory/UKFormRows.swift | 162/175 | 92.6 | 13 |
| HassUI/UIKitPort/Features/Inventory/UKInventoryRow.swift | 297/308 | 96.4 | 11 |
| HassUI/UIKitPort/Features/Inventory/UKInventoryRowActions.swift | 120/124 | 96.8 | 4 |
| HassUI/UIKitPort/Features/Inventory/UKInventorySheets.swift | 147/148 | 99.3 | 1 |

### UX UIKitPort/Features/Settings (114 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassUI/UIKitPort/Features/Settings/UKFeedback.swift | 598/634 | 94.3 | 36 |
| HassUI/UIKitPort/Features/Settings/UKHomeAssistantSettings.swift | 308/337 | 91.4 | 29 |
| HassUI/UIKitPort/Features/Settings/UKSettingsViewController.swift | 428/448 | 95.5 | 20 |
| HassUI/UIKitPort/Features/Settings/UKAppIcon.swift | 309/317 | 97.5 | 8 |
| HassUI/UIKitPort/Features/Settings/UKSettingsList.swift | 342/350 | 97.7 | 8 |
| HassUI/UIKitPort/Features/Settings/UKPerformanceViewController.swift | 219/224 | 97.8 | 5 |
| HassUI/UIKitPort/Features/Settings/UKSettingsStack.swift | 386/390 | 99.0 | 4 |
| HassUI/UIKitPort/Features/Settings/UKNotificationsSettings.swift | 33/36 | 91.7 | 3 |
| HassUI/UIKitPort/Features/Settings/UKSettingsRows.swift | 79/80 | 98.8 | 1 |

### UX UIKitPort/Features/Food (111 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassUI/UIKitPort/Features/Food/UKFoodHubViewController.swift | 527/567 | 92.9 | 40 |
| HassUI/UIKitPort/Features/Food/UKRecipesViewController.swift | 644/682 | 94.4 | 38 |
| HassUI/UIKitPort/Features/Food/UKRecipeDetail.swift | 683/709 | 96.3 | 26 |
| HassUI/UIKitPort/Features/Food/UKFoodEntry.swift | 67/74 | 90.5 | 7 |

### UX UIKitPort/Features/Vacuums (99 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassUI/UIKitPort/Features/Vacuums/UKVacuumComponents.swift | 487/511 | 95.3 | 24 |
| HassUI/UIKitPort/Features/Vacuums/UKVacuumTabs.swift | 381/402 | 94.8 | 21 |
| HassUI/UIKitPort/Features/Vacuums/UKVacuumAreaEditor.swift | 385/402 | 95.8 | 17 |
| HassUI/UIKitPort/Features/Vacuums/UKVacuumMapPanel.swift | 430/447 | 96.2 | 17 |
| HassUI/UIKitPort/Features/Vacuums/UKVacuumSheet.swift | 216/223 | 96.9 | 7 |
| HassUI/UIKitPort/Features/Vacuums/UKVacuumsViewController.swift | 315/321 | 98.1 | 6 |
| HassUI/UIKitPort/Features/Vacuums/UKValetudoMapView.swift | 429/433 | 99.1 | 4 |
| HassUI/UIKitPort/Features/Vacuums/UKVacuumsEntry.swift | 16/19 | 84.2 | 3 |

### UX HassDesign (97 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassDesign/TintedGlassGround.swift | 115/136 | 84.6 | 21 |
| HassDesign/SheetFit.swift | 192/208 | 92.3 | 16 |
| HassDesign/HassTokens.swift | 8/17 | 47.1 | 9 |
| HassDesign/ColorFamily.swift | 117/124 | 94.4 | 7 |
| HassDesign/DynamicGridLayout.swift | 279/286 | 97.6 | 7 |
| HassDesign/OptionPickerSheet.swift | 0/7 | 0.0 | 7 |
| HassDesign/Color+RGB.swift | 16/21 | 76.2 | 5 |
| HassDesign/SheetChrome.swift | 111/115 | 96.5 | 4 |
| HassDesign/TileFinish.swift | 18/22 | 81.8 | 4 |
| HassDesign/SheetSubtitle.swift | 3/6 | 50.0 | 3 |
| HassDesign/TransientFailure.swift | 21/24 | 87.5 | 3 |
| HassDesign/Announcer.swift | 9/11 | 81.8 | 2 |
| HassDesign/ChipTint.swift | 55/57 | 96.5 | 2 |
| HassDesign/SystemAppearance.swift | 23/25 | 92.0 | 2 |
| HassDesign/TileLayout.swift | 13/15 | 86.7 | 2 |
| HassDesign/ColorFamily+Glass.swift | 22/23 | 95.7 | 1 |
| HassDesign/QuickLinkPalette.swift | 14/15 | 93.3 | 1 |
| HassDesign/TintedGlassSheen.swift | 10/11 | 90.9 | 1 |

### UX HassUI/App (92 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassUI/App/Location/SystemDeviceStatusSource.swift | 122/140 | 87.1 | 18 |
| HassUI/App/Location/SystemBackgroundRefresh.swift | 18/35 | 51.4 | 17 |
| HassUI/App/AppSession.swift | 161/171 | 94.2 | 10 |
| HassUI/App/Push/PushPlatform.swift | 13/21 | 61.9 | 8 |
| HassUI/App/Location/LocationCoordinator.swift | 125/132 | 94.7 | 7 |
| HassUI/App/MobileApp/MobileAppCoordinator.swift | 143/149 | 96.0 | 6 |
| HassUI/App/Shell/PageChromeTitle.swift | 0/6 | 0.0 | 6 |
| HassUI/App/Layout/SplitPolicy.swift | 38/43 | 88.4 | 5 |
| HassUI/App/Layout/OrientationPolicy.swift | 62/66 | 93.9 | 4 |
| HassUI/App/Location/UIKitBackgroundTime.swift | 17/21 | 81.0 | 4 |
| HassUI/App/Setup/SetupCoordinator.swift | 61/63 | 96.8 | 2 |
| HassUI/App/LiveActivity/LiveActivityCoordinator.swift | 30/31 | 96.8 | 1 |
| HassUI/App/Push/PushCoordinator.swift | 114/115 | 99.1 | 1 |
| HassUI/App/Shell/ProfileButton.swift | 27/28 | 96.4 | 1 |
| HassUI/App/Shell/ReconnectingIndicatorHost.swift | 3/4 | 75.0 | 1 |
| HassUI/App/Spotlight/CoreSpotlightIndexer.swift | 34/35 | 97.1 | 1 |

### UX UIKitPort/App/Shell (64 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassUI/UIKitPort/App/Shell/UKShellViewController.swift | 447/474 | 94.3 | 27 |
| HassUI/UIKitPort/App/Shell/UKSectionNavigationController.swift | 353/371 | 95.1 | 18 |
| HassUI/UIKitPort/App/Shell/UKNavigationFlyout.swift | 388/395 | 98.2 | 7 |
| HassUI/UIKitPort/App/Shell/UKReconnectingHost.swift | 55/59 | 93.2 | 4 |
| HassUI/UIKitPort/App/Shell/UKShellHeaderItems.swift | 239/242 | 98.8 | 3 |
| HassUI/UIKitPort/App/Shell/UKOfflineChip.swift | 125/127 | 98.4 | 2 |
| HassUI/UIKitPort/App/Shell/UKShellEnvironment.swift | 44/46 | 95.7 | 2 |
| HassUI/UIKitPort/App/Shell/UKArrivalChrome.swift | 50/51 | 98.0 | 1 |

### UX UIKitPort/Features/Cameras (60 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassUI/UIKitPort/Features/Cameras/UKCameraLiveView.swift | 303/333 | 91.0 | 30 |
| HassUI/UIKitPort/Features/Cameras/UKCameraViewer.swift | 447/477 | 93.7 | 30 |

### UX HassUI/Diagnostics (57 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassUI/Diagnostics/FrameMonitor.swift | 67/82 | 81.7 | 15 |
| HassUI/Diagnostics/ScrollCostProbe.swift | 259/272 | 95.2 | 13 |
| HassUI/Diagnostics/PerformanceRow.swift | 21/29 | 72.4 | 8 |
| HassUI/Diagnostics/LayerCensus.swift | 151/156 | 96.8 | 5 |
| HassUI/Diagnostics/MetricKitCollector.swift | 58/62 | 93.5 | 4 |
| HassUI/Diagnostics/FramePacer.swift | 66/69 | 95.7 | 3 |
| HassUI/Diagnostics/LaunchCostProbe.swift | 38/41 | 92.7 | 3 |
| HassUI/Diagnostics/PerformanceReport.swift | 61/64 | 95.3 | 3 |
| HassUI/Diagnostics/PerformanceScreen.swift | 26/29 | 89.7 | 3 |

### UX UIKitPort/Features/Bedroom (49 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassUI/UIKitPort/Features/Bedroom/UKBedSideSheet.swift | 765/791 | 96.7 | 26 |
| HassUI/UIKitPort/Features/Bedroom/UKWakeLightSheet.swift | 622/642 | 96.9 | 20 |
| HassUI/UIKitPort/Features/Bedroom/UKBedroomKit.swift | 223/226 | 98.7 | 3 |

### UX UIKitPort/Features/Security (34 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassUI/UIKitPort/Features/Security/UKSecurityViewController.swift | 113/127 | 89.0 | 14 |
| HassUI/UIKitPort/Features/Security/UKAlarmPanelView.swift | 435/444 | 98.0 | 9 |
| HassUI/UIKitPort/Features/Security/UKSecurityTiles.swift | 202/206 | 98.1 | 4 |
| HassUI/UIKitPort/Features/Security/UKSecurityGuests.swift | 140/143 | 97.9 | 3 |
| HassUI/UIKitPort/Features/Security/UKSecuritySystemSheet.swift | 35/38 | 92.1 | 3 |
| HassUI/UIKitPort/Features/Security/UKSecurityEntry.swift | 12/13 | 92.3 | 1 |

### UX UIKitPort/App/Layout (33 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassUI/UIKitPort/App/Layout/UKDeviceSignals.swift | 70/89 | 78.7 | 19 |
| HassUI/UIKitPort/App/Layout/UKColumnsViewController.swift | 612/625 | 97.9 | 13 |
| HassUI/UIKitPort/App/Layout/UKLayoutCensus.swift | 88/89 | 98.9 | 1 |

### UX UIKitPort/Features/RoomDevices (33 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassUI/UIKitPort/Features/RoomDevices/UKHumidifierSheet.swift | 703/721 | 97.5 | 18 |
| HassUI/UIKitPort/Features/RoomDevices/UKRoomDeviceSheets.swift | 504/512 | 98.4 | 8 |
| HassUI/UIKitPort/Features/RoomDevices/UKDeviceKit.swift | 460/467 | 98.5 | 7 |

### UX UIKitPort/Features/Climate (29 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassUI/UIKitPort/Features/Climate/UKClimateSheet.swift | 823/837 | 98.3 | 14 |
| HassUI/UIKitPort/Features/Climate/UKClimateViewController.swift | 199/207 | 96.1 | 8 |
| HassUI/UIKitPort/Features/Climate/UKClimateParts.swift | 174/179 | 97.2 | 5 |
| HassUI/UIKitPort/Features/Climate/UKClimateForm.swift | 252/254 | 99.2 | 2 |

### UX UIKitPort/App/Page (27 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassUI/UIKitPort/App/Page/UKPageViewController.swift | 527/545 | 96.7 | 18 |
| HassUI/UIKitPort/App/Page/UKFixedBarTitle.swift | 55/59 | 93.2 | 4 |
| HassUI/UIKitPort/App/Page/UKPageBody.swift | 85/87 | 97.7 | 2 |
| HassUI/UIKitPort/App/Page/UKPageHost.swift | 77/79 | 97.5 | 2 |
| HassUI/UIKitPort/App/Page/UKScrollToTop.swift | 16/17 | 94.1 | 1 |

### UX FentonActivityViews (26 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| FentonActivityViews/ActivityRing.swift | 68/76 | 89.5 | 8 |
| FentonActivityViews/ActivityBar.swift | 29/33 | 87.9 | 4 |
| FentonActivityViews/HomeActivityIslandViews.swift | 264/268 | 98.5 | 4 |
| FentonActivityViews/ActivityActions.swift | 5/8 | 62.5 | 3 |
| FentonActivityViews/CornerMarkPalette.swift | 4/6 | 66.7 | 2 |
| FentonActivityViews/ActivityGlyphImage.swift | 33/34 | 97.1 | 1 |
| FentonActivityViews/ActivityStyle.swift | 11/12 | 91.7 | 1 |
| FentonActivityViews/CornerMark.swift | 9/10 | 90.0 | 1 |
| FentonActivityViews/JobCardView.swift | 70/71 | 98.6 | 1 |
| FentonActivityViews/ProblemCardView.swift | 108/109 | 99.1 | 1 |

### UX HassDesign/Images (23 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassDesign/Images/ImagePipeline.swift | 255/278 | 91.7 | 23 |

### UX HassUI/Common (21 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassUI/Common/HouseBackdrop.swift | 156/172 | 90.7 | 16 |
| HassUI/Common/BackdropRenderer.swift | 89/91 | 97.8 | 2 |
| HassUI/Common/ScreenshotPrivacy.swift | 7/9 | 77.8 | 2 |
| HassUI/Common/AlertCopy.swift | 29/30 | 96.7 | 1 |

### UX UIKitPort/App (14 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassUI/UIKitPort/App/UKRootViewController.swift | 504/518 | 97.3 | 14 |

### UX UIKitPort/App/Login (10 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassUI/UIKitPort/App/Login/UKLoginViewController.swift | 492/499 | 98.6 | 7 |
| HassUI/UIKitPort/App/Login/UKLoginParts.swift | 435/438 | 99.3 | 3 |

### UX UIKitPort/Diagnostics (8 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassUI/UIKitPort/Diagnostics/UKProbes.swift | 147/155 | 94.8 | 8 |

### UX UIKitPort/Features/Setup (7 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassUI/UIKitPort/Features/Setup/UKSetupSheet.swift | 170/176 | 96.6 | 6 |
| HassUI/UIKitPort/Features/Setup/UKSetupParts.swift | 154/155 | 99.4 | 1 |

### UX HassDesign/Loading (6 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassDesign/Loading/ContentGateModel.swift | 115/121 | 95.0 | 6 |

### UX HassDesign/TileActions (6 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassDesign/TileActions/TileActionSetTransition.swift | 11/14 | 78.6 | 3 |
| HassDesign/TileActions/TileSelectionIndicator.swift | 59/61 | 96.7 | 2 |
| HassDesign/TileActions/TileActionConfirmation.swift | 23/24 | 95.8 | 1 |

### UX UIKitPort/Common (6 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassUI/UIKitPort/Common/UKProfilePhotoView.swift | 56/60 | 93.3 | 4 |
| HassUI/UIKitPort/Common/UKBackdropView.swift | 147/148 | 99.3 | 1 |
| HassUI/UIKitPort/Common/UKShellFont.swift | 19/20 | 95.0 | 1 |

### UX HassDesign/Avatar (1 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassDesign/Avatar/AvatarFade.swift | 55/56 | 98.2 | 1 |

### UX HassDesign/Motion (1 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassDesign/Motion/StateColorTransition.swift | 33/34 | 97.1 | 1 |

### UX HassDesign/ThermostatDial (1 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassDesign/ThermostatDial/ThermostatDialModel.swift | 231/232 | 99.6 | 1 |

### UX UIKitPort/Foundation (1 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassUI/UIKitPort/Foundation/UKPerfSwitches.swift | 2/3 | 66.7 | 1 |

## LOGIC: 96.09% (23400/24352), 0 more lines to reach 95%

| Area | Files | Covered / lines | % | Uncovered | of which Gallery |
|---|---:|---:|---:|---:|---:|
| HassCore/Location | 9 | 614/824 | 74.5 | 210 | 0 |
| HassCore/Connection | 18 | 1140/1250 | 91.2 | 110 | 0 |
| HassCore/Bedroom | 7 | 1649/1718 | 96.0 | 69 | 0 |
| HassCore/Rooms | 11 | 1076/1136 | 94.7 | 60 | 0 |
| HassCore/Weather | 40 | 1863/1923 | 96.9 | 60 | 0 |
| HassCore/Vacuums | 12 | 2453/2511 | 97.7 | 58 | 0 |
| HassCore/Auth | 7 | 284/329 | 86.3 | 45 | 0 |
| HassCore/Profile | 7 | 703/748 | 94.0 | 45 | 0 |
| HassCore/RoomDevices | 6 | 854/893 | 95.6 | 39 | 0 |
| HassCore/Config | 14 | 1138/1176 | 96.8 | 38 | 0 |
| HassCore/Recipes | 5 | 1192/1229 | 97.0 | 37 | 0 |
| HassCore/MobileApp | 28 | 1053/1075 | 98.0 | 22 | 0 |
| HassCore/Todo | 5 | 566/586 | 96.6 | 20 | 0 |
| HassCore/Inventory | 8 | 1961/1980 | 99.0 | 19 | 0 |
| HassCore/Feedback | 19 | 534/552 | 96.7 | 18 | 0 |
| HassCore/HouseholdAway | 7 | 952/970 | 98.1 | 18 | 0 |
| HassCore/LiveActivity | 4 | 213/231 | 92.2 | 18 | 0 |
| FentonActivityModel | 14 | 768/782 | 98.2 | 14 | 0 |
| HassCore/Sprinklers | 3 | 394/406 | 97.0 | 12 | 0 |
| HassCore/TileActions | 23 | 770/782 | 98.5 | 12 | 0 |
| HassCore/MediaRemote | 2 | 377/388 | 97.2 | 11 | 0 |
| HassCore/Cameras | 4 | 227/231 | 98.3 | 4 | 0 |
| HassTelemetry | 8 | 510/514 | 99.2 | 4 | 0 |
| HassCore/Climate | 2 | 416/418 | 99.5 | 2 | 0 |
| HassCore/Entities | 8 | 411/413 | 99.5 | 2 | 0 |
| HassCore/Push | 19 | 538/540 | 99.6 | 2 | 0 |
| HassCore/Lights | 1 | 45/46 | 97.8 | 1 | 0 |
| HassCore/Optimism | 1 | 116/117 | 99.1 | 1 | 0 |
| HassCore/Settings | 4 | 331/332 | 99.7 | 1 | 0 |

### LOGIC HassCore/Location (210 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassCore/Location/CoreLocationPlatform.swift | 28/233 | 12.0 | 205 |
| HassCore/Location/LocationPlatform.swift | 0/3 | 0.0 | 3 |
| HassCore/Location/BackgroundRefresh.swift | 49/50 | 98.0 | 1 |
| HassCore/Location/LocationReporter.swift | 422/423 | 99.8 | 1 |

### LOGIC HassCore/Connection (110 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassCore/Connection/HassConnection.swift | 402/472 | 85.2 | 70 |
| HassCore/Connection/LocalServerRoute.swift | 239/264 | 90.5 | 25 |
| HassCore/Connection/HassConnection+Liveness.swift | 29/35 | 82.9 | 6 |
| HassCore/Connection/EntityDeltaEngine.swift | 104/108 | 96.3 | 4 |
| HassCore/Connection/HassConnection+User.swift | 40/43 | 93.0 | 3 |
| HassCore/Connection/ConnectionLifecycle.swift | 33/35 | 94.3 | 2 |

### LOGIC HassCore/Bedroom (69 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassCore/Bedroom/WakeLightContract.swift | 380/403 | 94.3 | 23 |
| HassCore/Bedroom/BedSideController.swift | 623/643 | 96.9 | 20 |
| HassCore/Bedroom/SleepypodSchedule.swift | 274/293 | 93.5 | 19 |
| HassCore/Bedroom/WakeLightController.swift | 214/217 | 98.6 | 3 |
| HassCore/Bedroom/BedroomDevices.swift | 48/50 | 96.0 | 2 |
| HassCore/Bedroom/BedroomConfig.swift | 52/53 | 98.1 | 1 |
| HassCore/Bedroom/HouseholdAwayScope.swift | 58/59 | 98.3 | 1 |

### LOGIC HassCore/Rooms (60 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassCore/Rooms/RoomController.swift | 249/271 | 91.9 | 22 |
| HassCore/Rooms/RoomOverview.swift | 295/308 | 95.8 | 13 |
| HassCore/Rooms/RoomFormat.swift | 138/149 | 92.6 | 11 |
| HassCore/Rooms/RoomModel.swift | 85/92 | 92.4 | 7 |
| HassCore/Rooms/RoomDetailSection.swift | 0/2 | 0.0 | 2 |
| HassCore/Rooms/AirQualityRoom.swift | 0/1 | 0.0 | 1 |
| HassCore/Rooms/RoomGroups.swift | 29/30 | 96.7 | 1 |
| HassCore/Rooms/RoomNavigation.swift | 54/55 | 98.2 | 1 |
| HassCore/Rooms/RoomOverviewKind.swift | 0/1 | 0.0 | 1 |
| HassCore/Rooms/RoomOverviewSection.swift | 4/5 | 80.0 | 1 |

### LOGIC HassCore/Weather (60 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassCore/Weather/WeatherDayBriefingGenerator.swift | 563/589 | 95.6 | 26 |
| HassCore/Weather/WeatherForecastStore.swift | 368/383 | 96.1 | 15 |
| HassCore/Weather/WeatherDates.swift | 37/42 | 88.1 | 5 |
| HassCore/Weather/WeatherPrecipitationTimeline.swift | 94/98 | 95.9 | 4 |
| HassCore/Weather/WeatherHighlights.swift | 143/146 | 97.9 | 3 |
| HassCore/Weather/WeatherFormat.swift | 78/80 | 97.5 | 2 |
| HassCore/Weather/WeatherPresentation.swift | 130/132 | 98.5 | 2 |
| HassCore/Weather/WeatherRails.swift | 40/42 | 95.2 | 2 |
| HassCore/Weather/WeatherBriefingRenderer.swift | 19/20 | 95.0 | 1 |

### LOGIC HassCore/Vacuums (58 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassCore/Vacuums/VacuumController.swift | 546/566 | 96.5 | 20 |
| HassCore/Vacuums/VacuumOutcomes.swift | 434/442 | 98.2 | 8 |
| HassCore/Vacuums/VacuumStatus.swift | 338/346 | 97.7 | 8 |
| HassCore/Vacuums/ValetudoMapFocus.swift | 227/235 | 96.6 | 8 |
| HassCore/Vacuums/VacuumSheetModel.swift | 152/156 | 97.4 | 4 |
| HassCore/Vacuums/ValetudoMap.swift | 253/257 | 98.4 | 4 |
| HassCore/Vacuums/ValetudoMapGeometry.swift | 160/164 | 97.6 | 4 |
| HassCore/Vacuums/VacuumAutoCleanController.swift | 69/70 | 98.6 | 1 |
| HassCore/Vacuums/ValetudoMapLoader.swift | 43/44 | 97.7 | 1 |

### LOGIC HassCore/Auth (45 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassCore/Auth/HassLoginFlow.swift | 117/138 | 84.8 | 21 |
| HassCore/Auth/TokenManager.swift | 12/29 | 41.4 | 17 |
| HassCore/Auth/TokenStore.swift | 58/62 | 93.5 | 4 |
| HassCore/Auth/HassServer.swift | 10/13 | 76.9 | 3 |

### LOGIC HassCore/Profile (45 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassCore/Profile/PersonAvatarSyncer.swift | 197/217 | 90.8 | 20 |
| HassCore/Profile/PersonAvatars.swift | 189/206 | 91.7 | 17 |
| HassCore/Profile/PersonAvatarStore.swift | 122/126 | 96.8 | 4 |
| HassCore/Profile/ProfileSummary.swift | 81/83 | 97.6 | 2 |
| HassCore/Profile/AvatarSyncPlan.swift | 28/29 | 96.6 | 1 |
| HassCore/Profile/SummaryTab.swift | 76/77 | 98.7 | 1 |

### LOGIC HassCore/RoomDevices (39 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassCore/RoomDevices/HumidifierScheduleController.swift | 102/118 | 86.4 | 16 |
| HassCore/RoomDevices/HumidifierSchedule.swift | 210/220 | 95.5 | 10 |
| HassCore/RoomDevices/BathroomFanController.swift | 150/156 | 96.2 | 6 |
| HassCore/RoomDevices/HumidifierController.swift | 208/212 | 98.1 | 4 |
| HassCore/RoomDevices/AirPurifierController.swift | 96/99 | 97.0 | 3 |

### LOGIC HassCore/Config (38 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassCore/Config/VacuumConfig.swift | 55/63 | 87.3 | 8 |
| HassCore/Config/ChoresConfig.swift | 154/160 | 96.2 | 6 |
| HassCore/Config/ClimateConfig.swift | 104/109 | 95.4 | 5 |
| HassCore/Config/HomeConfig.swift | 40/44 | 90.9 | 4 |
| HassCore/Config/MediaRemoteConfig.swift | 122/125 | 97.6 | 3 |
| HassCore/Config/RoomDeviceConfig.swift | 57/60 | 95.0 | 3 |
| HassCore/Config/CustomLightsConfig.swift | 63/65 | 96.9 | 2 |
| HassCore/Config/HouseholdSettingsConfig.swift | 29/31 | 93.5 | 2 |
| HassCore/Config/FoodConfig.swift | 56/57 | 98.2 | 1 |
| HassCore/Config/MediaPageConfig.swift | 70/71 | 98.6 | 1 |
| HassCore/Config/MediaRemotes.swift | 233/234 | 99.6 | 1 |
| HassCore/Config/SecurityConfig.swift | 65/66 | 98.5 | 1 |
| HassCore/Config/VacationConfig.swift | 68/69 | 98.6 | 1 |

### LOGIC HassCore/Recipes (37 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassCore/Recipes/RecipeParsing.swift | 564/588 | 95.9 | 24 |
| HassCore/Recipes/RecipeModels.swift | 217/228 | 95.2 | 11 |
| HassCore/Recipes/RecipeFormatting.swift | 232/234 | 99.1 | 2 |

### LOGIC HassCore/MobileApp (22 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassCore/MobileApp/KeychainMobileAppRegistrationStore.swift | 56/67 | 83.6 | 11 |
| HassCore/MobileApp/PresenceLinker.swift | 74/78 | 94.9 | 4 |
| HassCore/MobileApp/SensorReporter.swift | 98/100 | 98.0 | 2 |
| HassCore/MobileApp/ZonePlanner.swift | 76/78 | 97.4 | 2 |
| HassCore/MobileApp/HAZone.swift | 33/34 | 97.1 | 1 |
| HassCore/MobileApp/MobileAppRegistrationList.swift | 38/39 | 97.4 | 1 |
| HassCore/MobileApp/PendingUnregisterRetrier.swift | 28/29 | 96.6 | 1 |

### LOGIC HassCore/Todo (20 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassCore/Todo/TodoListController.swift | 207/218 | 95.0 | 11 |
| HassCore/Todo/TodoServicing.swift | 50/57 | 87.7 | 7 |
| HassCore/Todo/DonetickTaskForm.swift | 162/164 | 98.8 | 2 |

### LOGIC HassCore/Inventory (19 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassCore/Inventory/ScanItemModel.swift | 615/623 | 98.7 | 8 |
| HassCore/Inventory/InventoryCalendar.swift | 72/77 | 93.5 | 5 |
| HassCore/Inventory/EverShelfFixtureServer.swift | 224/228 | 98.2 | 4 |
| HassCore/Inventory/EverShelfClient.swift | 104/105 | 99.0 | 1 |
| HassCore/Inventory/InventoryCatalog.swift | 368/369 | 99.7 | 1 |

### LOGIC HassCore/Feedback (18 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassCore/Feedback/FeedbackLocationScrubber.swift | 98/105 | 93.3 | 7 |
| HassCore/Feedback/FeedbackMediaFitter.swift | 56/62 | 90.3 | 6 |
| HassCore/Feedback/FeedbackAttachmentPolicy.swift | 32/34 | 94.1 | 2 |
| HassCore/Feedback/URLSessionFeedbackTransport.swift | 6/8 | 75.0 | 2 |
| HassCore/Feedback/HomeAssistantFeedbackClient.swift | 75/76 | 98.7 | 1 |

### LOGIC HassCore/HouseholdAway (18 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassCore/HouseholdAway/HouseholdAwayContract.swift | 190/196 | 96.9 | 6 |
| HassCore/HouseholdAway/SoloTripController.swift | 285/291 | 97.9 | 6 |
| HassCore/HouseholdAway/VacationModeController.swift | 189/192 | 98.4 | 3 |
| HassCore/HouseholdAway/HouseholdAwayController.swift | 196/198 | 99.0 | 2 |
| HassCore/HouseholdAway/SoloTripStatus.swift | 73/74 | 98.6 | 1 |

### LOGIC HassCore/LiveActivity (18 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassCore/LiveActivity/LiveActivityClient.swift | 11/28 | 39.3 | 17 |
| HassCore/LiveActivity/LiveActivityTokenReporter.swift | 124/125 | 99.2 | 1 |

### LOGIC FentonActivityModel (14 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| FentonActivityModel/LiveActivityAction.swift | 5/15 | 33.3 | 10 |
| FentonActivityModel/ActivityCard.swift | 184/186 | 98.9 | 2 |
| FentonActivityModel/ActivityProblem.swift | 68/70 | 97.1 | 2 |

### LOGIC HassCore/Sprinklers (12 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassCore/Sprinklers/SprinklerController.swift | 179/186 | 96.2 | 7 |
| HassCore/Sprinklers/SprinklerFormat.swift | 76/79 | 96.2 | 3 |
| HassCore/Sprinklers/SprinklerSnapshot.swift | 139/141 | 98.6 | 2 |

### LOGIC HassCore/TileActions (12 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassCore/TileActions/MediaTransportActions.swift | 39/41 | 95.1 | 2 |
| HassCore/TileActions/PowerToggleActions.swift | 74/76 | 97.4 | 2 |
| HassCore/TileActions/SprinklerActions.swift | 30/32 | 93.8 | 2 |
| HassCore/TileActions/TileActionCatalog.swift | 125/127 | 98.4 | 2 |
| HassCore/TileActions/AlarmModeActions.swift | 20/21 | 95.2 | 1 |
| HassCore/TileActions/RoomLightsPowerActions.swift | 37/38 | 97.4 | 1 |
| HassCore/TileActions/SourceSelectActions.swift | 60/61 | 98.4 | 1 |
| HassCore/TileActions/TileActionProviding.swift | 0/1 | 0.0 | 1 |

### LOGIC HassCore/MediaRemote (11 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassCore/MediaRemote/MediaRemoteController.swift | 308/319 | 96.6 | 11 |

### LOGIC HassCore/Cameras (4 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassCore/Cameras/CameraStream.swift | 124/127 | 97.6 | 3 |
| HassCore/Cameras/MJPEGChunkStream.swift | 62/63 | 98.4 | 1 |

### LOGIC HassTelemetry (4 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassTelemetry/ResourceCensus.swift | 59/62 | 95.2 | 3 |
| HassTelemetry/MainThreadCostMeter.swift | 120/121 | 99.2 | 1 |

### LOGIC HassCore/Climate (2 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassCore/Climate/ClimateLogic.swift | 313/315 | 99.4 | 2 |

### LOGIC HassCore/Entities (2 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassCore/Entities/EntityState.swift | 23/24 | 95.8 | 1 |
| HassCore/Entities/OptimisticOverlay.swift | 187/188 | 99.5 | 1 |

### LOGIC HassCore/Push (2 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassCore/Push/PushCategory.swift | 74/75 | 98.7 | 1 |
| HassCore/Push/PushLink.swift | 59/60 | 98.3 | 1 |

### LOGIC HassCore/Lights (1 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassCore/Lights/LightControl.swift | 45/46 | 97.8 | 1 |

### LOGIC HassCore/Optimism (1 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassCore/Optimism/OptimisticActions.swift | 116/117 | 99.1 | 1 |

### LOGIC HassCore/Settings (1 uncovered)

| File | Covered / lines | % | Uncovered |
|---|---:|---:|---:|
| HassCore/Settings/HouseholdSettingsController.swift | 154/155 | 99.4 | 1 |
