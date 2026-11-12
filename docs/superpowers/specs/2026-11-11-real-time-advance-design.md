# Sleep Together v2: make time really advance, like a vanilla sleep

Status: **design, awaiting approval. Nothing is built.** Items marked *(my call)* were decided by the designer. Items marked *(unverified)* are assumptions to check before relying on them. Extends `2026-11-11-sleep-together-design.md`.

## Why (from the 0.1.1 in-game test, real log data)

- The trigger works: pressing Sleep sent a request and the server changed the clock.
- But the request was always "wake at 08:00", whatever the player chose. With 1 hour chosen at 13:39 the clock went **back** to 08:01; with about 7 hours chosen at 08:13 nothing visible happened.
- The sleep menu counts its chosen hours down at one hour per second, while the game hour stayed at 08:01 to 08:03. Nothing passed, so nothing could heal or reset.
- Cause: the server's `SetTime` only sets the time of day (no date rollover), the client's "days passed" only grows with normal ticking, and Lua has no way to read or advance the time properly.
- The slider is `HoursSlider._value` (1 to 24, counts down while sleeping). Confirmed in the log, not guessed.

## Goal

A shared sleep that behaves like a vanilla one as far as STR allows:
1. The hours the leader chose in the menu are honoured. If the leader does not touch the slider, the default applies: sleep **until 08:00**. A setting turns that default on or off (off = always use the slider).
2. Time **advances forward** by that much on the server, with correct date rollover, at the same pace as the menu (one game hour per second).
3. Every player's game counts the elapsed time as days passed, so vendors restock and time-based effects see it.
4. Players recover when it ends: health, magicka and stamina are restored (setting, default on).
5. Cancelling the sleep menu early stops the advance at that point.

## Non-goals

- The vanilla fast-forward world simulation (NPC schedules played out, crop growth, etc.): STR blocks it and it cannot be restored without patching the STR client. Anything driven by the clock follows it naturally.
- Voting, "everyone in a bed" gating, Lover's Embrace, changes to Survival Mode itself.

## Design

**Plugin (every player).**
- Remember the slider value when the sleep menu opens. At the Sleep press: hours = round(`_value`) clamped 1 to 24; "explicit" = the value differs from the one at open. *(my call)*
- Send to the server: `STv2|HOURS|<n>` when the slider was moved, or the default is disabled; otherwise `STv2|UNTIL|<wake hour>`. If the menu closes while sleeping before the countdown ends, send `STv2|WAKE`.
- Receive from the server: `STv2|STEP|<hours>` adds `hours/24` to the game's days-passed global (`GameDaysPassed`); `STv2|DONE|<hours>` restores the local player's health, magicka and stamina if the setting is on. *(unverified: writing that global and restoring values from a plugin)*
- MCM: `bUseDefaultWake` (default on), `iWakeHour` (default 8), `bRestoreStats` (default on), plus the existing enable and debug toggles.

**Server (Lua, built into the relay as now).**
- Same validation as v1: sender must be the party leader (or alone), clients are never trusted.
- One sleep at a time; further requests while one runs are ignored.
- `UNTIL`: asks the server how many hours until that hour next occurs. `HOURS`: uses `n`.
- Steps the advance from the server's `onUpdate` event at one game hour per real second (the last step may be partial): each step advances the server clock and sends `STEP` to everyone. At the end, or on `WAKE`, it sends `DONE` and the existing chat message (`[Sleep Together] <name> slept. It is now HH:00.`).

**Server patch (your `TiltedEvolution` fork, small).**
- New Lua functions on `CalendarService`: `AdvanceHours(hours)` (adds time with day, month and year rollover using the existing `DateTime` logic, then resyncs all clients) and `HoursUntil(hour)` (hours until the clock next reads that hour; 24 if it is exactly that hour). The pure date logic gets unit tests.
- Delivered as a branch plus a `.patch` file kept in the Sleep Together repo; you rebuild and redeploy your server image. *(my call: I do not know which fork branch your image is built from, so the patch is a standalone commit that applies to a clean base)*
- Clients follow the server's date only if the server setting `SyncPlayerCalendar` is on. Document it. *(unverified for your server)*

**Server to client messages.** The relay already builds STRPM envelopes. Server-originated ones (`STEP`, `DONE`) must be accepted by the client bridge. *(unverified: check the bridge source first; fallback is parsing the visible chat line)*

## Constraints

- Whole-hour requests, validated server-side: hours 1 to 24, wake hour 0 to 23; same rate limit and leader rules as v1.
- Version bump for every zip (0.2.0). Commit as the noreply identity. Nothing is published without approval. Only verified claims in the README.
- The first test run after the patch needs a rebuilt server image; the README must say so.

## Known unknowns (test in game)

Whether vendors actually restock after a shared sleep; whether Survival fatigue recovers; whether the date follows on clients; how smooth the one-hour-per-second clock looks; whether restoring stats is a good match for vanilla regeneration.
