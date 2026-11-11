# Sleep Together

Shared sleeping for Skyrim Together Reborn (STR) parties, for Skyrim Special Edition / Anniversary Edition.

Status: **0.1.0 first test build.** It compiles and its logic tests pass; it has not been played yet.
See "Known unknowns".

## What it does

On an STR server the server owns the game clock, so sleeping in vanilla Skyrim changes nothing for the
group. That also makes Survival Mode's need for sleep awkward. Sleep Together fixes this:

- When the **party leader** sleeps, the server sets the time of day for **everyone** and sends a chat
  message to all players, for example `[Sleep Together] Name slept. It is now 08:00.`
- If a **non-leader** sleeps, nothing changes except a chat message to that player: `Only the party leader can
  advance time.`
- A player who is **not in a party** can only advance time when they are the only player connected.
- The server accepts at most one advance every 5 seconds.
- The wake-up time is a **fixed hour set in the MCM** (default 08:00) in this first release. The hour you
  pick in the sleep menu is not used yet. The plugin writes `Sleep menu probe:` lines to its log so that
  the place to read it from can be found for a later version.

## Requirements

- Skyrim SE / AE 1.6.1170 or 1.7.104, with SKSE and Address Library
- Skyrim Together Reborn 1.8.4
- STRPluginMessagingAPI and the STRPM Bridge, 0.10.1
- MCM Helper and SkyUI (for the settings menu)
- **The server admin must install the server zip** (see "Install, server admin"). Without it the server
  ignores sleep requests.

## Install, players

1. Install `SleepTogether-0.1.0.zip` with Vortex (or copy its `Data` folder into your Skyrim `Data` folder).
2. Enable `SleepTogether.esp` in your plugin list. It is a small plugin with one quest, no gameplay: MCM Helper
   only lists a mod whose plugin is loaded.
3. Settings are in the SkyUI Mod Configuration Menu under "Sleep Together": on/off, wake hour (0 to 23,
   default 8) and debug logging.

## Install, server admin

`SleepTogether-Server-0.1.0.zip` contains a folder `strpm-chat-relay` with `main.lua` and
`strpm-chat-relay.manifest`.

1. Make a backup copy of your server's `Resources/strpm-chat-relay` folder.
2. Copy the two files from the zip over the files in `Resources/strpm-chat-relay`, replacing them.
3. Restart the server.

Note: any party leader on the server can change the time for everyone (see "Known unknowns"), so only
use this on a server whose players you trust.

Why it replaces the relay instead of being a separate resource: the Sleep Together code is built into the
STRPM chat relay. Server resources load in no fixed order and the relay stops later handlers from seeing a
message, so a separate script could not be made reliable. The relay's name and version are left unchanged
on purpose.

If the relay is updated upstream, the Sleep Together server code has to be built into the new version again:
put the new relay files in `server/upstream/strpm-chat-relay/` and run `python -I tools/build_server_resource.py`
(see `server/upstream/README.md`), then package with `make_archive.bat`.

## Settings and files

- defaults, shipped with the mod: `Data\MCM\Config\SleepTogether\settings.ini`
- your overrides: `Data\MCM\Settings\SleepTogether.ini` (wins over the default)
- log: `Documents\My Games\Skyrim Special Edition\SKSE\SleepTogether.log`

The plugin re-reads the settings about once a second, so changes to the on/off switch and wake hour apply without a restart. The debug logging switch is only
applied when the game loads.

## Known unknowns (test these first)

**Important: the date does not move forward.** The server can only set the time of day. The day, month and
year stay as they were, and the server's Lua API has no way to set the date (the game client only counts
days passed as time ticks by). So if the leader sleeps at 22:00 and the wake hour is 8, the clock goes to
08:00 of the **same** day, 14 hours back. Survival Mode, or any script that measures elapsed game time, may see
little or no sleep. The planned follow-up is a small server patch that adds a `SetDate` binding; it is not done.
Until then this is a test build, and sleeping after midnight with a wake hour later the same day (a
"morning-after" sleep) behaves best.

