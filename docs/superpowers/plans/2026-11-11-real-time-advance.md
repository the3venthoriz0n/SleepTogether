# Sleep Together v2 (real time advance) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A party leader's sleep makes game time really advance on an STR server (hours chosen in the menu, or until 08:00 by default), with correct date rollover, days-passed on every client and stats restored at the end.

**Architecture:** Two repos. (1) STR server fork worktree `C:\Users\Andrew\Documents\_devWin\TiltedEvolution-sleep` (branch `sleep-time-advance`, from `player-inventory-transfers`) gets two small Lua-callable functions (`AdvanceHours`, `HoursUntil`) and a CI tag. (2) `C:\Users\Andrew\Documents\_devWin\SleepTogether` (branch `build-sleep-together`): the plugin sends `STv2|HOURS|n` or `STv2|UNTIL|h`; the Lua code inside the relay runs a stepped session (one game hour per real second via `onUpdate`) and sends `STEP`/`DONE` envelopes to every player; the plugin applies them (days passed, stat restore).

**Tech Stack:** C++23 (plugin, CMake/vcpkg, CommonLibSSE-NG), C++ and xmake (STR server), Catch2 (server tests), Lua 5.5 (relay code), GitHub Actions (image build), MCM Helper.

**Spec:** `docs/superpowers/specs/2026-11-11-real-time-advance-design.md` (in the SleepTogether repo). Read it first: it lists what was verified and the binding decisions.

## Global Constraints

