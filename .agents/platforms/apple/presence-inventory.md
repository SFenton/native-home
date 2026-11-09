# Presence inventory

> **What:** what Home Assistant does with presence, so the native app's `device_tracker` is added without surprises. **Read when:** linking the app's tracker to a person, changing `HassCore/Location`, or planning the shadow-to-live switch in [location.md](location.md).

This is a pattern-level inventory. It was first taken from a live read-only survey of the owner's server (states, registries, person, zone, automation and script configs) on 2026-10-15; the house-specific listing stays out of the repo. Ids below are demo ids (`demo_` prefix), and the owner's local config holds the real ones. Coordinates are never recorded.

## Zones

| Zone | Passive | Used by |
|---|---|---|
| `zone.home` | no | Home/Away, the household presence group, most presence automations |
| a per-person workplace zone | no | The person's state shows the zone name while inside |
| store or errand zones | yes | Location-based notifications (zone trigger) |

Passive zones do not set a tracker's state; they only produce zone triggers and `in_zones`. The native `ZonePlanner` skips passive zones, so those zones are not monitored by the app's regions and any automation that relies on them keeps relying on the official app. A small home radius is padded to 100 m for the iOS region, per the location rules.

## People and trackers

| Person | `source` | Linked trackers (person order) |
|---|---|---|
| `person.demo_resident_1` | `device_tracker.demo_phone_1` | the official app's tracker, this app's tracker, simulator trackers |
| `person.demo_resident_2` | `device_tracker.demo_phone_2` | the official app's tracker |

| Tracker kind | Integration | Linked to | Notes |
|---|---|---|---|
| Official app tracker | mobile_app | a person | Live (battery, GPS accuracy of a few metres). Usually the person's current source |
| This app's registration | mobile_app | a person | `unknown` until the app sends a location |
| Simulator registration | mobile_app | possibly a real person | Debug and emulator registrations; linked automatically when signed in as that person |
| A previous phone or an iPad | mobile_app | nobody | Stale after the last HA restart |
| A car tracker | car integration | nobody | Used by garage or journey automations |

People normally use `gps` trackers only. Home Assistant's person entity follows the most recently updated GPS tracker among those linked to it, ignoring `unknown` and `unavailable`.

## household_presence

| Item | Value |
|---|---|
| Entity | `group.demo_household_presence` (defined in `configuration.yaml`) |
| Members | the household's person entities |
| Rule | `all: false`: home if any person is home |

Automations treat `home` to `not_home` (after a delay) as "everyone left" and `not_home` to `home` as "first person back".

## Thermostat Home/Away

| Item | Value |
|---|---|
| `sensor.demo_away_1` | A UI template helper (config entry, platform `template`), not in YAML. Its state is `Home` or `Away` |
| Consumer | A thermostat-with-contact-sensors custom component with an away-presence entity option and a vacation-mode entity; away is presence away or Vacation Mode on |
| Effect of away | Heat target a few degrees lower, cool target a few degrees higher by default; predictive comfort is skipped while away unless allowed |

Not verified from outside: the helper's template and the entity the component is configured with. Both live in `.storage` config entry options, which the Home Assistant config rules forbid reading, and opening an options flow is a write call. Read the template in Settings, Devices and services, Helpers before relying on the exact inputs.

## Automations and scripts that use presence

A typical house has many automation and script configs that read presence. The kinds that matter for the app's tracker:

| Kind | Presence use |
|---|---|
| Everyone-away automation | Trigger: household presence home to not_home for a delay. Action: arm the alarm away, lock doors, close covers, switch off conveniences, resume lighting. Skips with a notification when a guest-stay toggle is on |
| First-person-back automation | Trigger: household presence not_home to home for a few seconds. Action: arm the alarm home, restore conveniences |
| Arrival failsafe | Condition: group not_home with a recognized person at the opened door; waits for the group to go home |
| Door lifecycle and ownership | Group state, members and `last_changed` decide who owns a door notice; may check a person's `user_id` on notification acknowledgements |
| Bedtime and daytime recovery | Group home to not_home for a delay ends the routine |
| Chore reminders | Triggers: each person to home; condition: that person home at a given time |
| Location-based notifications | Zone triggers: a person entering passive zones; clears on leaving |
| Vacuum coordinator | `people:` lists the persons; starts cleaning after all are away for a delay |
| Journey recorder | Trigger and action on one hard-coded `device_tracker` entity |
| Trip scripts | Read a traveler person's state while a trip is active |

Custom components also read presence: a household component maps persons to their `mobile_app` registrations for notify targets, and an occupancy component can take a person entity per area.

## mobile_app registrations

A typical set: each person's official-app phone, this app's registration per person, any older phone, an iPad, several simulator and emulator registrations. Debug builds register with a `debug_` identifier prefix. The registry does not show which Home Assistant user owns each one; the person to user mapping is in `person` (`user_id`).

## What this means for the native app's tracker

- **It sits beside the official tracker.** The app's tracker is linked to the person behind the official one. While it is `unknown` it is ignored; the first location it sends makes it a candidate for the person's source.
- **Linking changes the person source.** Once it reports, the person follows whichever of the two trackers updated last, so a stale, noisy or differently-timed native fix can flip a person between home and not_home. Shadow mode should keep reports from reaching the person until the app has matched the official tracker on real trips.
- **Away is expensive.** If everyone reads not_home, the household presence group goes not_home and Home Assistant arms the alarm away, locks doors, closes covers, switches off conveniences and starts vacuum runs; the thermostat component may also move its targets. With one person already away, the other going not_home (from a bad native fix) would trigger all of it.
- **Simulators are linked to a person.** A simulator that reports a location (for example a simulated drive) can move that person. Unlink simulator trackers, or keep the simulator on the no-report path, before the reporter is turned on.
- **Hard-coded tracker.** An automation that triggers on one `device_tracker` entity directly will not see the native tracker even after it is linked. Journey automations work from person state otherwise.
- **iPad and old phone stay unlinked.** The iPad must not be linked to a person (see the `isPresenceDevice` rule in [location.md](location.md)); a previous phone is stale.

## Update 2026-10-20

The app now reports whenever location is allowed and adds its tracker to the signed-in user's person on sign-in (admin or owner; see [location](location.md), Presence link). Shadow mode and the Report toggle are gone, so a simulator or a second phone signed in as an admin is linked to that person too: keep simulators off the registration path (`MobileAppRegistrationPolicy`).
