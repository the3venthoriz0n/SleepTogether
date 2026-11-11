# Sleep Together Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When the party leader sleeps on a Skyrim Together Reborn server, the server sets the time for everyone; everyone else gets a message; non-leaders who try are told only the leader can.

**Architecture:** An SKSE plugin (C++, CommonLibSSE-NG) notices the local player starting to sleep and sends one STRPM message to the server. A Lua resource on the server checks the sender is the party leader, calls `GameServer:SetTime`, and announces with chat messages. Players need no receive code: results arrive as ordinary STR chat messages.

**Tech Stack:** C++23, CMake, vcpkg, CommonLibSSE-NG v15.7.3 (submodule), STR Plugin Messaging API 0.10.1, Lua (STR server scripting), MCM Helper.

**Spec:** `docs/superpowers/specs/2026-11-11-sleep-together-design.md`

## Global Constraints

- Skyrim SE/AE **1.6.1170 and 1.7.104**; STR **1.8.4**; STRPluginMessagingAPI + Bridge **0.10.1**; MCM Helper and SkyUI.
- Repo layout, build scripts, archive script and MCM plugin generator follow `C:\Users\Andrew\Documents\_devWin\EnchantersHandbook` (copy, rename).
- The server validates the leader (`player:IsPartyLeader()`); the client is never trusted.
- Time is set in **whole hours only** (minutes always 0): the server's `SetTime` minute encoding is wrong above about 35 minutes.
- Default wake-up hour **8**, valid 0 to 23. A player not in a party may advance time only when they are the only connected player.
- MCM Helper control types: `input`, `toggle`, `slider`, `enum`, `keymap`, `header` (not `textinput`). The MCM needs `SleepTogether.esp` from `tools/make_mcm_plugin.py SleepTogether`.
- Bump the version for every zip; commit every change; commit and push as the GitHub noreply identity already set in this repo; never put a private email in a commit or request. Only claim what was verified.
- Cannot run Skyrim from the build environment: in-game checks are done by the user, who reports `Documents\My Games\Skyrim Special Edition\SKSE\SleepTogether.log` and the server log.

## Review Focus

- Wake hour from the game is out of range, negative, NaN or 24: use the configured hour instead of a bad time (Task 2).
- A client sends garbage, oversized or wrong-version payload: ignored, no error, no time change (Tasks 3, 4).
- A non-leader or spoofed client asks for a time change: denied, clock unchanged (Task 4).
- Leader with no party: allowed only when alone; with others connected: denied (Task 4).
- Sleep start fires twice, or the leader sleeps again right away: only one advance per 5 seconds (Tasks 4, 6).

---

## File Structure

- `CMakeLists.txt`, `vcpkg.json`, `vcpkg-configuration.json`, `.gitignore`, `COPYING`, `build_release.bat`, `make_archive.bat`, `tools/make_archive.ps1`, `tools/make_mcm_plugin.py`: build and packaging (copied from EnchantersHandbook).
- `src/PCH.h`, `src/main.cpp`: plugin entry, logging, wiring.
- `src/Config.h/.cpp`: MCM Helper settings (enabled, wake hour, debug).
- `src/Core.h/.cpp`: pure logic, no game headers (wake hour, text). Unit tested.
- `src/Protocol.h/.cpp`: pure wire format, no game headers. Unit tested.
- `src/StrLink.h/.cpp`: STRPM channel, sends the request.
- `src/SleepWatch.h/.cpp`: detects the local player starting to sleep.
- `tests/test_main.cpp`: plain-assert unit tests for Core and Protocol, run by CTest.
- `server/sleeptogether/{main.lua, logic.lua, sleeptogether.manifest}` and `tests/test_logic.lua`: server resource.
- `package/Data/{SKSE/Plugins, MCM/Config/SleepTogether, SleepTogether.esp}`, `package/Server/sleeptogether/`: shipped files.

---

### Task 1: Scaffold that builds, loads and packages

