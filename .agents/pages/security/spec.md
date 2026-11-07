# Security

> **What:** platform-neutral spec for the Security page. **Read when:** changing Security on any platform.

Source: `ha-sfenton-react-dash@9ac2a46:src/components/hass/SecurityDashboard.tsx`, `SecurityControls.tsx`, `GarageDoorTile.tsx`, `useGarageDoorCommand.ts`; config in `src/constants/securityPage.ts` and `src/constants/garageDoors.ts`.

## Layout, top to bottom

1. Title "Security".
2. Status rail (`SECURITY_STATUS_CHIPS`): Security (alarm state; opens the security system sheet) and Contact Sensors ("N open"; opens the contact list).
3. Section "Security" (`SECURITY_CONTROL_TILES`):

| Tile | Entity | Shows | Tap |
|---|---|---|---|
| Security System | `alarm_control_panel.demo_alarm_control_panel_1` | mode, icon per mode | opens the security system sheet |
| Front Door | `lock.demo_lock_2` | lock state | `lock.lock` when unlocked/unlocking, else `lock.unlock` |
| Left Door | `cover.demo_garage_door_1` | door state or command feedback | garage door command (below) |
| Right Door | `cover.demo_garage_door_2` | door state or command feedback | garage door command (below) |

4. Guest presence section while a guest toggle is on (shared with Home).
5. Cameras (shared with Home).
6. Section "Vehicle": Doors (`lock.demo_lock_1`). **Hidden**, as on the web (`SHOW_MACHE_SECTION = false`); the native gallery shows it so it stays tested.

Tile tones: closed/locked/disarmed green, armed or moving blue, open/unlocked/jammed/failed red, unavailable dimmed.

## Security system sheet

Four modes: Home (`alarm_arm_home`), Away (`alarm_arm_away`), Night (`alarm_arm_night`), Disarmed (`alarm_disarm`), all on the alarm panel, no code. The current mode is selected in its color (home blue, away red, night purple, disarmed green). Native departures (HIG: Alerts): **Disarmed asks for confirmation** ("Disarm the security system?", Disarm / Cancel); tapping the current mode sends nothing.

## Garage door command

`closed`/`closing` → `cover.open_cover` (shows `opening`); `open`/`opening` → `cover.close_cover` (shows `closing`); any other state is unavailable.

| Time | Behavior |
|---|---|
| Tap | Tile reads "Sending Open…" / "Sending Close…"; taps ignored |
| ≥ 1 s and acknowledged | Back to the shown (optimistic) state, waiting for the door |
| ≥ 2 s and acknowledged | Taps accepted again |
| Not acknowledged in 10 s, call error, connection lost or offline, or no live change in 45 s | "Error" in red for 8 s, optimistic state dropped |
| Any live state change | Request ends; tile follows Home Assistant |

VoiceOver announces the feedback text.