- Server base branch is `player-inventory-transfers`; image `VERSION_OVERRIDE=v1.8.4`; new image tag `:sleep`; the `:patched` tag must never be written by this branch. The server rejects clients whose version string differs, so the override must stay `v1.8.4`.
- Wire format, all ASCII, 32-character cap, digits only, leading zeros accepted, no signs or spaces. Client to server: `STv2|HOURS|<n>` (n 1 to 24), `STv2|UNTIL|<h>` (h 0 to 23). Server to client: `STv2|STEP|<milliHours>` (integer 1 to 24000) and `STv2|DONE|<milliHours>` (integer 0 to 24000), where milliHours = hours times 1000. Channel `sleeptogether.v1`.
- Server-built envelope (the client bridge requires every field): `STRPM|v2|msg=<unique>|seq=<n>|channel=sleeptogether.v1|target=all|flags=0|part=1|parts=1|payload=<UPPERCASE HEX>|sender=<nonzero connection id>|senderPlayerId=<id>|senderName=<name>|serverTick=<tick>`; every `msg` unique; no `<` or `>` characters (the chat binding strips them).
- Anything a client sends on `sleeptogether.v1` must never be forwarded to other players by the relay (the hook returns "handled").
- Pace is one game hour per real second; steps accumulate `onUpdate` `Delta` (float seconds). Session starts only if no session is running and the 5 s rate limit allows it.
- Leader rules unchanged: sender must be the party leader, or the only connected player.
- Plugin version 0.2.0. Commit every task. Commit as the noreply identity already set in both repos; end commit messages with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`. Do not push anything in a task; the controller pushes `sleep-time-advance` after the final checks.
- Only use APIs that exist in the checked-out sources (CommonLibSSE-NG in the SleepTogether repo, the STR server source in the worktree, the STRPM repo at `C:\Users\Andrew\Documents\_devWin\STRPluginMessagingAPI`). If a needed API does not exist, report it; never invent one.
- The server image build takes 40+ minutes on GitHub: server C++ must be as small as possible and copy existing patterns line for line.
- Tools: Lua at `C:\dev\vcpkg\installed\x64-windows\tools\lua\lua.exe`; Visual Studio at `C:\Program Files\Microsoft Visual Studio\18\Community` (use `VsDevCmd.bat -arch=x64` for `cl`/cmake/ctest); plugin build recipe in `README.md`; vcpkg at `C:\dev\vcpkg`.

## Review Focus

- `AdvanceHours`/`Normalize` carry at month end, year end, and exactly 24 hours; `Update` behaves exactly as before (Task 1 tests).
- Server rejects bad hours (0, negative, over 24, NaN) and `HoursUntil` handles exactly-the-hour and wrap (Tasks 1, 2).
- A client sends garbage, oversized, wrong-version or `target=all` forged `STEP`/`DONE` on our channel: ignored and never relayed (Task 6).
- Slider unreadable or NaN: falls back safely to the default wake hour (Task 4, 7).
- Two requests overlap, or one arrives mid-session: second is ignored, session unaffected (Tasks 5, 6).
- A leader disconnects or the player list changes mid-session: the session still finishes without a Lua error (Task 6).

---

## File Structure

SleepTogether repo (plugin and relay code): `src/Protocol.h/.cpp` (wire format), `src/Core.h/.cpp` (pure decisions), `src/Effects.h/.cpp` (apply STEP/DONE in game), `src/StrLink.*` (send and receive), `src/SleepWatch.*` (slider capture, trigger), `src/Config.*` and MCM files (new settings), `server/sleeptogether/{logic.lua,handler.lua}` and `tools/build_server_resource.py` (relay code), `tests/`, `tools/server-verify/` (local compile check for the server `DateTime` code), `server/patches/` (exported server patch), `README.md`.

STR server worktree (`TiltedEvolution-sleep`): `Code/common/DateTime.h/.cpp`, `Code/tests/datetime.cpp` (+ `Code/tests/xmake.lua`), `Code/server/Services/CalendarService.h/.cpp`, `Code/server/Scripting/Services/CalendarService_Bindings.cpp`, `.github/workflows/docker-patched-server.yml`.

---

### Task 1: Server `DateTime` math with tests and a local verification harness

**Files (worktree `C:\Users\Andrew\Documents\_devWin\TiltedEvolution-sleep`):** Modify `Code/common/DateTime.h`, `Code/common/DateTime.cpp`; Create `Code/tests/datetime.cpp`; Modify `Code/tests/xmake.lua`. **Files (SleepTogether repo):** Create `tools/server-verify/` (stub headers `catch2/catch.hpp` and `TiltedCore/Buffer.hpp`, `run.ps1`).

**Interfaces:** Produces on `struct DateTime`: `void AdvanceHours(float aHours) noexcept;` (adds hours to `m_timeModel.Time` and carries day, month, year exactly like `Update` does) and `[[nodiscard]] float HoursUntil(int aHour) const noexcept;` (hours until the clock next reads `aHour:00`: `aHour - Time`, plus 24 if that is `<= 0`; returns `-1.f` if `aHour` is outside 0 to 23). The carry code moves into one private `void Normalize() noexcept;` called by both `Update` and `AdvanceHours`; `Update` behaviour must not change.

- [ ] **Step 1:** Create `tools/server-verify/` with minimal stub headers (`catch2/catch.hpp` defining `TEST_CASE`, `REQUIRE`, `Approx` with `.margin()`, and a main that runs and reports; `TiltedCore/Buffer.hpp` declaring `namespace TiltedPhoques { struct Buffer { struct Writer; struct Reader; }; }`) and `run.ps1` that compiles `Code/common/DateTime.cpp` plus `Code/tests/datetime.cpp` from the worktree with `cl /std:c++17 /EHsc` (include dirs: the stubs, `Code`, `Code/encoding`), runs the executable and exits non-zero on any failure. The stubs must be as faithful as needed for the real test file to compile unchanged.
- [ ] **Step 2: Write failing tests** in `Code/tests/datetime.cpp` (Catch2 v2 style like `Code/tests/playback_clock.cpp`: `#include <catch2/catch.hpp>`, `#include "../common/DateTime.h"`; the file must not define its own main). Test cases with these exact values (TimeModel defaults otherwise; Month is a 0-based index into 31,28,31,30,31,30,31,31,30,31,30,31 days):
  - `AdvanceHours` mid-day: Time 22.5, Day 1, Month 0, +1.0 gives Time 23.5, Day 1.
  - day rollover: Time 23.0, Day 1, Month 0, +2.0 gives Time 1.0 (Approx margin 1e-4), Day 2.
  - month rollover: Time 23.0, Day 31, Month 0, +2.0 gives Time 1.0, Day 1, Month 1, Year unchanged.
  - year rollover: Time 23.0, Day 31, Month 11, Year 5, +2.0 gives Day 1, Month 0, Year 6.
  - exactly 24 h: Time 5.0, Day 3, Month 0, +24.0 gives Time 5.0, Day 4.
  - `Update` unchanged: TimeScale 100, Time 23.99, Day 1, Month 0, `Update(1000)` gives Time about 0.0177 (margin 1e-3) and Day 2; and TimeScale 20, Time 12.0, `Update(1000)` gives Time about 12.00556 (margin 1e-4).
  - `HoursUntil`: Time 13.64, `HoursUntil(8)` about 18.36 (margin 1e-3); Time 7.5, `HoursUntil(8)` about 0.5; Time 8.0, `HoursUntil(8)` equals 24.0; Time 0.0, `HoursUntil(0)` equals 24.0; `HoursUntil(24)` equals -1.0; `HoursUntil(-1)` equals -1.0.
  Add `datetime.cpp` handling: `Code/tests/xmake.lua` already globs `*.cpp`; add `add_files("../common/DateTime.cpp")` next to the existing PlaybackClock line with a comment (`-- Pure date maths, no game dependencies`), nothing else.
