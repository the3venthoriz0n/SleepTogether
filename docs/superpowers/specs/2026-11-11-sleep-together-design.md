# Sleep Together — design

A small mod for Skyrim Together Reborn (STR) that lets a group sleep and advance time, so Survival Mode
(fatigue, stamina recovery) is playable with friends.

Status: **design, awaiting approval. Nothing is built.** Items marked *(my call)* are decisions made by
the designer, not agreed by the user. Items marked *(unverified)* are assumptions about game or STR
behaviour that must be checked before relying on them.

## Why

On an STR server the **server owns the game clock**. Verified in the STR source (`TiltedEvolution`):

- The client skips the game's own time step while connected (`HookSimulateTime` returns early when
  `CalendarService::AllowGameTick()` is false), and every update overwrites `GameHour`, `GameDay`,
  `GameMonth`, `GameYear` and `TimeScale` from the server's time.
- So the vanilla Sleep/Wait menu opens, but whatever time it tries to advance is undone. Sleeping never
  completes, and Survival Mode's rest/fatigue recovery never happens.

The group wants to play Survival Mode (Creation Club, already installed) together, which requires sleep.

## What it does (first version)

1. The vanilla Sleep/Wait menu is kept as is. No custom menu.
2. When the **party leader** sleeps, the plugin tells the server the wake-up time the leader chose in the
   menu. The server sets the clock to that time for everyone.
3. Everyone else in the party gets a message saying the party leader advanced time (and to what time).
4. When a **non-leader** tries to sleep, they get a message that only the party leader can advance time.
5. The leader's request is validated **on the server** (sender must be the party leader). A modified client
   cannot advance time.
6. Because the server clock jumps, each client's own sleep finishes when the clock reaches its wake time.
   This should let Survival Mode's rest recovery fire for everyone who is in bed *(unverified)*.

### Fallback: fixed wake-up hour *(user's request, my interpretation)*

If the leader's chosen wake time cannot be read, the server uses a **configurable wake-up hour,
default 08:00**, set in the MCM (SkyUI Mod Configuration Menu). The leader's client sends that setting.

## Goals

- A group on an STR server can sleep and advance time; Survival Mode recovery works.
- Works with the vanilla menu and vanilla Survival Mode; no changes to either.
- Settings in MCM Helper like the user's other mods.
- Skyrim SE/AE **1.6.1170 and 1.7.104** (the same two profiles the STRPM packages support).

## Non-goals (for now)

- Voting, "everyone must be in bed" gating, and the green "sleep eligible" indicator. Wanted later.
- The Lover's Embrace buff. Wanted later, as its own piece.
- Any change to Survival Mode itself (that is the separate "Survive Together" idea).
- Making it work on servers the user does not control. A server script is required.

## Anti-goals

- Time jumping unpredictably, or a player being stuck in the sleep menu.
- A client being able to set time without being the party leader.
- Players seeing STRPM transport text in chat.

## Constraints and decisions

- **Language/stack** *(my call)*: C++ SKSE plugin on CommonLibSSE-NG v15.7.3 (git submodule), CMake +
  vcpkg, built like the user's existing mods (`PartyInventory`, `EnchantersHandbook`; copy their layout,
  build scripts, `tools/make_archive.ps1`, `tools/make_mcm_plugin.py`). GPL because CommonLibSSE-NG is.
- **Messaging**: STR Plugin Messaging API (STRPM) between clients and server, as `PartyInventory` does
  (`StrLink`). A new channel, e.g. `sleeptogether.v1`, addressed to `server`.
- **Server side**: a Lua resource for the user's patched STR server, alongside `strpm-chat-relay`.
  Verified available in the server Lua API: `player:IsPartyLeader()`, `GameServer:SetTime(hours, minutes,
  scale)`, `GameServer:SendGlobalChatMessage(text)`, chat/join/quit/update events.
- **Reading the sleep** *(unverified)*: the game fires `TESSleepStartEvent` when sleeping begins; its
  payload is believed to be start time and desired end time (floats). CommonLibSSE-NG only forward-declares
  the struct, so the plugin must define the layout and **log the values on first run to confirm**. The
  `SleepWaitMenu` class exists in CommonLibSSE-NG as an alternative source.
- **MCM**: MCM Helper needs a plugin named like the config folder with a quest carrying `MCM_ConfigBase`.
  Generate it with `tools/make_mcm_plugin.py SleepTogether`. Valid control types include `input`,
  `toggle`, `slider`, `enum`, `keymap`, `header` (not `textinput`).
- **Dependencies**: STR 1.8.4, STRPluginMessagingAPI + Bridge (0.10.1), the chat-relay resource, MCM
  Helper, SkyUI.
- **Repo/process**: new repo `SleepTogether`; bump the version for every zip; commit every change; push
  with the GitHub noreply email (private email is rejected). Only claim what was verified.

## Known risks the builder must resolve

1. **Server receives the message?** `strpm-chat-relay` cancels STRPM chat envelopes and drops
   server-addressed ones (`target == "server"` only returns true). Whether another Lua resource still
   sees the event is unknown. Options: handle `onChatMessage` in the new resource with the same envelope
   format; or patch the relay with a hook for server-addressed channels.
2. **`SetTime` needs a scale.** The Lua binding takes `(hours, minutes, scale)` and clamps scale to
   1 to 100. The resource must pass the server's current time scale; check whether Lua can read it.
3. **No party.** A player not in a party has no leader. *(my call)*: a player not in a party may advance
   time only when they are the only connected player. Check what `IsPartyLeader()` returns then.
4. **Menu behaviour under STR.** STR does not unfreeze the Sleep/Wait menu (its allow-list does not
   include it). The vanilla menu opens but may pause or behave oddly. Observe before changing anything.
5. **Wake time mapping.** The server stores time as hours with a fractional part; use the same minute
   encoding as the server's `CalendarService::SetTime`.

## Left to the builder

File layout, message wire format, throttling, log wording, MCM page layout, how the notification text
is shown (HUD notification is the default), and the test plan. Test in game: leader sleeps, non-leader
sleeps, leader sleeps with a non-leader in bed, disconnects during sleep.