**Files:** Create everything listed under build and packaging, `src/PCH.h`, `src/main.cpp`, `src/Config.h/.cpp`, `package/Data/MCM/Config/SleepTogether/{config.json,settings.ini}`, `package/Data/SleepTogether.esp`, `README.md`; add submodule `lib/commonlibsse-ng` (alandtse/CommonLibSSE-NG at tag v15.7.3).

**Interfaces:**
- Produces: `SleepTogether::Config::Settings { bool enabled{true}; std::uint32_t wakeHour{8}; bool debug{false}; }`, `Config::Load()`, `Config::ReloadIfChanged()`, `Config::Get() -> Settings`. Settings keys: `[General] bEnabled`, `iWakeHour`, `bDebug`.

- [ ] **Step 1:** Copy the scaffold from EnchantersHandbook with names changed to `SleepTogether`, version `0.1.0`, plugin author `the3venthoriz0n`; `main.cpp` logs `SleepTogether 0.1.0 loading` (the archive script checks this string).
- [ ] **Step 2:** `Config` reads `Data\MCM\Config\SleepTogether\settings.ini` (defaults) and `Data\MCM\Settings\SleepTogether.ini` (user), user wins; clamp `iWakeHour` to 0 to 23. MCM page: toggle `bEnabled`, slider `iWakeHour` (0 to 23, step 1), toggle `bDebug`.
- [ ] **Step 3:** Generate `package/Data/SleepTogether.esp` with `python -I tools/make_mcm_plugin.py SleepTogether package/Data/SleepTogether.esp`.
- [ ] **Step 4:** Build: `cmake -S . -B out\build-release -A x64 -DCMAKE_TOOLCHAIN_FILE=C:\dev\vcpkg\scripts\buildsystems\vcpkg.cmake` then `cmake --build out\build-release --config Release --target SleepTogether` from a VS developer environment. Expected: `SleepTogether.dll` copied to `package/Data/SKSE/Plugins`.
- [ ] **Step 5:** Run `tools\make_archive.ps1`. Expected: `dist\SleepTogether-0.1.0.zip` listing `Data\SleepTogether.esp`, the MCM files and the DLL.
- [ ] **Step 6:** Commit: `git add -A && git commit -m "Scaffold Sleep Together"`.

### Task 2: Core logic (TDD)

**Files:** Create `src/Core.h`, `src/Core.cpp`, `tests/test_main.cpp`; Modify `CMakeLists.txt` (add `enable_testing()`, executable `SleepTogetherTests` from `tests/test_main.cpp src/Core.cpp src/Protocol.cpp`, `add_test`).

**Interfaces:** Produces (namespace `SleepTogether::Core`, standard library only):
- `int ResolveWakeHour(std::optional<float> chosenEndHour, int fallbackHour)`: whole hour 0 to 23.
- `std::string FormatHour(int hour)`: `"08:00"` style.
- `std::string AdvanceMessage(std::string_view leaderName, int hour)`.
- `std::string DenyMessage()`.

- [ ] **Step 1: Write failing tests** in `tests/test_main.cpp` (use a small `CHECK(expr)` macro that prints the failing line and returns non-zero):

```cpp
CHECK(Core::ResolveWakeHour(std::nullopt, 8) == 8);
CHECK(Core::ResolveWakeHour(13.4f, 8) == 13);
CHECK(Core::ResolveWakeHour(13.5f, 8) == 14);
CHECK(Core::ResolveWakeHour(23.6f, 8) == 0);
CHECK(Core::ResolveWakeHour(-1.f, 8) == 8);
CHECK(Core::ResolveWakeHour(24.f, 8) == 8);
CHECK(Core::ResolveWakeHour(std::nanf(""), 8) == 8);
CHECK(Core::ResolveWakeHour(std::nullopt, 99) == 23);
CHECK(Core::ResolveWakeHour(std::nullopt, -3) == 0);
CHECK(Core::FormatHour(8) == "08:00");
CHECK(Core::FormatHour(0) == "00:00");
CHECK(Core::AdvanceMessage("Alice", 8) == "[Sleep Together] Alice slept. It is now 08:00.");
CHECK(Core::DenyMessage() == "[Sleep Together] Only the party leader can advance time.");
```
- [ ] **Step 2:** Run `cmake --build out\build-release --config Release --target SleepTogetherTests`. Expected: FAIL (does not compile: `Core` undefined).
- [ ] **Step 3:** Implement the four functions in `src/Core.cpp` (round chosen hour to nearest, wrap 24 to 0; chosen outside `[0,24)` or NaN falls back; fallback clamped to 0 to 23).
- [ ] **Step 4:** Build and run `ctest --test-dir out\build-release -C Release --output-on-failure`. Expected: all pass.
- [ ] **Step 5:** Commit: `git add -A && git commit -m "Add core wake-hour logic with tests"`.