- [ ] **Step 3: Run RED:** `powershell -File tools\server-verify\run.ps1` in the SleepTogether repo. Expected: compile failure (methods missing).
- [ ] **Step 4: Implement** `Normalize`, `AdvanceHours`, `HoursUntil` in `Code/common/DateTime.h/.cpp`; make `Update` call `Normalize` after adding the delta. `AdvanceHours` ignores non-finite or non-positive input (no change).
- [ ] **Step 5: Run GREEN:** the same command. Expected: all test cases pass, output clean.
- [ ] **Step 6: Commit** the worktree change (`git -C C:\Users\Andrew\Documents\_devWin\TiltedEvolution-sleep add Code && git commit`, message `server: add DateTime::AdvanceHours and HoursUntil with tests`) and commit the harness in the SleepTogether repo.

### Task 2: Server `CalendarService` functions and Lua bindings

**Files (worktree):** Modify `Code/server/Services/CalendarService.h`, `Code/server/Services/CalendarService.cpp`, `Code/server/Scripting/Services/CalendarService_Bindings.cpp`.

**Interfaces:** Consumes `DateTime::AdvanceHours(float)` and `DateTime::HoursUntil(int)` (Task 1). Produces `bool CalendarService::AdvanceHours(float aHours) noexcept;` (true only when `0 < aHours <= 24` and finite: advances `m_dateTime`, then `SendTimeResync()`) and `float CalendarService::HoursUntil(int aHour) const noexcept;` (forwards to `m_dateTime.HoursUntil`); Lua: `CalendarService:get():AdvanceHours(x)` returns bool, `CalendarService:get():HoursUntil(h)` returns number (-1 if invalid). Bindings are lambdas taking `CalendarService& aSelf` first, exactly like the `GameServer` bindings in `GameServer_Bindings.cpp`; the existing `GetTimeScale` binding stays untouched.

- [ ] **Step 1:** Add the two declarations to `CalendarService.h` next to `SetTime`/`GetTimeScale`; implement in `CalendarService.cpp` next to `SetTimeScale`, copying that function's style; `AdvanceHours` must not call `GetScriptService().HandleSetTime` (no script re-entry) and must reuse `SendTimeResync()`.
- [ ] **Step 2:** Add the two bindings in `CalendarService_Bindings.cpp` after `GetTimeScale`, following the `type["Name"] = [](T& aSelf, args)` pattern from `Code/server/Scripting/GameServer_Bindings.cpp`.
- [ ] **Step 3: Compile-risk checklist (no local server build exists):** write `COMPILE_CHECK.md` content into the commit message body and your report, listing for every identifier used: where it is declared and that the include is already present in that file (`CalendarService.cpp` and the bindings file). Double check signatures (const-ness, `noexcept`, parameter types) against the header, and that no new include is needed. Do not add includes unless the check proves one missing.
- [ ] **Step 4: Verify what can be verified locally:** re-run `tools\server-verify\run.ps1` (still green) and show `git diff` for the three files.
- [ ] **Step 5: Commit** in the worktree (`server: expose CalendarService AdvanceHours and HoursUntil to Lua`).

### Task 3: CI workflow for the new image tag and patch export

**Files (worktree):** Modify `.github/workflows/docker-patched-server.yml`. **Files (SleepTogether repo):** Create `server/patches/README.md`.