- Any player can make a party of one and become its leader, so the leader of any party, including a
  stranger's one-person party, can change the time for the whole server. "Only the party leader" does not mean
  "only your friends' party leader". The "only when alone" rule stops a player with no party, but not a
  party-of-one leader. This only matters on a server with other people on it; it is meant for a private server.
- This has not been played yet. Everything here is from reading the code.
- Sleeping in the same bed as another player is untested.
- Whether the time jump looks abrupt in game.
- Whether cancelling a bed activation can still trigger a request. The `Sleep state:` lines in the log show
  the sequence of sleep states.
- The server reads the time scale from `CalendarService`; if that is unavailable it falls back to 20.
- The server's `IsPartyLeader` behaviour was checked in the STR source only.
- The server code has only been tested with stand-in objects, not on a real STR server.

## Troubleshooting

- **Nothing happens when you sleep:**
  - In `SleepTogether.log`, look for `Local sleep started` and `Sleep request sent`. If they are missing,
    check the mod is enabled in the MCM and that the STRPM Bridge is installed.
  - In the server log, look for `[SleepTogether]` lines. If there are none, the relay was not replaced
    (or the server was not restarted).
- **No "Sleep Together" entry in the MCM:** enable `SleepTogether.esp`, make sure MCM Helper is installed, and
  load a save. Then check `Documents\My Games\Skyrim Special Edition\SKSE\MCMHelper.log`: it should list the
  mod, and a line saying the config failed to parse means the config was rejected.

## In-game test list

| Test | Result |
| --- | --- |
| Leader sleeps: time changes for everyone, chat message to all | |
| Non-leader sleeps: time does not change, only they get the "only the party leader" message | |
| Leader sleeps while a non-leader is also in a bed | |
| Two players in the same double bed | |
| A player disconnects during sleep | |
| Leader sleeps twice within 5 seconds: second request is refused | |
| Activate a bed, then cancel the sleep menu without sleeping: does a request go out, does time change? (see the `Sleep state:` lines and the server `[SleepTogether]` lines) | |
| Open the Sleep/Wait menu, move the hours slider, then press Sleep: send the `Sleep menu probe:` lines (needed before the chosen hour can be used) | |
| Sleep in the evening (for example 22:00): after the clock change, check the in-game date, whether days passed changed, and whether Survival fatigue recovered | |
| After the first successful advance: is the server's time scale still what it was configured to? (the handler falls back to 20 if it cannot read it) | |
| If the server log never shows a `[SleepTogether]` line: in the STRPM plugin log, is the backend the STR bridge? (a UDP backend would not reach the STR server) | |

After testing, please send back: `SleepTogether.log`, the `[SleepTogether]` lines from the server log, and the
`Sleep menu probe:` and `Sleep state:` lines from the plugin log.

## Build

Needs Visual Studio (C++), CMake and vcpkg (`VCPKG_ROOT`, default `C:\dev\vcpkg`), Python 3 and a Lua
interpreter for the server tests.

- Plugin: run `build_release.bat` from a Visual Studio x64 developer prompt.
- Server resource: `python -I tools/build_server_resource.py` regenerates `package/Server/strpm-chat-relay`
  from `server/upstream` and `server/sleeptogether`.
- Tests: `lua tests/test_logic.lua`, `lua tests/test_handler.lua`, and the C++ tests with
  `cmake --build out\build-release --config Release --target SleepTogetherTests` then
  `ctest --test-dir out\build-release -C Release --output-on-failure`.
- Zips: `make_archive.bat` writes `dist\SleepTogether-0.1.0.zip` (the `Data` folder) and
  `dist\SleepTogether-Server-0.1.0.zip` (the `strpm-chat-relay` folder). It refuses to run if the DLL lacks the 0.1.0
  version marker, or if the server relay file lacks the Sleep Together handler.

## License

CommonLibSSE-NG is GPL-3.0-or-later and is linked into the plugin, so this plugin is GPL too (see COPYING).
The bundled copy of the STRPM chat relay is MIT upstream (see `server/upstream/README.md`).