### Task 3: Wire protocol (TDD)

**Files:** Create `src/Protocol.h`, `src/Protocol.cpp`; Modify `tests/test_main.cpp`.

**Interfaces:** Produces (namespace `SleepTogether::Protocol`, standard library only):
- `inline constexpr const char* kChannel = "sleeptogether.v1";`
- `std::string FormatSleepRequest(int hour)`: `"STv1|SLEEP|<hour>"`.
- `std::optional<int> ParseSleepRequest(std::string_view text)`: hour 0 to 23 or nothing.

- [ ] **Step 1: Write failing tests:**

```cpp
CHECK(Protocol::FormatSleepRequest(8) == "STv1|SLEEP|8");
CHECK(Protocol::ParseSleepRequest("STv1|SLEEP|8") == 8);
CHECK(Protocol::ParseSleepRequest("STv1|SLEEP|23") == 23);
for (auto bad : {"STv1|SLEEP|24", "STv1|SLEEP|-1", "STv1|SLEEP|", "STv1|SLEEP|8x",
                 "STv2|SLEEP|8", "", "STv1|SLEEP|08 ", "hello"})
    CHECK(!Protocol::ParseSleepRequest(bad));
CHECK(!Protocol::ParseSleepRequest(std::string(5000, '8')));
```
- [ ] **Step 2:** Build the tests target. Expected: FAIL (does not compile).
- [ ] **Step 3:** Implement both in `src/Protocol.cpp` (strict: exact prefix, digits only, no whitespace, length cap 32).
- [ ] **Step 4:** Build and run ctest. Expected: all pass.
- [ ] **Step 5:** Commit: `git add -A && git commit -m "Add sleep request wire format with tests"`.

### Task 4: Server resource (Lua)