- [ ] **Step 1:** Edit only these lines of the workflow: the header comment (say it builds branch `sleep-time-advance` to `ghcr.io/<owner>/st-reborn-server:sleep`, never touching `:patched`), the push trigger branch list (`sleep-time-advance` instead of `player-inventory-transfers`), and the image tag line (`${{ env.IMAGE }}:sleep`). `VERSION_OVERRIDE=v1.8.4` and every other line stay identical. Show `git diff` proving only those lines changed.
- [ ] **Step 2:** In the SleepTogether repo create `server/patches/README.md` explaining: the branch name and base, that `git format-patch` output (added in Task 9) applies to a clean `player-inventory-transfers`, the new image tag `:sleep`, that `:patched` is untouched, how to roll back (point the server at `:patched`), and that `bSyncPlayerCalendar=true` is required in `STServer.ini` under `[Gameplay]`.
- [ ] **Step 3: Commit** both (worktree: `ci: build the sleep-time-advance branch to the :sleep image tag`).

### Task 4: Protocol v2 and pure decisions in C++

**Files:** Modify `src/Protocol.h`, `src/Protocol.cpp`, `src/Core.h`, `src/Core.cpp`, `tests/test_main.cpp`.

**Interfaces:** Produces, namespace `SleepTogether::Protocol`: `enum class RequestKind { kHours, kUntil };` `struct Request { RequestKind kind; int value; };` `std::string FormatRequest(const Request&)` (`STv2|HOURS|<n>` / `STv2|UNTIL|<h>`); `std::optional<Request> ParseRequest(std::string_view)` (exact rules above; HOURS 1 to 24, UNTIL 0 to 23; used as the contract mirror of the Lua parser); `enum class ServerKind { kStep, kDone };` `struct ServerMessage { ServerKind kind; int milliHours; };` `std::optional<ServerMessage> ParseServerMessage(std::string_view)` (`STv2|STEP|<1..24000>`, `STv2|DONE|<0..24000>`, digits only, 32-character cap, leading zeros accepted). The old `FormatSleepRequest`/`ParseSleepRequest` and their tests are removed (v1 is superseded). Namespace `SleepTogether::Core`: `Protocol::Request DecideRequest(std::optional<float> initialSlider, std::optional<float> pressSlider, bool useDefaultWake, int wakeHour);` and `float StatRestoreAmount(float maximum, float current) noexcept;` and `std::string AdvanceMessage(std::string_view name, float hours);` (now `[Sleep Together] <name> slept for <n> hour(s).`, n = nearest whole hour at least 1; `1 hour`, otherwise `<n> hours`). `Core::DenyMessage()` unchanged. Remove `Core::FormatHour` only if nothing uses it afterwards (check usages first).

- [ ] **Step 1: Write failing tests** in `tests/test_main.cpp` (exact values):
  - `FormatRequest({kHours, 7}) == "STv2|HOURS|7"`, `FormatRequest({kUntil, 8}) == "STv2|UNTIL|8"`.
  - `ParseRequest` accepts: `"STv2|HOURS|1"`, `"STv2|HOURS|24"`, `"STv2|HOURS|07"` (value 7), `"STv2|UNTIL|0"`, `"STv2|UNTIL|23"`; rejects `"STv2|HOURS|0"`, `"STv2|HOURS|25"`, `"STv2|UNTIL|24"`, `"STv2|UNTIL|-1"`, `"STv2|HOURS|"`, `"STv2|HOURS|8x"`, `"STv2|HOURS|+8"`, `"STv2|HOURS|8 "`, `"STv1|SLEEP|8"`, `"STv2|SLEEP|8"`, `"STv2|hours|8"`, `""`, a 5000-character string, a 33-character zero-padded `STv2|HOURS|` value, and a string with an embedded NUL.
  - `ParseServerMessage`: `"STv2|STEP|1000"` gives {kStep,1000}; `"STv2|STEP|24000"` ok; `"STv2|STEP|0"` rejected; `"STv2|STEP|24001"` rejected; `"STv2|DONE|0"` gives {kDone,0}; `"STv2|DONE|18360"` ok; `"STv2|DONE|24001"` rejected; `"STv2|STEP|"`, `"STv2|STEP|1e3"`, `"STv2|STEP|-5"`, `"STv2|HOURS|3"` rejected.
  - `DecideRequest`: initial 18, press 18, useDefault true, wake 8 gives {kUntil,8}; initial 1, press 7.345, useDefault true gives {kHours,7} (explicit); initial 1, press 1, useDefault false gives {kHours,1}; press 7.5 gives 8 (round half up); press 30 clamps to 24; press 0.2 clamps to 1; press NaN or nullopt gives {kUntil, wake} even with useDefault false; initial nullopt with a readable press and useDefault true gives {kUntil, wake} (cannot tell if explicit); wake 99 clamps to 23 and -3 to 0.
  - `StatRestoreAmount(100,40)==60`, `(100,100)==0`, `(100,120)==0`, `(NaN,40)==0`, `(100,NaN)==0`, `(-5,0)==0`.
  - `AdvanceMessage("Alice", 8.0f) == "[Sleep Together] Alice slept for 8 hours."`, `("Bob", 1.0f) == "[Sleep Together] Bob slept for 1 hour."`, `("Bob", 0.2f)` equals the 1 hour text, `("Cy", 18.36f)` equals `"[Sleep Together] Cy slept for 18 hours."`.
