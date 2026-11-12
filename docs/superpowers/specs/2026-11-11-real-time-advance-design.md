# Sleep Together v2: make time really advance, like a vanilla sleep

Status: **design (revised after verification), awaiting approval. Nothing is built.** Items marked *(my call)* were decided by the designer. Items marked *(unverified)* can only be checked in the game or on a real server. Extends `2026-11-11-sleep-together-design.md`.

## Why (from the 0.1.1 in-game test, real log data)

- The trigger works: pressing Sleep sent a request and the server changed the clock.
- But the request was always "wake at 08:00", whatever the player chose. With 1 hour chosen at 13:39 the clock went **back** to 08:01; with about 7 hours chosen at 08:13 nothing visible happened.
- The sleep menu counts its chosen hours down at one game hour per second, while the game hour stayed at 08:01 to 08:03. Nothing passed, so nothing could heal or reset.
- Cause: the server's `SetTime` only sets the time of day (no date rollover); the client's days-passed counter only grows with normal ticking; Lua can neither read nor properly advance the time.
- The slider is `HoursSlider._value` (1 to 24, counts down while sleeping). Confirmed in the log.
- The clock "racing" right after joining is STR's join transition (it slides the client clock toward the server's over 5 s), not this mod.

## Goal

A shared sleep that behaves like a vanilla one as far as STR allows:
1. The hours the leader chose in the menu are honoured. If the leader does not touch the slider, the default applies: sleep **until 08:00**. A setting turns that default on or off (off = always use the slider).
2. Time **advances forward** on the server, with correct date rollover, at the menu's pace (one game hour per second).
3. Every player's game counts the elapsed time as days passed.
4. Players recover when it ends (health, magicka, stamina restored; setting, default on).

## Non-goals

- The vanilla fast-forward world simulation (NPC routines played out, crop growth): STR blocks it; fixing that means patching the STR client. Anything driven by the clock follows it.
- Early wake when the leader cancels mid-sleep (there is no verified signal for it yet; the advance always runs to completion). Revisit after a cancel test.
- Voting, "everyone in a bed" gating, Lover's Embrace, changes to Survival Mode.

## What was verified (and how)

| Item | Result | Source |
|---|---|---|
| Plugin can write the days-passed counter | Yes: `Calendar::GetSingleton()->gameDaysPassed` is a `TESGlobal*` with a writable `float value`; `GetCurrentGameTime()` reads it; STR's client updates the same global every tick | CommonLibSSE-NG `Calendar.cpp`, STR `client/Services/Generic/CalendarService.cpp` |
| Plugin can restore health/magicka/stamina | API exists: `ActorValueOwner::RestoreActorValue(av, amount)` and `Actor::GetActorValueMax(av)`; full restore = max minus current | CommonLibSSE-NG headers |
| Vendors restock off that counter | **Unverified** (needs the game) | |
| Server-built messages reach the client plugin | Yes, if the envelope has `msg`, `seq`, `channel`, `flags`, `part=1`, `parts=1`, `payload` (uppercase hex) and a **nonzero numeric `sender`**; the bridge does not check the sender's identity; messages are keyed by sender plus `msg`, so each needs a unique `msg`; they arrive on the bridge's own thread | STRPM `STRPluginMessagingBridgeReceive.cpp` |
| A rogue client could forge such messages | **Yes** through the relay, because the relay forwards `target=all` envelopes: the server hook must stop the relay from forwarding anything on our channel that came from a client | relay `main.lua` |
| Lua `onUpdate` gives real seconds | Yes, `UpdateEvent.Delta` is a float of seconds | `server/GameServer.cpp` |
| Server date rollover logic exists | Yes, in `DateTime::Update` (carry day, month, year) | `Code/common/DateTime.cpp` |
| Clients follow the server date | Only when the server setting `bSyncPlayerCalendar` is **true**; the default is **false** | `Code/server/GameServer.cpp`, client `CalendarService.cpp` |
| Version check | Strict equality: the server kicks clients whose version string differs from its own build tag | `Code/server/GameServer.cpp:789` |
| Which fork branch to build from | **`player-inventory-transfers`**: it builds as `v1.8.4` (matches stock clients) and is the `:patched` image PartyInventory uses. `potion-sync` builds as `v1.8.4-potions1` and stock clients cannot join it | the two workflow files |
| Server can be built here | **No**: Docker Desktop is not running and the image is built by GitHub Actions (60 min limit) | |

