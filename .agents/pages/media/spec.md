# Media

> **What:** platform-neutral spec for the Media page (web route `media`). **Read when:** changing Media on any platform.

Source: `ha-sfenton-react-dash@9ac2a46:src/pages/DashboardViewPage.tsx` `MediaPage` and `mediaPageCardFromItem` (2749-2867), `src/constants/portedDashboard.ts` `MEDIA_SECTIONS` (827), the Studio's `lead-row` and `app-launch` source cards in `src/constants/roomPages.ts` (352-408), `src/constants/surfaceSemantics.ts` `MEDIA_PAGE_REMOTE_HASH_BY_ENTITY_ID` (83). Entry: Home Quick Links "Media" (`atAGlance.ts:257`).

Sections side by side when wide; each is a header, a full-width lead card, then a grid of the rest. Player cards are active on `on` and `playing`.

| Section | Card | Entity | Tap |
|---|---|---|---|
| Living Room | Living Room Streamer (`mdi:television`, off icon `mdi:television-off`) | `media_player.demo_living_room_1` | Living Room Streamer remote |
| Studio | Studio Remote | `media_player.demo_studio_1` | Studio remote |
| | Game Console (on for Game Console or Game) | `sensor.demo_studio_source_1` | active: `script.demo_ext_7`, else `script.demo_game_1` |
| | Server | same | active: `script.demo_ext_7`, else `script.demo_ext_8` |
| | Computer | same | active: `script.demo_ext_7`, else `script.demo_ext_9` |
| | Game (Quick App Launch) | same | `script.demo_game_2` |
| Media Room | Media Room | `media_player.demo_media_player_2` | Media Room Streamer remote |
| | Handheld Console | `input_boolean.demo_switch_1` | `script.demo_ext_10` (no target) |
| | Media Room Streamer | `input_boolean.demo_input_boolean_5` | `script.demo_ext_11` (no target) |

Studio scripts carry the remote's optimistic intents (see [media-remote](../../patterns/media-remote.md)); the page and the Studio remote share them. Source cards read "On" for their own source and "Off" otherwise. The Primary Bedroom Streamer is not on this page (web parity).