- [ ] **Step 2:** Run the C++ tests RED: build `SleepTogetherTests` (recipe in `README.md`), expect compile failure.
- [ ] **Step 3:** Implement the new Protocol and Core functions; remove the v1 functions and their tests.
- [ ] **Step 4:** Run ctest GREEN, then build the plugin target once to confirm it still compiles (SleepWatch and StrLink currently call the removed v1 functions: change those call sites minimally to a temporary `FormatRequest({kUntil, wakeHour})` so the build stays green; Task 7 replaces them properly).
- [ ] **Step 5: Commit.**

### Task 5: Lua `logic.lua` v2 (parsing, session, envelopes)

**Files:** Modify `server/sleeptogether/logic.lua`, `tests/test_logic.lua`.

**Interfaces:** Produces on the table returned by `logic.lua`: `parse_request(text) -> kind, value | nil` (`"HOURS"`/`"UNTIL"`, same rules and vectors as the C++ `ParseRequest`); `decode_envelope(message)` (unchanged); `payload_step(milliHours)`, `payload_done(milliHours)` returning `STv2|STEP|<n>`/`STv2|DONE|<n>` with `n` an integer (rounded); `build_envelope(channel, seq, msgid, senderConnectionId, senderPlayerId, senderName, payloadText, tick) -> string` (format in Global Constraints; the name is sanitised: `|`, `<`, `>`, CR, LF and `=` replaced by `_`); `decide(isLeader, playerCount, nowMs, lastAdvanceMs, busy) -> {kind="advance"} | {kind="deny", reason="not_leader"|"rate_limited"|"busy"}` (leader or solo player allowed; busy beats rate limit); `new_session(totalHours) -> session` and `session_tick(session, deltaSeconds) -> stepsMilliHours (array), finished (bool)` (accumulates seconds; one game hour per second; emits a step when the accumulated seconds cover min(1, remaining) hours, last step may be partial; no step for zero or negative delta; remaining never goes negative; total of steps equals totalHours within 1 milli-hour); `advance_message(name, hours)` and `deny_message()` identical to the C++ strings (Task 4). Remove `format_hour` and the old HH:00 `advance_message`.

