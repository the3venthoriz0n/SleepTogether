# Sleep Together

Shared sleeping for Skyrim Together Reborn (STR) parties, for Skyrim Special Edition / Anniversary Edition.

Status: **0.2.0 test build.** It compiles, and its logic tests pass (C++ tests, Lua tests, and a check of the
server's date arithmetic). **It has not been tried in game**, and the patched server it needs has never been built
or run. See "Known unknowns".

## What it does

On an STR server the server owns the game clock, so sleeping in vanilla Skyrim changed nothing for the group.
Sleep Together fixes this:

- The **party leader** sleeps in a bed and presses Sleep in the Sleep/Wait menu.
  - If the leader **moved the hours slider**, that many hours pass.
  - If the leader **left the slider alone**, everyone sleeps until the **wake-up hour** (default 08:00). This
    can be turned off in the MCM, so that the slider is always used.
- The server steps the clock forward at **one game hour per real second**, with correct rollover of the date
  (day, month, year).
- Every player's **days-passed counter** is advanced by the same amount, so game systems that measure elapsed
  time see it.
- At the end, **health, magicka and stamina are restored** (MCM option).
- A chat message tells everyone who slept and for how many hours, for example
  `[Sleep Together] Name slept for 8 hours.`
- If a **non-leader** tries, nothing changes except a chat message to that player: `[Sleep Together] Only the
  party leader can advance time.`
- A player who is **not in a party** can only advance time when they are the only player connected.
- At most one advance every 5 seconds on the server, and the plugin sends at most one request every 3 seconds.
  While an advance is running, further requests are ignored.
- Trigger: the request is sent when the player presses Sleep in the Sleep/Wait menu (the menu opened from a
  bed, with its Sleep button pressed). Opening the menu and cancelling does not send anything. The plugin
  checks about every 100 ms.

### Why

STR's server owns the clock, and vanilla sleeping did nothing to it. That also makes Survival Mode's need for
sleep awkward.

### What it does NOT do

- It does **not fast-forward the world simulation** like a vanilla sleep. Only the clock and the days-passed
  counters move. Anything driven by the clock follows, anything that needs the simulation to run does not.
- If the leader **cancels in the middle of the sleep**, nothing stops the advance: it always runs to the end.
  Early wake-up is not handled.
- There is **no voting**: the party leader decides for everyone.

## Requirements

- Skyrim SE / AE 1.6.1170 or 1.7.104, with SKSE and Address Library
- Skyrim Together Reborn 1.8.4
- STRPluginMessagingAPI and the STRPM Bridge, 0.10.1
- MCM Helper and SkyUI (for the settings menu)
- **A server built from the patched fork branch** (see "Install, server admin"). The stock server cannot advance
  the date, and without the new relay the server ignores sleep requests.

## Install, players

1. Install `SleepTogether-0.2.0.zip` with Vortex (or copy its `Data` folder into your Skyrim `Data` folder).
2. Enable `SleepTogether.esp` in your plugin list. It is a small plugin with one quest, no gameplay: MCM Helper
   only lists a mod whose plugin is loaded.
3. Settings are in the SkyUI Mod Configuration Menu under "Sleep Together":
   - **Enable Sleep Together** (on/off)
   - **Wake hour** (0 to 23, default 8)
   - **Sleep until the wake-up hour unless I move the slider** (on by default; off means the slider is always
     used)
   - **Restore health, magicka and stamina after a shared sleep** (on by default)
   - **Debug logging**

## Install, server admin

**Two things are required, and both must be done: the patched server image AND the new relay.**

### a) Run the patched server image (`:sleep`)

The server must run the patched image. Pushing the branch `sleep-time-advance` in the fork
`the3venthoriz0n/TiltedEvolution` builds `ghcr.io/<owner>/st-reborn-server:sleep` with GitHub Actions (about 40+
minutes, amd64 only). The branch is `player-inventory-transfers` plus three commits; the same changes are in
`server/patches` as three patch files (see `server/patches/README.md`). Point the server at the `:sleep` image
and restart.

**Rollback:** point the server back at `ghcr.io/<owner>/st-reborn-server:patched` and restart. The workflow never
writes the `:patched` tag.

### b) Calendar sync setting

In `STServer.ini`, under `[Gameplay]`, set:

    bSyncPlayerCalendar=true

so that clients' dates follow the server's. (The owner has already turned this on.)

### c) Replace the relay

`SleepTogether-Server-0.2.0.zip` contains a folder `strpm-chat-relay` with `main.lua` and
`strpm-chat-relay.manifest`.

1. Make a backup copy of your server's `Resources/strpm-chat-relay` folder.
2. Copy the two files from the zip over the files in `Resources/strpm-chat-relay`, replacing them.
3. Restart the server.

The Sleep Together code is built into the STRPM chat relay. Server resources load in no fixed order and the
relay stops later handlers from seeing a message, so a separate script could not be made reliable. The relay's
name and version are left unchanged on purpose.

If the relay is updated upstream, the Sleep Together server code has to be built into the new version again: put
the new relay files in `server/upstream/strpm-chat-relay/` and run `python -I tools/build_server_resource.py`
(see `server/upstream/README.md`), then package with `make_archive.bat`.

Note: any party leader on the server can change the time for everyone (see "Known unknowns"), so only use this on
a server whose players you trust.

## Settings and files

- defaults, shipped with the mod: `Data\MCM\Config\SleepTogether\settings.ini` (`bEnabled`, `iWakeHour`,
  `bUseDefaultWake`, `bRestoreStats`, `bDebug`, all under `[General]`)
- your overrides: `Data\MCM\Settings\SleepTogether.ini` (wins over the default)
- log: `Documents\My Games\Skyrim Special Edition\SKSE\SleepTogether.log`

The plugin re-reads the settings about once a second, so changes apply without a restart. The debug logging
switch is only applied when the game loads.

## Log lines to expect

Plugin log (`SleepTogether.log`), in this order for one sleep:

- `Local sleep started (initial slider ..., at press ...), requested HOURS 8` or `... requested UNTIL 8`: the
  plugin saw Sleep pressed. "initial slider" is the slider when the menu opened, "at press" is when Sleep was
  pressed (`unreadable` if it could not be read).
- `Sleep request sent STv2|HOURS|8` (or `STv2|UNTIL|8`): the request went to the STRPM bridge.
- `Sleep step +1000 milli-hours (days passed now ...)`: one per game hour, as the server steps.
- `Sleep done 8000 milli-hours, restored health +..., magicka +..., stamina +...` (or `restored nothing (all stats
  already full)`, or `stat restore disabled`).
- Other lines you may see: `Sleep request throttled`, `Sleep started but Sleep Together is disabled`,
  `Sleep step ignored: calendar or days-passed global not available`.
- `Sleep menu probe:` and `Sleep state:` lines are a leftover diagnostic and can be ignored.

Server log:

- `[SleepTogether] <name> sleeps for <hours> h`
- `[SleepTogether] deny (not_leader)`, `[SleepTogether] ignored request (busy)` or `(rate_limited)`
- `[SleepTogether] Error: ...` lines mean something failed (for example `AdvanceHours failed`).

## Troubleshooting

- **Nothing happens when you sleep:**
  - In `SleepTogether.log`, look for `Local sleep started` (the plugin saw Sleep pressed) and `Sleep request sent`
    (the request went to the STRPM bridge). If the first is missing, send the `Sleep menu probe:` lines. If only
    the second is missing, check the mod is enabled in the MCM and that the STRPM Bridge is installed and
    connected. In the STRPM plugin log, the backend must be the STR bridge (a UDP backend would not reach the
    STR server).
  - In the server log, look for `[SleepTogether]` lines. If there are none, the relay was not replaced (or the
    server was not restarted).
  - Check that the server really runs the `:sleep` image. With the stock image, advancing fails with an
    `[SleepTogether] Error: ...` line.
- **Time does not advance, or the date does not follow:** check the server settings, in particular
  `bSyncPlayerCalendar=true` under `[Gameplay]` and the time scale.
- **No "Sleep Together" entry in the MCM:** enable `SleepTogether.esp`, make sure MCM Helper is installed, and
  load a save. Then check `Documents\My Games\Skyrim Special Edition\SKSE\MCMHelper.log`: it should list the
  mod, and a line saying the config failed to parse means the config was rejected.

## Known unknowns (test these first)

**Nothing in this release has been tried in game.** The 0.1.0 build was tried once (plugin loads, STRPM link
works, its trigger did not fire); the trigger and everything after it are untested. In detail:

- The patched server image and the new Lua calendar bindings have **never been built or run on a real server**.
  The date arithmetic was only tested by a stand-alone check (`tools\server-verify`), the server Lua only with
  stand-in objects. The patch was checked with a local `git am` only.
- Whether the date really follows on clients needs `bSyncPlayerCalendar=true` and is unverified.
- How the stepped clock (one game hour per real second) looks in game is unverified.
- Vendors restocking after a long sleep is unverified.
- Whether Survival Mode fatigue recovers after a shared sleep is unverified.
- The stat restore is an approximation of vanilla regeneration (it fills health, magicka and stamina).
- The hours slider's value is read from its `_value` member. That member name was observed in the owner's game
  log, but reading the slider has not been tested in a full sleep.
- Any player can make a party of one and become its leader, so the leader of any party, including a stranger's
  one-person party, can change the time for the whole server. "Only the party leader" does not mean "only your
  friends' party leader". The "only when alone" rule stops a player with no party, but not a party-of-one leader.
  This only matters on a server with other people on it; it is meant for a private server.
- Sleeping in the same bed as another player is untested.
- The server's `IsPartyLeader` behaviour was checked in the STR source only.

## In-game test list

| Test | Result |
| --- | --- |
| Leader sleeps with the slider moved (for example to 3): that many hours pass for everyone, chat message names the hours | |
| Leader sleeps with the slider untouched: everyone sleeps until 08:00 | |
| "Sleep until the wake-up hour" option turned off: the slider is always used, even if untouched | |
| Sleeping past midnight: the date advances for everyone (check the date on a second client) | |
| A non-leader tries: time does not change, only they get the "only the party leader" message | |
| Two requests close together (within 5 seconds): the second is ignored | |
| A player joins in the middle of a sleep | |
| Vendors after a long sleep (48+ hours in total): do they restock? | |
| Survival fatigue and health, magicka, stamina after sleeping | |
| Two players in the same double bed | |
| A player disconnects during the sleep | |
| Leader cancels in the middle of the sleep (expected: the server advance continues to the end) | |

After testing, please send back: `SleepTogether.log`, the `[SleepTogether]` lines from the server log, and (if the
trigger misbehaves) the `Sleep menu probe:` and `Sleep state:` lines from the plugin log.

## Build

Needs Visual Studio (C++), CMake and vcpkg (`VCPKG_ROOT`, default `C:\dev\vcpkg`), Python 3 and a Lua
interpreter for the server tests.

- Plugin: run `build_release.bat` from a Visual Studio x64 developer prompt.
- Server resource: `python -I tools/build_server_resource.py` regenerates `package/Server/strpm-chat-relay`
  from `server/upstream` and `server/sleeptogether`.
- Tests: `lua tests/test_logic.lua`, `lua tests/test_handler.lua`, and the C++ tests with
  `cmake --build out\build-release --config Release --target SleepTogetherTests` then
  `ctest --test-dir out\build-release -C Release --output-on-failure`.
- Server date arithmetic check: `powershell -File tools\server-verify\run.ps1`.
- Zips: `make_archive.bat` writes `dist\SleepTogether-0.2.0.zip` (the `Data` folder) and
  `dist\SleepTogether-Server-0.2.0.zip` (the `strpm-chat-relay` folder). It refuses to run if the DLL lacks the
  0.2.0 version marker, or if the server relay file lacks the Sleep Together handler.

## License

CommonLibSSE-NG is GPL-3.0-or-later and is linked into the plugin, so this plugin is GPL too (see COPYING).
The bundled copy of the STRPM chat relay is MIT upstream (see `server/upstream/README.md`).
