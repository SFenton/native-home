# Journey expectations

Journeys never hold a house's real names, ids or counts. They read what to expect from one type, `JourneyExpectations` (`apple/Apps/iOSUITests/JourneyExpectations.swift`), keyed by role (`bedFirstAlarmSnooze`, `roomBedroomTitle`, `personFirstFullName`, `climateHub`, ...).

## Targets

| Target | Serves | Expectations |
|---|---|---|
| Gallery journeys (`FENTON_GALLERY=...`) | The DEBUG gallery, which draws the synthetic DemoHouse | DemoHouse values, always. |
| Signed-in journeys, hosted CI | The test instance (`HASS_TEST_SERVER`, `HASS_TEST_USERNAME`, `HASS_TEST_PASSWORD`), which serves DemoHouse | DemoHouse values. |
| Signed-in journeys, the owner's house | The live server | Values from the owner's private file. Without it the journey skips. |

## Resolution order

`JourneyExpectations.current(for: .signedIn)`:

1. `FENTON_JOURNEY_EXPECTATIONS` is set: load that JSON file. Unreadable or invalid JSON skips with a reason. A key the file lacks skips the journey (`try expectations.value(.key)`); it never fails on house data.
2. Else `FENTON_JOURNEY_TARGET=demo`, or `FENTON_HASS_SERVER` equal to `HASS_TEST_SERVER`: DemoHouse values. Hosted jobs set one of these.
3. Else `XCTSkip("Live house journeys need FENTON_JOURNEY_EXPECTATIONS ...")`.

`.gallery` skips step 1 to 3 and always answers with DemoHouse (`expectations[.key]` on `JourneyTestCase`).

## What stays literal

System ids stay in the journeys: accessibility identifiers, SF Symbols, Home Assistant built-in services (`light.turn_on`, `button.press`, `climate.set_hvac_mode`), gallery launch ids and the app's own fixed copy ("Light Sync", "HDMI 1", "Volume Up"). A title the app draws from the house config, such as a remote's app tiles (`remote.app.<title>`), is house content and goes through the layer. Only house content moves to the layer: entity ids, script names, room, person, bed and camera titles, page ids. Do not blind-replace; a literal that is the app's own string or a Home Assistant built-in is not house data. The built-in service names the scanner would otherwise read as entities are listed in `allow.object_ids` in `contracts/house_scan.json`.

## The template and the private file

`apple/Apps/iOSUITests/JourneyExpectations.template.json` lists every key with its DemoHouse value and a comment saying what it is. `JourneyExpectationsTests` fails if a key lacks a DemoHouse value or a template comment, or if the template drifts from the table.

To run the signed-in journeys against your own house:

1. Copy the template to a path outside the repository (never inside it; the copy holds your real values and is never committed). As a safety net `.gitignore` ignores `**/JourneyExpectations.json`, `**/JourneyExpectations.local.json`, `*.private.json` and `*.expectations.json`, so a copy saved inside the checkout under one of those names stays untracked; the `.template.json` stays tracked. Name your copy one of those even when it lives elsewhere.
2. Replace each value in `values` with your house's. Keys you leave out make the journeys that need them skip. Unknown keys and the `comments` and `_comment` entries are ignored.
3. Export the path for the run (`TEST_RUNNER_FENTON_JOURNEY_EXPECTATIONS=/path/to/file`; the runner strips the prefix).

Agents never create or read the private file.

## Adding a key

1. Add a case to `JourneyExpectations.Key` with a `///` line, and its DemoHouse value to `demoValues`; take the value from `HassDemoHouse` (`DemoHouseDocument.swift`), not from a real house.
2. Add the key, value and comment to the template.
3. Use `expectations[.key]` in a gallery journey. In a signed-in journey call `try JourneyExpectations.current(for: .signedIn).value(.key)` so it skips on the owner's house without the file.

The house scan (`tools/house_scan.py`, entry `apple/Apps/iOSUITests`) holds the baseline at 0.