- [ ] **Step 1: Write failing tests** in `tests/test_logic.lua` (plain `assert`; keep the existing envelope tests): every `ParseRequest` vector from Task 4 gives the same accept/reject here (including the NUL and 33-character cases); `payload_step(1000) == "STv2|STEP|1000"`, `payload_done(18360) == "STv2|DONE|18360"`, `payload_step(1000.4) == "STv2|STEP|1000"`; `build_envelope` output decoded by a test-local reimplementation of the client bridge's rules (read `C:\Users\Andrew\Documents\_devWin\STRPluginMessagingAPI\src\STRPluginMessagingBridgeReceive.cpp` lines 760 to 860: fields `msg`, `channel`, `sender`, `seq`, `flags`, `part`, `parts`, `payload` required; `sender` numeric and nonzero; `part >= 1`, `part <= parts`, hex even length) accepts it and recovers the payload text and sender id, and rejects it when `sender` is 0; two envelopes built with different msg ids differ; a name containing `|=<>` and a newline is sanitised; `decide` cases: (true,3,10000,0,false) advance; (false,3,...) not_leader; (false,1,...) advance; (true,3,12000,10000,false) rate_limited; (true,3,15001,10000,false) advance; (true,3,20000,0,true) busy; `session_tick` for total 3 hours: tick 0.5 gives no steps and not finished; tick 0.5 gives {1000}; tick 2.0 gives {1000,1000} and finished; for total 0.35: tick 0.35 gives {350} and finished; tick 10 on a total of 2 gives {1000,1000} finished (catch-up, never over); a delta of 0 or -1 gives nothing; `advance_message("Alice", 8)` and friends equal the Task 4 strings exactly.
- [ ] **Step 2:** RED: `C:\dev\vcpkg\installed\x64-windows\tools\lua\lua.exe tests\test_logic.lua` from the repo root. Expected failure (functions missing).
- [ ] **Step 3:** Implement in `logic.lua`; keep the file free of game globals.
- [ ] **Step 4:** GREEN: same command exits 0 with no output. `tests/test_handler.lua` is allowed to fail at this point (Task 6 fixes it); say so in the report.
- [ ] **Step 5: Commit.**

### Task 6: Handler v2, relay hook and build script

**Files:** Modify `server/sleeptogether/handler.lua`, `tools/build_server_resource.py`, `tests/test_handler.lua`; regenerate and commit `package/Server/strpm-chat-relay/main.lua`.

**Interfaces:** Consumes Task 5's `logic`. Produces `handler.lua` returning `function(logic, gameServer, playerManager, calendar) return handle, tick end`, where `handle(player, fields, message)` returns **true when the envelope is on channel `sleeptogether.v1` (it was handled and must not be relayed), false otherwise, and never raises**, and `tick(deltaSeconds)` drives the session. The build script embeds both in the relay as now, calls the factory with `CalendarService:get()` as `calendar`, registers `addEventHandler("onUpdate", SleepTogetherTick)` right after the factory call, and changes the injected relay line to `local ok, handled = pcall(SleepTogetherHandler, player, fields, message); if ok and handled then return end` (still located by an exact anchor asserted to occur once; update the anchor/replacement and keep the header comment accurate).

Behaviour of `handle` for a valid request from a permitted sender: compute hours (`HOURS n` gives n; `UNTIL h` gives `calendar:HoursUntil(h)` inside `pcall`; a failed or non-positive result is treated as a bad request and logged), start one session recorded with the leader's connection id, player id and name, log `[SleepTogether] <name> sleeps for <hours> h`; denied sender gets `logic.deny_message()` via `SendChatMessage` to their connection; busy or rate-limited requests are logged and ignored. `tick(delta)`: when a session runs, call `logic.session_tick`; for each step call `calendar:AdvanceHours(step / 1000)` (inside `pcall`; on failure log and finish the session) and send a `STEP` envelope to every player returned by `playerManager:GetAllPlayers()` (iterate with `ipairs`; wrap each send in `pcall`); when finished send the `DONE` envelope (total milliHours) to everyone plus `gameServer:SendGlobalChatMessage(logic.advance_message(name, totalHours))`, and clear the session. Envelope sequence numbers and `msg` ids are a module-level counter (unique per message); `tick` is cheap when idle.