## Design

**Plugin (every player).**
- Remember the slider value when the sleep menu opens. At the Sleep press: hours = round(`_value`) clamped 1 to 24; "explicit" = the value differs from the one at open. *(my call)*
- Send to the server on channel `sleeptogether.v1` (target server): `STv2|HOURS|<n>` when the slider was moved or the default is disabled; otherwise `STv2|UNTIL|<wake hour>`.
- Receive `STv2|STEP|<hours>`: add `hours/24` to `gameDaysPassed->value`. Receive `STv2|DONE|<hours>`: restore the local player's health, magicka and stamina if the setting is on. The receive callback runs on the bridge thread, so game state is touched only inside `SKSE::GetTaskInterface()->AddTask`.
- MCM (top level): `bUseDefaultWake` (default on), `iWakeHour` (default 8), `bRestoreStats` (default on), plus the existing enable and debug toggles.

**Server resource (Lua, built into the relay as now).**
- Same validation as v1: sender must be the party leader (or alone); clients are never trusted. One sleep at a time; requests while one runs are ignored.
- The relay hook now **returns "handled"** for our channel, so nothing a client sends on it is ever forwarded to other players. *(closes the forgery hole)*
- `UNTIL h`: hours = `CalendarService:get():HoursUntil(h)`. `HOURS n`: hours = n.
- A session steps from `onUpdate`, accumulating `Delta` seconds, one game hour per real second (the last step may be partial): each step calls `AdvanceHours(step)` and sends `STEP` to every connected player, as a server-built envelope naming the leader's connection id as `sender` and a unique `msg`. At the end it sends `DONE` and the existing chat message (`[Sleep Together] <name> slept. It is now HH:00.`).

**Server patch (fork branch `sleep-time-advance`, from `player-inventory-transfers`).**
- `DateTime`: new `AdvanceHours(float)` and `HoursUntil(int) const`; the carry code moves into one private helper used by both `Update` and `AdvanceHours`, so normal ticking keeps its behaviour. Pure logic, unit tested.
- `server/Services/CalendarService`: `bool AdvanceHours(float)` (accepts 0 < hours <= 24, advances, then resyncs all loaded players with the existing `SendTimeResync`) and `float HoursUntil(int) const` (-1 for an invalid hour).
- `server/Scripting/Services/CalendarService_Bindings.cpp`: `AdvanceHours` and `HoursUntil` bound as member functions taking `CalendarService&`, called from Lua as `CalendarService:get():AdvanceHours(x)`.
- CI: the workflow builds this branch to a **separate image tag** (`:sleep`), with `VERSION_OVERRIDE=v1.8.4` (so stock clients still join) and never touches `:patched`; roll back by pointing the server at `:patched` again.
- Testing without a full build: the new `DateTime` test file mirrors the existing `playback_clock.cpp` precedent in `Code/tests` (the image build compiles that target), and is first compiled and run locally against a stub of the Catch2 and TiltedCore headers, so a mistake shows up here and not 40 minutes into a CI run. Everything else on the server side copies existing code patterns line for line and is reviewed against the sources.
- Server settings needed: `bSyncPlayerCalendar=true` in `STServer.ini` `[Gameplay]` (documented; without it clients' dates do not follow, only days-passed and time of day do).

## Constraints

- Whole-hour request values validated server-side: HOURS 1 to 24, UNTIL 0 to 23; same leader and rate rules as v1.
- Plugin version bump to 0.2.0. Commit as the noreply identity. Nothing is published or pushed without approval. Only verified claims in the README.
- Zero guesses on server APIs: every Lua and C++ call used is one that exists in the checked-out source (checked by reading, listed in the plan).

## Known unknowns (test in game)

Whether vendors restock after a shared sleep; whether Survival fatigue recovers; whether the date follows on clients; how the one-hour-per-second clock looks; whether restoring stats matches vanilla regeneration; whether `GetTimeScale`-style bindings called with `:` work (the new bindings avoid the question by taking `self`).