**Files:** Create `server/sleeptogether/logic.lua`, `server/sleeptogether/main.lua`, `server/sleeptogether/sleeptogether.manifest` (same keys as the relay's manifest: name, version, apiset, entrypoint `main.lua`), `tests/test_logic.lua`.

**Interfaces:**
- Produces (`logic.lua` returns a table, no game globals used):
  - `logic.parse_request(text) -> hour|nil` (same rules and vectors as Task 3).
  - `logic.decode_envelope(message) -> channel, payloadText | nil`: takes a relay envelope `STRPM|v2|...|channel=<c>|...|payload=<HEX>|...`, returns the channel and the hex-decoded payload; nil if malformed or `part`/`parts` is not `1`/`1`.
  - `logic.format_hour(hour) -> "08:00"`, `logic.advance_message(leaderName, hour)`, `logic.deny_message()`: must return exactly the same strings as `Core::FormatHour`, `Core::AdvanceMessage`, `Core::DenyMessage` (Task 2); Lua cannot call the C++ ones.
  - `logic.decide(isLeader, playerCount, hour, nowMs, lastAdvanceMs) -> {kind="advance", hour=h} | {kind="deny", reason="not_leader"|"rate_limited"|"bad_request"}`. Rules: `hour` nil gives `bad_request`; advance within 5000 ms of `lastAdvanceMs` gives `rate_limited`; leader advances; non-leader advances only when `playerCount == 1`.
- Consumes: Task 3 request format; relay envelope format from `STRPluginMessagingAPI\extras\str-server-resources\strpm-chat-relay\main.lua`.

- [ ] **Step 1: Write failing tests** in `tests/test_logic.lua` (plain `assert`, run with a Lua 5.4 interpreter; if none is installed, install one with `vcpkg install lua[tools]:x64-windows` and use its `lua.exe`): all parse vectors from Task 3; `decode_envelope` of a hand-built envelope with payload hex of `STv1|SLEEP|8` returns `("sleeptogether.v1", "STv1|SLEEP|8")`; and:

```lua
assert(logic.format_hour(8) == "08:00")
assert(logic.advance_message("Alice", 8) == "[Sleep Together] Alice slept. It is now 08:00.")
assert(logic.deny_message() == "[Sleep Together] Only the party leader can advance time.")
assert(logic.decide(true, 3, 8, 10000, 0).kind == "advance")
assert(logic.decide(false, 3, 8, 10000, 0).reason == "not_leader")
assert(logic.decide(false, 1, 8, 10000, 0).kind == "advance")
assert(logic.decide(true, 3, nil, 10000, 0).reason == "bad_request")
assert(logic.decide(true, 3, 8, 12000, 10000).reason == "rate_limited")
assert(logic.decide(true, 3, 8, 15001, 10000).kind == "advance")
```
- [ ] **Step 2:** Run `lua tests\test_logic.lua`. Expected: FAIL (module missing).
- [ ] **Step 3:** Implement `logic.lua`.
- [ ] **Step 4:** Run `lua tests\test_logic.lua`. Expected: no output, exit 0.
- [ ] **Step 5:** Implement `main.lua`: `addEventHandler("onChatMessage", function(entityId, message) ... end)`. Look up the player as the relay does (`getPlayerByCharacter`); decode and filter on channel `sleeptogether.v1`; call `logic.decide`. Do **not** call `cancelEvent` (the relay does). On `advance`: `GameServer:get():SetTime(hour, 0, CalendarService:get():GetTimeScale())` then `SendGlobalChatMessage` with `logic.advance_message(player:GetUsername(), hour)`. On `not_leader`: `SendChatMessage(player:GetConnectionId(), logic.deny_message())`. Print one log line per request: sender name, decision.
- [ ] **Step 6:** Load-order check (user, in game): copy the resource next to `strpm-chat-relay` on the server and restart. Expected server log: our request line when a leader sleeps. Handlers run in registration order and the first `cancelEvent` stops the rest, and the relay cancels, so our resource must load first. If our line never appears, copy the relay into this repo as `server/strpm-chat-relay-sleeptogether` and call a `STRPM_SERVER_HANDLERS` list (filled by our `main.lua`) just before its `cancelEvent`.
- [ ] **Step 7:** Commit: `git add -A && git commit -m "Add server resource and logic tests"`.

### Task 5: STRPM link and sending

**Files:** Create `src/StrLink.h`, `src/StrLink.cpp`; copy `src/STRPluginMessagingAPI/STRPluginMessagingAPI.h` and `src/STRPluginMessagingAPI.cpp` from `PartyInventory`; Modify `CMakeLists.txt`.

**Interfaces:**
- Consumes: `Protocol::kChannel`, `Protocol::FormatSleepRequest(int)`; STRPM `Interface::send(channel, Target, data, size, flags)` as used by `PartyInventory\src\StrLink.cpp`.
- Produces: `bool SleepTogether::StrLink::Start()`; `bool StrLink::SendSleepRequest(int hour)`: sends to `TargetKind::kServer` with `kMessageReliable | kMessageOrdered`; returns false when not connected.

- [ ] **Step 1:** Implement `Start()` (load the API, register the channel) and `SendSleepRequest` following `PartyInventory`'s `StrLink::SendText`, with the target kind for the server taken from the API header.
- [ ] **Step 2:** In `main.cpp`, call `StrLink::Start()` on `kDataLoaded` and log the result; log `Sleep request sent hour=<h>` at info level in `SendSleepRequest` on success.
- [ ] **Step 3:** Build the plugin. Expected: compiles and links; the tests target still passes.
- [ ] **Step 4:** Commit: `git add -A && git commit -m "Add STRPM link and sleep request sender"`.

### Task 6: Detect local sleep and send

**Files:** Create `src/SleepWatch.h`, `src/SleepWatch.cpp`; Modify `src/main.cpp`.

**Interfaces:**
- Consumes: `Core::ResolveWakeHour`, `Config::Get()`, `StrLink::SendSleepRequest`.
- Produces: `void SleepTogether::SleepWatch::Install()`; internally calls `OnSleepStarted(std::optional<float> chosenEndHour)`, which sends `SendSleepRequest(Core::ResolveWakeHour(chosenEndHour, Config::Get().wakeHour))` when `Config::Get().enabled`, at most once per 3 seconds.

- [ ] **Step 1:** Implement `Install()` so that `OnSleepStarted(std::nullopt)` is called once when the player goes from not sleeping to sleeping. Prefer a sink on the game's `TESSleepStartEvent` if CommonLibSSE-NG's `ScriptEventSourceHolder` can be used with a locally defined struct; otherwise watch the player's sit/sleep state from a task on the game thread.
- [ ] **Step 2:** Log `Local sleep started` at info level each time it triggers, with the hour sent.
- [ ] **Step 3:** Build. Expected: compiles; tests pass.
- [ ] **Step 4 (user, in game):** On the server with the Task 4 resource: leader lies down and sleeps; check `SleepTogether.log` for `Local sleep started` and `Sleep request sent hour=8`, the server log for the request line, and that the clock jumps to 08:00 for everyone with the announce message in chat. Then a non-leader sleeps: they see the deny message and the clock is unchanged.
- [ ] **Step 5:** Commit: `git add -A && git commit -m "Detect local sleep and send the request"`.

### Task 7: Use the hour chosen in the sleep menu

**Files:** Modify `src/SleepWatch.cpp`, `src/SleepWatch.h`.

**Interfaces:** Produces: `OnSleepStarted` is called with the leader's chosen end hour when it can be read.

- [ ] **Step 1:** If the sleep-start event payload is available (believed to be start time then desired end time, two floats), define the struct locally and log both values at info level on each sleep. If the sink approach cannot compile, read the same information from `RE::SleepWaitMenu` before it closes (`GetRuntimeData()` fields) and log what is found.
- [ ] **Step 2 (user, in game):** Sleep for several different durations; send the log. Confirm the logged end hour matches the hour chosen in the menu.
- [ ] **Step 3:** Only after step 2 confirms, pass the logged end hour into `OnSleepStarted`. Until then the configured wake hour is used.
- [ ] **Step 4:** Commit: `git add -A && git commit -m "Read the chosen wake time from the sleep event"`.

### Task 8: Package, document, publish

**Files:** Modify `README.md`, `tools/make_archive.ps1` (include `server\sleeptogether` as `Server\sleeptogether` in the zip), `package/`.

- [ ] **Step 1:** README: what it does, requirements (STR 1.8.4, STRPM + Bridge + chat relay, MCM Helper, SkyUI), install (zip contents, copy `Server\sleeptogether` to the STR server `Resources` folder next to the relay, enable `SleepTogether.esp`), settings, known unknowns (same-bed sleeping untested; chosen-time reading depends on Task 7; clock jump may look abrupt).
- [ ] **Step 2:** Build Release, run `tools\make_archive.ps1`. Expected: zip contains the DLL, MCM files, `SleepTogether.esp` and `Server\sleeptogether\*`.
- [ ] **Step 3:** Commit, then create the GitHub repo and push (this step needs the user's go-ahead because it publishes): `gh repo create the3venthoriz0n/SleepTogether --private --source . --push`.
- [ ] **Step 4 (user, in game):** Run the full test list: leader sleeps; non-leader sleeps; leader sleeps with a non-leader in bed; two players in the same double bed; a player disconnects during sleep; leader sleeps twice within 5 seconds. Record results in the README.