- [ ] **Step 1: Write failing tests** in `tests/test_handler.lua` (stubs for gameServer, playerManager (a table of player stubs with `GetConnectionId`, `GetId`, `GetUsername`, `IsPartyLeader`), calendar with `AdvanceHours`/`HoursUntil` recording calls; stubbed `print` captured; update the existing cases that assumed `SetTime` and chat-at-start): leader sends `STv2|HOURS|3` returns true, then ticks of 1.0 s call `AdvanceHours(1.0)` three times, send one STEP envelope per player per step (envelopes pass the Task 5 bridge-rule checker, sender = leader connection id), then one DONE with 3000 and one global chat message `[Sleep Together] Alice slept for 3 hours.`; `STv2|UNTIL|8` with `HoursUntil` stubbed to return 18.36 runs 18 full steps plus a 0.36 step (milliHours 360) and DONE 18360; a non-leader with two players online gets the deny message to its connection, no calendar call, handler still returns true; a solo non-leader is allowed; a second request during a session is ignored (no second session, returns true, logged as busy); a request within 5000 ms of the last start (after the session ended) is rate limited; a forged `STv2|STEP|1000` or `STv2|DONE|1000` sent by a client on our channel returns true, causes no calendar call and no sends; wrong channel returns false and does nothing; malformed payloads, odd-length hex, NUL, 5000-character input return true without error and without calendar calls (no `[SleepTogether] Error` line); `AdvanceHours` returning false or raising ends the session with a logged error and a DONE not sent; `HoursUntil` raising or returning -1 or 0 logs and starts nothing; a player whose `GetConnectionId` raises does not stop the others from receiving the STEP; `tick(0)`, `tick(-1)`, `tick` with no session do nothing; a session continues after the leader disappears from the player list. Plus a build test: run `python -I tools/build_server_resource.py`, then `assert(loadfile("package/Server/strpm-chat-relay/main.lua"))`, assert the generated file contains the `addEventHandler("onUpdate"` registration after the factory call and the `if ok and handled then return end` line after the `local flags` line and before `relayToTarget(`, and (new) assert the generated text equals the upstream file plus only the header, the embed block and the hook lines (compare the upstream lines in order).
- [ ] **Step 2:** RED with both Lua test files; expected failures.
- [ ] **Step 3:** Implement `handler.lua` and the build script changes; keep the build script's exact-once anchor asserts.
- [ ] **Step 4:** GREEN: both `tests/test_logic.lua` and `tests/test_handler.lua` exit 0 with no output; `python -I tools/build_server_resource.py` leaves the committed generated file unchanged after the first regeneration.
- [ ] **Step 5: Commit** (sources, tests, regenerated `package/Server/strpm-chat-relay/main.lua`).

### Task 7: Plugin send path (slider, settings)

**Files:** Modify `src/SleepWatch.h`, `src/SleepWatch.cpp`, `src/StrLink.h`, `src/StrLink.cpp`, `src/Config.h`, `src/Config.cpp`, `package/Data/MCM/Config/SleepTogether/config.json`, `package/Data/MCM/Config/SleepTogether/settings.ini`, `tests/test_main.cpp` only if a pure helper is added.

**Interfaces:** Consumes `Protocol::Request`, `Protocol::FormatRequest`, `Core::DecideRequest` (Task 4). Produces `bool StrLink::SendRequest(const Protocol::Request&)` (replaces `SendSleepRequest`; same send flags and logging, log `Sleep request sent <text>`); `Config::Settings` gains `bool useDefaultWake{true}; bool restoreStats{true};` (keys `[General] bUseDefaultWake = 1`, `bRestoreStats = 1`; `wakeHour` default 8 stays). `SleepWatch::OnSleepStarted(std::optional<float> chosenEndHour)` is replaced by `OnSleepStarted(std::optional<float> initialSlider, std::optional<float> pressSlider)`, which keeps the enable check and the 3 s `Core::Throttle`, builds the request with `Core::DecideRequest(initialSlider, pressSlider, Config::Get().useDefaultWake, static_cast<int>(Config::Get().wakeHour))`, sends it, and logs `Local sleep started (initial slider <v>, at press <v>), requested <kind> <value>`.

- [ ] **Step 1:** In `SleepWatch.cpp`, add a small game-thread reader `std::optional<float> ReadHoursSlider(RE::SleepWaitMenu*)` that reads `HoursSlider` then its `_value` member from the menu's `root` (`GFxValue::GetMember`, check `IsObject()` and `IsNumber()`, return nothing otherwise). Capture the initial value on the first poll tick where the menu is open and not yet active (`isActive == false`), forget it when the menu closes. At the rising edge of `IsSleepPressed`, read the slider again and pass both values to `OnSleepStarted`.
- [ ] **Step 2:** Replace `SendSleepRequest` with `SendRequest` in `StrLink` and fix its callers.
- [ ] **Step 3:** Add the two settings to `Config`, `settings.ini` (`bUseDefaultWake = 1`, `bRestoreStats = 1` under `[General]`) and the MCM `content` (two toggles with clear help text: "Sleep until the wake-up hour unless I move the hours slider" and "Restore health, magicka and stamina after a shared sleep"); keep the control types valid and the config JSON parsing.
- [ ] **Step 4:** Build plugin and tests (recipe in `README.md`); ctest green; show the diff.
- [ ] **Step 5: Commit.**

### Task 8: Plugin receive path (STEP and DONE)

**Files:** Create `src/Effects.h`, `src/Effects.cpp`; Modify `src/StrLink.h`, `src/StrLink.cpp`, `CMakeLists.txt`.

**Interfaces:** Consumes `Protocol::ParseServerMessage`, `Core::StatRestoreAmount`, `Config::Get().restoreStats`. Produces `namespace SleepTogether::Effects { void OnStep(int milliHours); void OnDone(int milliHours); }` (must be called on the game thread): `OnStep` adds `milliHours / 1000.0f / 24.0f` to `RE::Calendar::GetSingleton()->gameDaysPassed->value` (null-check the singleton and the global); `OnDone` (when `restoreStats`) for `RE::ActorValue::kHealth`, `kMagicka`, `kStamina` on `RE::PlayerCharacter::GetSingleton()` restores `Core::StatRestoreAmount(player->GetActorValueMax(av), owner->GetActorValue(av))` through `AsActorValueOwner()->RestoreActorValue(av, amount)` when the amount is greater than 0. `StrLink` registers a real receive callback (replacing the no-op) that parses with `Protocol::ParseServerMessage`, ignores anything unparseable, and queues the effect with `SKSE::GetTaskInterface()->AddTask` (the bridge calls the callback on its own thread; never touch game state in the callback). Log at info (`Sleep step +<milliHours> milli-hours`, `Sleep done`) and at debug for ignored messages.

- [ ] **Step 1:** Read `STRPluginMessagingAPI.h` for the exact receive callback signature and `Message` fields (`channel`, `data`, `size`, `sender`) and how `registerChannel` takes the callback; implement `OnMessage` accordingly, copying `data` before queuing.
- [ ] **Step 2:** Implement `Effects`; add `src/Effects.h/.cpp` to `PROJECT_SOURCES` in `CMakeLists.txt` (not to the test target).
- [ ] **Step 3:** Build plugin and tests; ctest green. State plainly that the receive path and effects were not exercised (they need the game and the server).
- [ ] **Step 4: Commit.**

### Task 9: Version, README, patch export and zips

**Files (SleepTogether repo):** Modify `CMakeLists.txt`, `vcpkg.json`, `src/main.cpp`, `tools/make_archive.ps1` (version 0.2.0 and the marker check), `README.md`, `server/patches/README.md`; Create `server/patches/*.patch`. Delete stale `dist\*0.1.1*` zips after building.

- [ ] **Step 1:** Bump 0.1.1 to 0.2.0 in every place.
- [ ] **Step 2:** Export the server patch: `git -C C:\Users\Andrew\Documents\_devWin\TiltedEvolution-sleep format-patch origin/player-inventory-transfers..HEAD -o C:\Users\Andrew\Documents\_devWin\SleepTogether\server\patches` and confirm they apply cleanly to a fresh temporary worktree of `origin/player-inventory-transfers` (`git apply --check` or `git am --dry-run`; use a throwaway worktree and remove it).
- [ ] **Step 3:** README: replace the old behaviour text with the v2 behaviour (slider hours honoured; default wake hour unless the slider was moved; steps one game hour per second; days passed and stat restore; the new settings), a server-admin section (rebuilt image `:sleep`, workflow, `bSyncPlayerCalendar=true`, rollback to `:patched`, replace the relay `main.lua` with the new one from the server zip, restart), updated log line descriptions, and an updated honest test checklist (hours chosen, default 08:00 untouched slider, toggle off, date rollover past midnight, vendor restock after sleeping 48+ hours total, Survival fatigue, stats restored, double bed, disconnect mid-sleep, leader cancels mid-sleep (not handled: the advance always completes), two requests close together). Keep every earlier warning that still applies; remove the "date does not move forward" warning and say what replaced it, without claiming anything unverified.
- [ ] **Step 4:** Run the full chain: server-verify harness, ctest, plugin and tests build, both Lua tests, `python -I tools/build_server_resource.py` (no change), `make_archive.ps1`; list both zips.
- [ ] **Step 5: Commit.**
